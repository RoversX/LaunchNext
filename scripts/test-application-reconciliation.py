#!/usr/bin/env python3
"""Run macOS application scan/layout regression tests without launching LaunchNext.

The harness compiles the current AppStore methods and SwiftData models verbatim.
Only icons, cache effects, UI notifications, and AppStore's unrelated state are
adapted. Every database is in memory; all application bundles are temporary.

Requires Xcode and a non-root account so chmod(000) produces real access errors.
Run from any directory: python3 scripts/test-application-reconciliation.py
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile


REPOSITORY = Path(__file__).resolve().parents[1]
DECLARATIONS = [
    "    private enum ApplicationReconciliationReason:",
    "    private var applicationSearchPaths:",
    "    private func normalizeApplicationPath(",
    "    private func standardizedFilePath(",
    "    func performInitialScanIfNeeded(",
    "    private func requestApplicationReconciliation(",
    "    private func schedulePendingApplicationReconciliation(",
    "    private func startPendingApplicationReconciliation(",
    "    private func finishApplicationReconciliation(",
    "    private func performApplicationReconciliation(",
    "    private func processScannedApplications(",
    "    private func isInsideAnotherApp(",
    "    private func isValidApp(",
    "    private func generateCacheAfterScan(",
    "    private func smartRebuildItemsWithOrderPreservation(",
    "    private func hasPersistedOrderData(",
    "    private func mergeCurrentOrderWithPersistedData(",
    "    private func loadFoldersFromPersistedData(",
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
]

# Optional only so --app-store can run the same behavioral checks against the
# original PR, which predates these helpers. Missing dependencies still produce
# a compiler error instead of being silently replaced with test logic.
AVAILABILITY_DECLARATIONS = [
    "    private func canonicalApplicationPath(",
    "    private func isApplicationPathUnavailable(",
    "    private func isApplicationPathInaccessible(",
]


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


def run_tests(directory: Path, app_store: Path) -> int:
    source = app_store.read_text()
    model_source = (REPOSITORY / "LaunchNext/FolderInfo.swift").read_text()
    models = "\n\n".join(
        "@Model\n" + declaration(model_source, f"final class {name}")
        for name in ("PageEntryData", "TopItemData")
    )
    declarations = DECLARATIONS + [marker for marker in AVAILABILITY_DECLARATIONS if marker in source]
    methods = "\n\n".join(declaration(source, marker) for marker in declarations)
    template = (
        REPOSITORY / "scripts/diagnostics/ApplicationReconciliationHarness.swift"
    ).read_text()
    for marker in ("// INSERT_PRODUCTION_MODELS", "    // INSERT_PRODUCTION_METHODS"):
        if template.count(marker) != 1:
            raise ValueError(f"Harness template must contain exactly one {marker}")
    generated = template.replace("// INSERT_PRODUCTION_MODELS", models).replace(
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
    print(f"Compiling {len(declarations)} production declarations and two SwiftData models…", flush=True)
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
    parser.add_argument("--keep-temp", action="store_true", help="Keep generated Swift and logs for diagnostics")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("These tests require macOS and Xcode's SwiftData implementation")
    if os.geteuid() == 0:
        parser.error("Run as a non-root user so permission-denied fixtures are meaningful")
    if args.keep_temp:
        directory = Path(tempfile.mkdtemp(prefix="launchnext-reconciliation-"))
        print(f"Diagnostic directory: {directory}")
        return run_tests(directory, args.app_store)
    with tempfile.TemporaryDirectory(prefix="launchnext-reconciliation-") as temporary:
        return run_tests(Path(temporary), args.app_store)


if __name__ == "__main__":
    raise SystemExit(main())
