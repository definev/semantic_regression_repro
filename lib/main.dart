import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
// Keep the SDK import to support affected versions before Material was extracted.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

const variant = String.fromEnvironment('VARIANT', defaultValue: 'CURRENT SDK');
const buildMode = kReleaseMode
    ? 'release'
    : (kProfileMode ? 'profile' : 'debug');
const buildLabel = kReleaseMode
    ? 'Release AOT'
    : (kProfileMode ? 'Profile' : 'Debug');
const paneCount = 500;
const cellsPerPane = 64;
final semanticsSamples = <double>[];
final uiSamples = <double>[];
bool captureMeasurements = false;

final class MeasuredPipelineOwner extends PipelineOwner {
  MeasuredPipelineOwner()
    : super(onSemanticsUpdate: (update) => update.dispose());

  @override
  void flushSemantics() {
    final watch = Stopwatch()..start();
    super.flushSemantics();
    if (captureMeasurements) {
      semanticsSamples.add(watch.elapsedMicroseconds / 1000);
    }
  }
}

class MeasuredBinding extends WidgetsFlutterBinding {
  @override
  PipelineOwner createRootPipelineOwner() => MeasuredPipelineOwner();

  @override
  void drawFrame() {
    final watch = Stopwatch()..start();
    super.drawFrame();
    if (captureMeasurements) uiSamples.add(watch.elapsedMicroseconds / 1000);
  }
}

void main() {
  final binding = MeasuredBinding();
  binding.ensureSemantics();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: Demo()));
}

class Demo extends StatefulWidget {
  const Demo({super.key});
  @override
  State<Demo> createState() => _DemoState();
}

