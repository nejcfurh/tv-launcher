import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flauncher/flauncher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Paints the scrims over a white picture at 1920x1080 and returns a red-channel reader.
Future<int Function(double x, double y)> _paintOverWhite(WidgetTester tester, CinematicScrimPainter painter) async {
  const size = Size(1920, 1080);
  late ByteData bytes;
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    painter.paint(canvas, size);
    final image = recorder.endRecording().toImageSync(size.width.toInt(), size.height.toInt());
    bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
  });
  return (x, y) => bytes.getUint8(((y * size.height).floor().clamp(0, 1079) * 1920 + (x * size.width).floor().clamp(0, 1919)) * 4);
}

void main() {
  testWidgets('a Watch Next picture is dimmed to 80% where no scrim reaches', (tester) async {
    final red = await _paintOverWhite(tester, const CinematicScrimPainter(dim: true));
    expect(red(0.6, 0.4), inInclusiveRange(200, 206));
  });

  testWidgets('the wallpaper is not dimmed', (tester) async {
    final red = await _paintOverWhite(tester, const CinematicScrimPainter(leftScrim: false));
    expect(red(0.6, 0.4), 255);
  });

  testWidgets('the lower third, where services bake their logo, is at most 60% bright', (tester) async {
    final red = await _paintOverWhite(tester, const CinematicScrimPainter(dim: true));
    // 20% to 40% up from the bottom edge, right of the hero text.
    for (final y in [0.6, 0.7, 0.8]) {
      expect(red(0.6, y), lessThanOrEqualTo(153), reason: 'y = $y');
    }
    expect(red(0.6, 0.999), lessThan(70), reason: 'bottom edge');
  });

  testWidgets('the area behind the date and time is darker than the rest of the top edge', (tester) async {
    final red = await _paintOverWhite(tester, const CinematicScrimPainter(leftScrim: false));
    final clock = red(0.86, 0.06);
    final middle = red(0.5, 0.06);
    expect(middle - clock, greaterThanOrEqualTo(50), reason: 'clock $clock, middle $middle');
  });
}
