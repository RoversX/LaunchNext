#!/usr/bin/env python3
"""Run macOS application scan/layout regression tests without launching LaunchNext.

The harness compiles the current AppStore methods and SwiftData models verbatim.
Only icons, cache effects, UI notifications, and AppStore's unrelated state are
adapted. Every database is in memory; all application bundles are temporary.
Discovery metadata uses a unique disposable UserDefaults suite per fixture.

Requires Xcode and a non-root account so chmod(000) produces real access errors.
Run from any directory: python3 scripts/test-application-reconciliation.py
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


REPOSITORY = Path(__file__).resolve().parents[1]
DECLARATIONS = [
    "    private enum ApplicationReconciliationReason:",
    "    private var applicationSearchPaths:",
    "    private func normalizeApplicationPath(",
    "    private func standardizedFilePath(",
    "    func removeCustomAppSource(path:",
    "    private func purgeMissingPlaceholders(",
    "    private func updateHiddenAppPaths(",
    "    func performInitialScanIfNeeded(",
    "    func reconcileApplicationsOnWindowShow(",
    "    func scanApplications(loadPersistedOrder:",
    "    private func requestApplicationReconciliation(",
    "    private func schedulePendingApplicationReconciliation(",
    "    private func startPendingApplicationReconciliation(",
    "    private func finishApplicationReconciliation(",
    "    private func performApplicationReconciliation(",
    "    private func processScannedApplications(",
    "    private func handleVolumeEvent(",
    "    private func generateCacheAfterScan(",
    "    private func hasPersistedOrderData(",
    "    private func mergeCurrentOrderWithPersistedData(",
    "    private func folderWithValidQuickLaunchPins(",
    "    private func reconcileFolderQuickLaunchPinsInCurrentLayout(",
    "    private func removableSourcePath(",
    "    private func placeholderDisplayName(",
    "    private func updateMissingPlaceholder(",
    "    private func shouldTrackMissingPlaceholder(",
    "    private func clearMissingPlaceholder(",
    "    private func currentMissingAppItem(",
    "    private func placeholderAppInfo(",
    "    private func refreshMissingPlaceholders(",
    "    func compactItemsWithinPages(",
    "    private func compactedItemsWithinPages(",
    "    func loadAllOrder(",
    "    private func loadOrderFromPageEntries(",
    "    private func loadOrderFromLegacyTopItems(",
    "    func saveAllOrder(",
    "    private func pruneHiddenAppsFromAppList(",
    "    private func sanitizedFolders(",
    "    private func filteredItemsRemovingHidden(",
    "    private func filteredFolderRemovingHidden(from folder: FolderInfo) ",
    "    private func filteredFolderRemovingHidden(from folder: FolderInfo, hidden:",
    "    func setCustomTitle(",
    "    private func applyCustomTitleOverride(",
]

# Keep --app-store compatible with earlier source snapshots. Extract each
# version's own methods; missing dependencies still cause a compiler error
# instead of being silently replaced with test logic.
VERSIONED_DECLARATIONS = [
    "    private func canonicalApplicationPath(",
    "    private func isApplicationPathUnavailable(",
    "    private func isApplicationPathInaccessible(",
    "    private func applicationTargetPath(",
    "    private func isApplicationPathAvailable(",
    "    private func smartRebuildItemsWithOrderPreservation(",
    "    private func loadFoldersFromPersistedData(",
    "    private func isInsideAnotherApp(",
    "    private func applicationSourcesDidChange(",
    "    private func invalidateApplicationDiscoveryForImportedLayout(",
    "    func applyOrderAndFolders(",
    "    func applyImportedOrderAndFolders(",
]

# Settings asks AppStore which apps a source provides. Older sources listed
# them by literal path in SettingsView; the fallback mirrors that query so
# those snapshots compile and show their listing behavior.
SOURCE_LISTING_MARKER = "    func isApplication(atPath path: String, providedBySource"
VERSIONED_DECLARATIONS.append(SOURCE_LISTING_MARKER)
SOURCE_LISTING_FALLBACK = """\
    func isApplication(atPath path: String, providedBySource source: String) -> Bool {
        ApplicationPath.isPath(URL(fileURLWithPath: path).standardized.path,
                               within: URL(fileURLWithPath: source).standardized.path)
    }"""


def declaration(source: str, marker: str) -> str:
    """Extract one declaration, ignoring braces inside strings and comments."""
    if source.count(marker) != 1:
        raise ValueError(f"Expected one declaration matching {marker!r}")
    start = source.index(marker)
    cursor = source.index("{", start)
    depth = 0
    while cursor < len(source):
        if source.startswith("//", cursor):
            cursor = source.find("\n", cursor)
            if cursor == -1:
                break
        elif source.startswith("/*", cursor):
            comments = 1
            cursor += 2
            while comments and cursor < len(source):
                if source.startswith("/*", cursor):
                    comments += 1
                    cursor += 2
                elif source.startswith("*/", cursor):
                    comments -= 1
                    cursor += 2
                else:
                    cursor += 1
        elif source[cursor] == '"':
            delimiter = '"""' if source.startswith('"""', cursor) else '"'
            cursor += len(delimiter)
            while cursor < len(source):
                if source[cursor] == "\\":
                    cursor += 2
                elif source.startswith(delimiter, cursor):
                    cursor += len(delimiter)
                    break
                else:
                    cursor += 1
        else:
            if source[cursor] == "{":
                depth += 1
            elif source[cursor] == "}":
                depth -= 1
                if depth == 0:
                    return source[start : cursor + 1]
            cursor += 1
    raise ValueError(f"Unterminated declaration matching {marker!r}")


def window_show_store_calls(lifecycle_root: Path) -> str:
    """Use the real call order for an already-loaded window, without AppKit UI."""
    app_source = (lifecycle_root / "LaunchNext/LaunchpadApp.swift").read_text()
    view_source = (lifecycle_root / "LaunchNext/LaunchpadView.swift").read_text()
    show = declaration(app_source, "    private func performShowWindow(")
    observer = declaration(view_source, "    private func setupWindowShownObserver(")
    notification = "NotificationCenter.default.post(name: .launchpadWindowShown"
    if show.count(notification) != 1:
        raise ValueError("Expected exactly one window-shown notification in performShowWindow")
    before, after = show.split(notification)

    def calls(block: str) -> list[str]:
        result = []
        for match in re.finditer(r"\b(?:self\.)?appStore\.([A-Za-z_]\w*)\s*\(", block):
            # Current lifecycle calls take no arguments. A changed signature
            # requires an explicit adapter rather than silently skipping it.
            if not re.match(r"\s*\)", block[match.end():]):
                raise ValueError(f"Window lifecycle call needs an adapter: {match.group(1)}")
            result.append(f"        {match.group(1)}()")
        return result

    ordered = calls(before) + calls(observer) + calls(after)
    if not ordered:
        raise ValueError("Window lifecycle has no AppStore calls to exercise")
    return "\n".join(ordered)


def run_tests(directory: Path, app_store: Path, lifecycle_root: Path = REPOSITORY) -> int:
    source = app_store.read_text()
    model_source = (REPOSITORY / "LaunchNext/FolderInfo.swift").read_text()
    models = "\n\n".join(
        "@Model\n" + declaration(model_source, f"final class {name}")
        for name in ("PageEntryData", "TopItemData")
    )
    declarations = DECLARATIONS + [marker for marker in VERSIONED_DECLARATIONS if marker in source]
    methods = "\n\n".join(declaration(source, marker) for marker in declarations)
    metadata_method = declaration(source, "    private func appInfo(from")
    methods += "\n" + metadata_method.replace("func appInfo(", "func productionAppInfo(", 1)
    # The harness wraps validation so a fixture can change the filesystem at a
    # precise point inside a background scan.
    validation_method = declaration(source, "    private func isValidApp(")
    methods += "\n" + validation_method.replace("func isValidApp(", "func productionIsValidApp(", 1)
    metadata_call = "productionAppInfo(from: url, preferredName: preferredName"
    if "includeCustomTitle:" in metadata_method:
        metadata_call += ", includeCustomTitle: includeCustomTitle"
    metadata_call += ")"
    template = (
        REPOSITORY / "scripts/diagnostics/ApplicationReconciliationHarness.swift"
    ).read_text()
    discovery_source = (REPOSITORY / "LaunchNext/ApplicationDiscovery.swift").read_text()
    # Invoke the real hook used by each version's source-property observer,
    # without installing filesystem watchers or changing user preferences.
    source_change_call = (
        "applicationSourcesDidChange()"
        if "    private func applicationSourcesDidChange(" in source
        else "requestApplicationReconciliation(reason: .sourceChange)"
    )
    import_call = (
        "applyImportedOrderAndFolders()"
        if "    func applyImportedOrderAndFolders(" in source
        else "applyOrderAndFolders()"
    )
    fallback_lines = [line for line in source.splitlines()
                      if line.startswith("    private static let applicationReconciliationFallbackInterval:")]
    if len(fallback_lines) != 1:
        raise ValueError("Expected one production window-show fallback interval")
    window_calls = window_show_store_calls(lifecycle_root)
    listing_fallback = "" if SOURCE_LISTING_MARKER in source else SOURCE_LISTING_FALLBACK
    for marker in ("// INSERT_PRODUCTION_DISCOVERY", "// INSERT_PRODUCTION_MODELS",
                   "// INSERT_PRODUCTION_APP_INFO", "// INSERT_METADATA_CALL",
                   "        // INSERT_SOURCE_CHANGE_CALL", "        // INSERT_IMPORT_CALL",
                   "        // INSERT_WINDOW_SHOW_CALLS", "    // INSERT_PRODUCTION_FALLBACK_INTERVAL",
                   "    // INSERT_SOURCE_LISTING_FALLBACK", "    // INSERT_PRODUCTION_METHODS"):
        if template.count(marker) != 1:
            raise ValueError(f"Harness template must contain exactly one {marker}")
    generated = template.replace("// INSERT_PRODUCTION_DISCOVERY", discovery_source).replace(
        "// INSERT_PRODUCTION_APP_INFO", (REPOSITORY / "LaunchNext/AppInfo.swift").read_text()
    ).replace("// INSERT_METADATA_CALL", metadata_call).replace(
        "// INSERT_PRODUCTION_MODELS", models
    ).replace("        // INSERT_SOURCE_CHANGE_CALL", "        " + source_change_call).replace(
        "        // INSERT_IMPORT_CALL", "        " + import_call
    ).replace("        // INSERT_WINDOW_SHOW_CALLS", window_calls).replace(
        "    // INSERT_PRODUCTION_FALLBACK_INTERVAL", fallback_lines[0]
    ).replace(
        "    // INSERT_SOURCE_LISTING_FALLBACK", listing_fallback
    ).replace(
        "    // INSERT_PRODUCTION_METHODS", methods
    )
    main = directory / "main.swift"
    main.write_text(generated)
    executable = directory / "application-reconciliation-tests"
    command = [
        "xcrun", "swiftc", "-swift-version", "5",
        "-module-cache-path", str(directory / "module-cache"),
        str(main), "-o", str(executable),
    ]
    print(f"Compiling {len(declarations)} production declarations, discovery runtime, and two SwiftData models…", flush=True)
    compiled = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (directory / "build.log").write_text(compiled.stdout)
    if compiled.returncode:
        print(compiled.stdout)
        return compiled.returncode
    # Use the platform temp directory. Foundation can return alternate /private
    # and non-/private spellings here; the fixture explicitly tests that case.
    tested = subprocess.run(
        [str(executable), str(directory / "fixtures")],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    (directory / "test.log").write_text(tested.stdout)
    if tested.returncode:
        print(tested.stdout)
    else:
        for line in tested.stdout.splitlines():
            if line.startswith(("PASS ", "SKIP ", "SUMMARY ")):
                print(line)
    return tested.returncode


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-store", type=Path, default=REPOSITORY / "LaunchNext/AppStore.swift",
                        help="AppStore source to test; useful for proving a regression fails before a fix")
    parser.add_argument("--lifecycle-source-root", type=Path, default=REPOSITORY,
                        help="Root containing LaunchNext/LaunchpadApp.swift and LaunchpadView.swift for window-show calls")
    parser.add_argument("--keep-temp", action="store_true", help="Keep generated Swift and logs for diagnostics")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("These tests require macOS and Xcode's SwiftData implementation")
    if os.geteuid() == 0:
        parser.error("Run as a non-root user so permission-denied fixtures are meaningful")
    if args.keep_temp:
        directory = Path(tempfile.mkdtemp(prefix="launchnext-reconciliation-"))
        print(f"Diagnostic directory: {directory}")
        return run_tests(directory, args.app_store, args.lifecycle_source_root)
    with tempfile.TemporaryDirectory(prefix="launchnext-reconciliation-") as temporary:
        return run_tests(Path(temporary), args.app_store, args.lifecycle_source_root)


if __name__ == "__main__":
    raise SystemExit(main())