class _DemoState extends State<Demo> with SingleTickerProviderStateMixin {
  late final AnimationController camera = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();
  final ui = uiSamples;
  final raster = <double>[];
  final frames = <double>[];
  final clock = Stopwatch()..start();
  Timer? timer;
  int lastTick = 0;
  int count = 0;
  bool collecting = false;
  bool finished = false;
  Map<String, dynamic>? result;
  late Widget workspace = board();
  bool expandedCells = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(onTimings);
    camera.addListener(onTick);
    Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        expandedCells = true;
        workspace = board();
      });
    });
    timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || finished) return;
      final elapsed = clock.elapsedMilliseconds;
      if (!collecting && elapsed >= 5000) {
        collecting = true;
        semanticsSamples.clear();
        uiSamples.clear();
        captureMeasurements = true;
      }
      if (elapsed >= 15000) {
        finished = true;
        captureMeasurements = false;
        result = {
          'variant': variant,
          'mode': buildMode,
          'panes': paneCount,
          'excluded_semantic_cells': paneCount * cellsPerPane,
          'measurement_seconds': 10,
          'frames': count,
          'fps': count / 10,
          'ui': stats(ui),
          'raster': stats(raster),
          'semantics': stats(semanticsSamples),
          'interval': stats(frames),
          'ui_over_16_67_ms': ui.where((v) => v > 1000 / 60).length,
          'raw_ui_ms': ui,
          'raw_raster_ms': raster,
          'raw_semantics_ms': List<double>.of(semanticsSamples),
        };
        final variantName = variant.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]+'),
          '-',
        );
        final destination =
            '${Directory.systemTemp.path}/semantics-$variantName.json';
        File(destination).writeAsStringSync(jsonEncode(result));
        debugPrint('Measurements saved to $destination');
        debugPrint(
          'VISUAL_RESULT ${jsonEncode(result!.map((k, v) => MapEntry(k, k.startsWith('raw_') ? (v as List).length : v)))}',
        );
        timer?.cancel();
      }
      setState(() {});
    });
  }

  void onTick() {
    final now = clock.elapsedMicroseconds;
    if (collecting && !finished) {
      count++;
      if (lastTick > 0) frames.add((now - lastTick) / 1000);
    }
    lastTick = now;
  }

  void onTimings(List<FrameTiming> timings) {
    if (!collecting || finished) return;
    for (final frame in timings) {
      raster.add(frame.rasterDuration.inMicroseconds / 1000);
    }
  }

  Map<String, double> stats(List<double> values) {
    if (values.isEmpty) return {'mean': 0, 'p50': 0, 'p95': 0};
    final sorted = List<double>.of(values)..sort();
    return {
      'mean': values.reduce((a, b) => a + b) / values.length,
      'p50': sorted[(sorted.length * .5).floor()],
      'p95': sorted[math.min(sorted.length - 1, (sorted.length * .95).floor())],
    };
  }

  @override
  void dispose() {
    timer?.cancel();
    camera.removeListener(onTick);
    camera.dispose();
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = variant.startsWith('BEFORE')
        ? const Color(0xffff826c)
        : const Color(0xff55e0b2);
    final data = result;
    return Scaffold(
      backgroundColor: const Color(0xff0e1422),
      body: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: 'Menlo',
          fontSize: 12,
          color: Color(0xffe2e9f4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
              child: Row(
                children: [
                  Container(width: 4, height: 38, color: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SEMANTICS / CAMERA STRESS TEST',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          '500 retained panes  /  32,000 excluded semantic cells',
                        ),
                      ],
                    ),
                  ),
                  Text(
                    variant,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  metric(
                    'UI MEAN',
                    data == null
                        ? '--'
                        : '${(data['ui']['mean'] as double).toStringAsFixed(2)} ms',
                    accent,
                  ),
                  metric(
                    'UI P95',
                    data == null
                        ? '--'
                        : '${(data['ui']['p95'] as double).toStringAsFixed(2)} ms',
                    accent,
                  ),
                  metric(
                    'SEMANTICS MEAN',
                    data == null
                        ? '--'
                        : '${(data['semantics']['mean'] as double).toStringAsFixed(2)} ms',
                    accent,
                  ),
                  metric(
                    'FRAME RATE',
                    data == null
                        ? '--'
                        : '${(data['fps'] as double).toStringAsFixed(1)} fps',
                    accent,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              child: Text(
                finished
                    ? '10 s sample complete  |  $buildLabel  |  Semantics enabled globally'
                    : collecting
                    ? 'Measuring 10 seconds of camera motion...'
                    : 'Warming up for 5 seconds...',
                style: const TextStyle(color: Color(0xff91a5bf)),
              ),
            ),
            Expanded(
              child: ClipRect(
                child: ColoredBox(
                  color: const Color(0xff141e30),
                  child: AnimatedBuilder(
                    animation: camera,
                    child: workspace,
                    builder: (context, child) {
                      final phase = camera.value * math.pi * 2;
                      return OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: 5000,
                        maxWidth: 5000,
                        minHeight: 2800,
                        maxHeight: 2800,
                        child: Transform.translate(
                          offset: Offset(
                            -1600 - math.sin(phase) * 1200,
                            -800 - math.cos(phase) * 650,
                          ),
                          child: child,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            Container(
              height: 104,
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'UI FRAME TIME    -- 16.67 ms budget at 60 Hz',
                    style: TextStyle(fontSize: 11, color: Color(0xff91a5bf)),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: CustomPaint(
                      painter: FrameChart(List<double>.of(ui), accent),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget metric(String label, String value, Color accent) => Expanded(
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xff1b273b),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xff91a5bf)),
          ),
          const SizedBox(height: 7),
          Text(
            value,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    ),
  );

  Widget board() => ExcludeSemantics(
    child: SizedBox(
      width: 5000,
      height: 2800,
      child: Stack(
        children: List.generate(paneCount, (i) {
          final color = [
            const Color(0xff49a5ff),
            const Color(0xffb69aff),
            const Color(0xffffbf69),
            const Color(0xff55d6b4),
          ][i % 4];
          return Positioned(
            left: (i % 25) * 200.0 + 8,
            top: (i ~/ 25) * 140.0 + 8,
            width: 184,
            height: 124,
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xff202e46),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: .5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(width: 6, height: 6, color: color),
                          const SizedBox(width: 7),
                          Text(
                            'PANE ${i.toString().padLeft(3, '0')}',
                            style: TextStyle(color: color, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 3,
                        runSpacing: 3,
                        children: List.generate(
                          cellsPerPane,
                          (j) => Semantics(
                            label: 'Pane $i cell $j',
                            child: SizedBox(
                              width: expandedCells ? 15 : 14,
                              height: 7,
                              child: ColoredBox(
                                color: color.withValues(
                                  alpha: .25 + ((i + j) % 5) * .13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    ),
  );
}

class FrameChart extends CustomPainter {
  FrameChart(this.values, this.color);
  final List<double> values;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    const scale = 60.0;
    final lineY = size.height * (1 - (1000 / 60) / scale);
    final dash = Paint()
      ..color = const Color(0xff798aa3)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 10) {
      canvas.drawLine(Offset(x, lineY), Offset(x + 5, lineY), dash);
    }
    if (values.isEmpty) return;
    final paint = Paint()..color = color.withValues(alpha: .8);
    final bins = math.min(200, values.length);
    for (var b = 0; b < bins; b++) {
      final start = b * values.length ~/ bins;
      final end = math.max(start + 1, (b + 1) * values.length ~/ bins);
      final value = values.sublist(start, end).reduce(math.max);
      final h = math.min(size.height, value / scale * size.height);
      canvas.drawRect(
        Rect.fromLTWH(
          b * size.width / bins,
          size.height - h,
          math.max(1, size.width / bins - 1),
          h,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(FrameChart oldDelegate) => true;
}
