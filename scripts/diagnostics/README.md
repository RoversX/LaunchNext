# Grid and folder-glass diagnostics

Manual probes for the Core Animation grid and the folder Liquid Glass overlay.

Design rationale, implementation constraints, measurement history and the
outstanding acceptance work live in
[`Documentation/FolderLiquidGlass.md`](../../Documentation/FolderLiquidGlass.md).

## What these are, and what they are not

The older probes compile **real production source** together with a **simplified
host**: a minimal `CAGridView`, model types and layer tree, built just far
enough to exercise the extension under test.

That shape is deliberate — it keeps the checks close to shipping behaviour
without booting the app — but it has hard limits:

- They do **not** exercise `AppStore`, the real reorder callbacks, or persistence.
- They do **not** exercise the real input stack: pointer hit testing, event
  timing, gesture recognition and drag sessions are all synthetic.
- They do **not** replace main-app visual acceptance, and their CPU numbers are
  process-level probe measurements, not app, WindowServer or GPU cost.
- Their simplified model types can drift from production. When a production type
  changes, a probe can keep compiling while no longer representing it. Treat a
  passing probe as evidence about the extension it hosts, not about the app.

The production-grid merge integration check below is an exception: it compiles
the full app target with a replacement entry point, without shadow grid/model
types. Its model callbacks still use fixtures rather than AppStore.

Nothing here runs in CI, and none of it ships in LaunchNext.

## Reorder algorithm

Now covered by a real unit test against the same production source, not a probe:

```sh
xcodebuild test -scheme LaunchNext -destination 'platform=macOS' \
  -only-testing:LaunchNextTests/GridReorderPlanTests
```

`LaunchNext/GridReorderPlan.swift` is compiled into the `LaunchNextTests` target
directly, so there is no copy of the algorithm to keep in sync. Covers trailing
and interior hole compaction, forward/backward cascade, new-page creation,
emptied-page removal, the final destination index, and an exhaustive sweep of
every occupancy mask for 1–8 slots against page sizes 1–4.

## Visual policy check

```sh
python3 scripts/diagnostics/check_grid_visual_policy.py
```

Checks that ordinary-app hover/press does not schedule glass geometry work, that
actual folder scaling still synchronises, that unchanged transforms do not
extend the deadline, and that missing placeholders reuse only when their content
is unchanged. Also checks that folder creation keeps the target app at its
normal size while merging into an existing folder retains its scaling feedback.

**This is not a lint and not an integration test.** It extracts production
methods out of `CAGridView+Input.swift`, `CAGridView+Layout.swift` and
`CAGridView+FolderGlass.swift` by literal source-text markers, concatenates them
with its own redefined model types, then compiles and runs the result. It
therefore carries the same model-drift risk as the probes, plus a direct
coupling to method names, signatures and source ordering: renaming or moving one
of the extracted methods, or changing `syncFolderGlass`'s signature, breaks the
extraction rather than failing an assertion. Fix the fixture when that happens —
do not weaken the assertions to make it pass.

## Folder glass overlay

```sh
xcrun swiftc -O -parse-as-library \
  -module-cache-path /tmp/launchnext-glass-module-cache \
  LaunchNext/FolderGlassOverlay.swift \
  scripts/diagnostics/FolderGlassProbe.swift \
  -o /tmp/launchnext-folder-glass-probe
/tmp/launchnext-folder-glass-probe --check
```

Covers geometry, page reuse, bounded culling, nearby-batch invalidation,
drag-only position updates, leaving and re-entering the viewport, drag
scale/position, source hiding, reset and deallocation. It reads
`FolderGlassOverlay.activeGlassCount`, which exists in production as an
observation hook for these assertions and is never evaluated on a running frame.

Creation checks verify that a growing backplate reuses one native glass view,
shares the target bitmap at a fixed size outside the glass content bounds, and
restores the original icon and removes the sibling preview on cleanup.

Screenshot modes capture only the probe's own synthetic window via
`SCShareableContent.currentProcess`, writing to `/tmp/launchnext-folder-*.png`.
This capture code is compiled only into the probe, not into LaunchNext.

| Flag | What it does |
| --- | --- |
| `--still` | leaves the probe window open |
| `--screenshot` | captures the probe window, then exits |
| `--shift` / `--drag` | half-page swipe, or a scaled dragged folder |
| `--start-late --toggle --screenshot` | six pages, 80-point gap, start on page four, toggle glass three times |
| `--drop --screenshot` | offset drag preview, removal, source restoration, capture after 20 ms |
| `--drag-start --screenshot` | asserts presentation opacity is zero with no opacity animation (`--legacy-start` reproduces the former fade) |
| `--split-scroll-commit` | reproduces the former separate page-commit ordering |
| `--sparse` | 6 folders per page instead of 35 |

Screenshot checks assert native geometry matches the source layers after
AppKit's backing/layout pass. Capture completion is asynchronous and may land
after the transition, so the presentation-state assertions — not the eventual
image — are what verify timing.

### Repeatable performance workload

```sh
/tmp/launchnext-folder-glass-probe
/tmp/launchnext-folder-glass-probe --glass
/tmp/launchnext-folder-glass-probe --sparse
/tmp/launchnext-folder-glass-probe --glass --sparse
```

