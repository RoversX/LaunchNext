# Folder Liquid Glass

Design notes, implementation constraints and measurement history for the
Appearance switch **Liquid Glass folder icons**.

Runnable probes and their commands live in
[`scripts/diagnostics/README.md`](../scripts/diagnostics/README.md).

---

## Verification status

Read this before citing anything below as a result.

- **The final main-app performance comparison has not been completed.** The Mac
  locked during the first CPU optimization test and ScreenCaptureKit returned
  `-3811` for both the unchanged baseline and the candidate. Preliminary CPU
  numbers from that period are excluded.
- **The historical probe measurements do not establish the current main app's
  GPU, frame-rate, memory or macOS 26 behaviour.** They are synthetic,
  process-level numbers from an isolated probe window, taken against an earlier
  revision of the overlay.
- Probe timer-interval p95 is **not** rendered FPS or GPU frame time, and
  excludes WindowServer's own work.
- Compiling against the macOS 26 deployment target is not a substitute for
  validating on a macOS 26 device.

## Scope

The switch is enabled once for both new and existing users, including
previously saved off values. The persisted marker
`folderLiquidGlassDefaultEnabledV1` prevents subsequent launches or preference
reloads from overriding a manual opt-out. Appearance reset restores on without
clearing the migration marker.

It affects only the Core Animation grid's folder icons. Turning it off restores
the existing CA backplates and releases the native glass overlay; it does not
change the already-glass opened-folder panel or the SwiftUI grid.

---

## Confirmed design constraints

These are established by the source and by the probe assertions listed in the
diagnostics README. They explain why the implementation is shaped the way it is.

### Material and containers

- Public `NSGlassEffectView`, style `.clear`, inside native effect containers
  with `spacing = 0`. No private API and no screen capture in the feature
  itself.
- Folder preview images share the existing CA bitmap. The original preview and
  backplate layers remain layout references and are hidden only while replaced.

### Paging

- **The complete native material subtree follows paging via `sublayerTransform`.**
  Two alternatives were ruled out by observed behaviour: moving only the content
  layer leaves AppKit's generated material behind, and changing the view layer's
  own `transform` is unsafe because AppKit resets it during initial layout. The
  reproduction was concrete — enabling glass on a later page left 100 of 100
  prepared backplates misaligned in the six-page probe. The subtree translation
  keeps material and previews aligned even when glass is first enabled on a
  later page, without a deferred refresh or timer.
- The effect surface is bounded to about three viewport widths, independent of
  total page count. Only nearby page batches are considered; distant batches are
  removed. Backplates inside this bounded surface stay prepared during swipes,
  avoiding per-column native hide/show layout work.
- Pure page translations reuse geometry and move only the effect group. Layout,
  content, hover/reorder animation and dragging still synchronise geometry.
  Changes to the nearby batch, viewport or effect-surface origin invalidate the
  fast path. Preview bitmaps continue to be shared rather than duplicated.
- A view-coordinate check alone is insufficient for paging; the probe includes
  the manual CA transform of the native effect group.

### Dragging

- Dragged folders use a separate stationary effect container and the drag
  layer's geometry. Plain pointer movement updates only root-attached drag
  content while reusing page geometry. Dragged apps stay above the backplates.
  Glass does not receive input.
- Pointer events update the drag immediately; the display link synchronises
  glass only for page or icon animations, not merely because a drag remains
  active. Reordering, hover scaling and page changes invalidate reuse.
- Drag start disables implicit actions while hiding source layers and creating
  the preview, and removes any existing source opacity animation. The older path
  set model opacity to zero but still presented about 0.92 opacity after 20 ms
  in the isolated probe, allowing the original CA image to overlap the drag
  preview.

### Drop and landing

- Single-item drops, both reordered and returned to the original cell, retain
  the lifted preview for a 0.18-second move/shrink to the destination icon.
  Reorders start immediately toward the proposed cell while the model updates
  asynchronously.
- The final destination is resolved by item identity, including across pages and
  subsequent compaction rebuilds; corrections continue from the current
  trajectory without jumping.
- Landing has an absolute 0.5-second upper bound in addition to the normal
  0.18-second duration. The bound adds no timer and uses the existing display
  link.
- Pure reorders during landing reuse page layers, bitmaps and native glass.
  Changed content uses a full rebuild, which preserves the native drag view. An
  explicit icon-cache refresh ends landing before refreshing content.
- At arrival, the native drag group and CA preview are removed together before
  revealing the grid icon. New pointer input, scrolling or window teardown
  finishes the handoff immediately.
- Creating/moving into folders retains the source preview while shrinking and
  fading it into the target, without revealing the old source before the
  asynchronous model update. A replaced target uses its snapshotted rect;
  rejected merges restore the source after bounded cleanup.
- Batch drops retain their existing behaviour. Cancellation still tears down
  immediately.

### Displayed operation

- A single-item drag stores one displayed operation: merge into a highlighted
  target, insert into a previewed slot, or return to the source. Mouse-up
  consumes that operation without a second pointer hit test.
- Merge targets use stable IDs, and a missing target cancels instead of becoming
  an insertion.
- Single-item feedback and gap movement update together after the 0.15-second
  insertion dwell. Merge feedback remains immediate and cancels pending
  insertion. Leaving a merge zone clears its highlight immediately.
