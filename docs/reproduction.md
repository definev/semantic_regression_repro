# How the repro works

Semantics remain enabled globally. The workspace contains 500 retained panes, each with 64 semantic cells, beneath one `ExcludeSemantics` widget.

One second after startup, each cell changes width once. Flutter lays out the cells again and marks their semantics geometry dirty. The workspace then remains static while an ancestor transform moves the camera.

On the affected framework, `PipelineOwner.flushSemantics()` keeps revisiting deferred geometry updates beneath the excluded subtree. The cost continues after the cells stop changing. The patch keeps deferred state on each render object's semantics data and queues the work when parent data becomes available again.

The regression was introduced by [Flutter PR #192146](https://github.com/flutter/flutter/pull/192146). The included comparison uses framework commit `047cf8e385aee01751767268e275c92670ebf52c` before and after the local patch.

## Measurements

UI time covers the complete synchronous `WidgetsFlutterBinding.drawFrame()` call, including semantics. Semantics time covers the root `PipelineOwner.flushSemantics()` call and its child pipeline owners. Raster time comes from `FrameTiming` and appears in the JSON results.

The HUD frame rate counts camera animation ticks over wall-clock time. It can include pauses caused by desktop activity or display scheduling.

The chart uses a fixed scale from 0 to 60 ms. Each bar shows the maximum frame time within a group of samples. The dashed line marks the 16.67 ms budget for 60 Hz.

The demo caches the workspace between HUD updates. Those updates do not rebuild all 32,000 cells during the measurement window.

## Repository copy

`lib/main.dart` contains the standalone demo. It defaults to the neutral label `CURRENT SDK`, reports the actual build mode, and prints the result path.

`docs/measurements/visual_repro.dart` preserves the exact source used for the screenshots. Its source hash is recorded in `visual-manifest.json`. The screenshots and raw measurements are unchanged.