Run **sequentially**, with no build, profiler or other benchmark running. Keep
the display, refresh rate, window size, appearance and foreground state the
same, and keep the Mac unlocked with the probe window visible. Each run pages
between two synthetic pages for 12 seconds and exits. An occluded or locked
probe aborts rather than reporting a misleading result; discard any run
reporting `INVALID`. Repeat in reverse order when evaluating a release.

Output is process CPU seconds, sampled peak physical footprint, peak unhidden
native backplate count (including prepared neighbouring pages) and timer
interval p95. **Timer interval p95 is not rendered FPS or GPU frame time**, and
these numbers exclude WindowServer entirely. Do not change defaults on a
synthetic CPU result alone.

## Drag landing

```sh
xcrun swiftc -O -parse-as-library \
  -module-cache-path /tmp/launchnext-glass-module-cache \
  LaunchNext/GridDragDrop.swift \
  LaunchNext/FolderGlassOverlay.swift \
  LaunchNext/CAGridView+DragLanding.swift \
  scripts/diagnostics/DragLandingProbe.swift \
  -o /tmp/launchnext-drag-landing-probe
/tmp/launchnext-drag-landing-probe
```

Covers classic/glass move and scale continuity, icon-versus-label geometry,
movement before model publication, post-reorder identity, layer reuse with a
changed-content fallback, cross-page coordinates, continuous correction during a
second rebuild, native material retention, interruption and new-drag cleanup, an
unpublished reorder, and an item disappearing. It also drives the target
continuously until the absolute 0.5-second landing bound, then checks preview
removal and source restoration in both classic and glass modes for return and
fallback merge landings, and covers an old-order refresh arriving before the reorder plus
empty-page removal during landing — both must retain the same target and
animation start time.

It uses a simplified `LaunchpadItem` whose content comparison is `id` plus a
version counter, so it exercises reuse *dispatch*, not the production
`hasSameGridContent`. It does not exercise the app's reorder callbacks, and it
cannot judge how the animation feels.

## Drop preview

```sh
xcrun swiftc -O -parse-as-library \
  -module-cache-path /tmp/launchnext-glass-module-cache \
  LaunchNext/GridDragDrop.swift \
  LaunchNext/CAGridView+DropPreview.swift \
  scripts/diagnostics/DropPreviewProbe.swift \
  -o /tmp/launchnext-drop-preview-probe
/tmp/launchnext-drop-preview-probe
```

Covers insertion dwell, merge/insert transitions followed by immediate release,
stale timer cancellation, target identity after reorder, missing targets and
sources, and explicit neighbour motion and retargeting. It verifies that the
operation actually dispatched to the owner is the one that was displayed.

Pointer hit testing stays a main-app acceptance check: movement at the
merge-zone boundary (default 1.6 icon widths), expanded-target release outside
the icon's smaller click rectangle, moving back out to insertion, folder-to-slot
drags, row and page boundaries, and both glass modes.

## Production-grid folder merge integration

```sh
python3 scripts/diagnostics/run_folder_merge_integration.py
# Optional recording of only the verifier window (no audio or other apps):
python3 scripts/diagnostics/run_folder_merge_integration.py --record
# Focused rebuild/state regression, without requiring display-link frames:
python3 scripts/diagnostics/run_folder_merge_integration.py --hover-rebuild-only
# Deterministic robustness and cold-icon handoff checks:
python3 scripts/diagnostics/run_folder_merge_integration.py --guardrails-only
```

Requires an unlocked macOS GUI session and Xcode. Builds a temporary copy of
the app target, replacing its entry point with `FolderMergeIntegration.swift`.
The production CAGridView, input/landing/layout, FolderInfo renderer and native
glass are used unchanged. It neither invokes AppDelegate/AppStore nor loads or
saves the user's launcher layout. The installed app is not replaced.

The focused mode checks app/folder merge highlights after duplicate publication,
target movement/removal, and preservation of entrance timing in classic/glass
styles. It explicitly advances the production highlight update for its state
assertion; it does not validate compositor animation or frame rate. The full
mode requires live display-link callbacks and fails with a bounded timeout if
the temporary host does not receive them.

Guardrail mode uses a disposable preferences suite for migration checks, injects
zero-sized merge layers and orphan state, verifies preview crop row order at a
scaled display size, and exercises cold-grid bitmap handoff and state release.
It does not instantiate AppStore or mutate the user's preferences. These checks
do not establish full-app frame rate, GPU cost, or memory-footprint improvements.

Checks classic/glass creation, model publication delayed by 120 ms, actual
intermediate CA presentation scale, opaque visible-slot arrival, overflow fade,
repeated model publication, rejected merges, cancellation and layer cleanup.
The callback deliberately compacts the fixture model to exercise a moving
destination. Recording uses ScreenCaptureKit **only in this diagnostic entry
point**, selecting its own process window. Video is written to
`/tmp/launchnext-merge-integration.mp4`; build output goes to
`/tmp/launchnext-folder-merge-integration-build.log`. The temporary project and
binary are removed at exit.

This goes beyond the simplified landing probe, but it still does not exercise
AppStore persistence, SwiftUI publication timing, real mouse/trackpad gesture
input, full-app responsiveness, GPU cost or memory benchmarks.

The same production-grid integration run also checks folder dissolution through
the production notification observer: two/ten apps, initial full-size native
backplate, intermediate growth, overflow, neighbor movement, repeated publication,
no-op cleanup, window teardown and disabled animations. Creation asserts that
neighbor compaction animates and survives a duplicate publication. The fixture
publishes replacement items; it does not execute the AppStore dissolve method.