- **Mouse-up never commits an insertion that has not yet been displayed.** This
  is a deliberate trade: it guarantees that what was shown is what happens, at
  the cost of discarding a release that arrives inside the dwell window. Page
  changes clear the previous page's preview.
- Batch dragging retains its existing handling.

### Reorder calculation

Single-item landing and model updates share `GridReorderPlan`: insertion,
cascade, per-page compaction and cross-page empty-page removal are calculated
before publishing. The model publishes and saves the final arrangement once,
with no delayed 0.1/0.5-second second move. Predictions include explicit empty
placeholders and the page offset after page removal. An unrelated publication of
the old order cannot redirect the preview back to its source cell.

This algorithm is covered by `LaunchNextTests/GridReorderPlanTests.swift`.

### Previews, animation and lifecycle

- Folder rebuilds retain the previous same-ID bitmap until the refreshed preview
  arrives. This is a layer-to-layer handoff, not an added image cache.
- Rebuilt CA layers use a cache-only synchronous lookup before scheduling
  background rendering. Cache keys retain folder content, size and scale
  validation. Async completion ignores detached layers and directly updates the
  matching glass bitmap, without a geometry pass or new native view.
- External folder-to-grid handoff reasserts source hiding after a rebuild even
  when its index has not changed, with no implicit opacity fade.
- Neighbour movement uses explicit position animations from the presentation
  position: 0.45-second easing during hover, and 0.18 seconds for final
  landing/layout corrections, including row wrapping. Repeated publications of
  the same destination retain the current animation instead of restarting it.
- Existing display-link callbacks follow hover/reorder animations for at most
  0.5 seconds after changes. There is no new timer or display link. Hiding or
  detaching the grid and turning the preference off remove the glass views.
- Ordinary-app hover and press do not schedule glass geometry work; unchanged
  folder transforms do not extend the synchronisation deadline.

---

## Changes whose main-app effect is not yet established

Keep these separate from the confirmed constraints above. The mechanism is
understood; the user-visible improvement is not demonstrated.

### Combined paging transaction

The main grid synchronises native folder glass before committing its page
translation, including gesture tracking, mouse page dragging, animated paging
and layout/snap paths. Both trees use one outer CA transaction. Pure paging
still uses the existing group translation and geometry reuse; this adds no image
cache, view, timer or per-icon geometry pass.

A moving red/green marker screenshot experiment returned at most 0.5 pixel
alignment error for both transaction modes (30 captures each). **It did not
reproduce the larger transient displacement that motivated the change.** The
change removes a commit boundary but is not a verified fix for that symptom.

`--glass --split-scroll-commit` reproduces the former commit ordering for
comparison.

### CPU optimisation

The optimisation removes repeated per-column hide/show work and bypasses
per-icon geometry traversal on pure page translations. A local sample of the
intermediate buffered version identified repeated layer coordinate conversion,
sublayer-array bridging and presentation-layer reads in the sync path.

Native checks cover geometry, page reuse, bounded culling, nearby-batch
invalidation, drag-only position updates, leaving/re-entering the viewport, drag
scale/position, source hiding, reset and deallocation. **These are correctness
checks; the CPU benefit in the running app is unmeasured** — see Verification
status.

---

## Historical measurement (2026-09-16, macOS 27)

Taken **before** the pure-paging fast path, against the earlier
viewport-culling probe. One sequential pass, 980 × 680 point content area, 12 s
of continuous synthetic paging per case, built with `swiftc -O`, no concurrent
build or profiler. Process measurements, not whole-system or GPU totals.

| Folders per page | Style | CPU seconds / 12 s | Sampled peak physical footprint |
| --- | --- | ---: | ---: |
| 6 | Original CA | 0.2653 | 16.53 MiB |
| 6 | Clear glass | 1.0981 | 18.86 MiB |
| 35 | Original CA | 0.2900 | 16.70 MiB |
| 35 | Clear glass | 2.4546 | 28.75 MiB |

The glass version has measurable overhead in the probe. The switch can restore
the original style. **No claim of unchanged FPS or GPU cost is supported by
these numbers**, and they describe an earlier revision, not current `main`.

Validation completed for that earlier revision: Release app build, native
overlay behaviour/lifecycle checks, all 14 localization entries, and visual
inspection of normal, half-page and scaled folder-drag screenshots from the
synthetic window. The drag source is empty while the dragged folder's clear
backplate and preview move together. The probe uses the production overlay but
not the complete LaunchNext event/input stack.

---

## Main-app acceptance checklist

Still required; none of the probes substitute for it.

Build Release once and compare both positions of the Appearance switch using the
same folder layout. Check sparse and full pages, rapid paging, hover/press
scale, folder drag and cancellation, drag across pages, application drag over
folders, search/result changes, repeated show/hide and preference switching.
Confirm the source folder leaves no backplate behind and returns after
cancellation. Check both light/dark appearance and multiple display scale
factors.

Pointer acceptance must also cover movement at the configured merge-zone
boundary (including the default 1.6 icon widths), expanded-target release
outside the icon's smaller click rectangle, moving back out to insertion,
folder-to-slot drags, row/page boundaries and both glass modes.

Use Instruments **Animation Hitches** / **Metal System Trace** to inspect actual
frame delivery and GPU work, and **Time Profiler** for CPU attribution. Compare
memory after the same workload and after hiding; also check that memory does not
grow across repeated cycles. The app's existing FPS display is not sufficient
for this comparison. **Do not change defaults solely on a synthetic CPU result.**
