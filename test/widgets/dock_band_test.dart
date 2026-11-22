import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flauncher/widgets/dock_band.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ByteData _solid(int width, int height, Color colour) {
  final data = ByteData(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    data.setUint8(i * 4, (colour.r * 255).round());
    data.setUint8(i * 4 + 1, (colour.g * 255).round());
    data.setUint8(i * 4 + 2, (colour.b * 255).round());
    data.setUint8(i * 4 + 3, (colour.a * 255).round());
  }
  return data;
}

Future<ui.Image> _image(Color colour) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 32, 18), Paint()..color = colour);
  return recorder.endRecording().toImage(32, 18);
}

/// Paints [painter] over black at 120x56 and returns the red channel at the tile's centre.
Future<int> _centreRed(WidgetTester tester, BandTilePainter painter) async {
  late int red;
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 120, 56), Paint()..color = Colors.black);
    painter.paint(canvas, const Size(120, 56));
    final image = recorder.endRecording().toImageSync(120, 56);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    red = bytes.getUint8((28 * 120 + 60) * 4);
    image.dispose();
  });
  return red;
}

void main() {
  group('bandArtColours', () {
    test('a white banner is bright and extends with white', () {
      final colours = bandArtColours(_solid(40, 20, Colors.white), 40)!;
      expect(colours.luma, closeTo(1, 0.01));
      expect(colours.edge, const Color(0xFFFFFFFF));
    });

    test('a blue banner extends with its blue and is not bright', () {
      final colours = bandArtColours(_solid(40, 20, const Color(0xFF0070D1)), 40)!;
      expect(colours.edge, const Color(0xFF0070D1));
      expect(colours.luma, lessThan(kBandBrightLuma));
    });

    test('a fully transparent picture has no colours', () {
      expect(bandArtColours(_solid(40, 20, const Color(0x00FFFFFF)), 40), isNull);
    });
  });

  group('BandGeometry', () {
    test('tiles plus a half at each edge fill the width exactly, at a 10 degree lean', () {
      const geometry = BandGeometry(960, 8);
      expect(geometry.pitch * 9, 960);
      expect(geometry.slotLeft(0), closeTo(-geometry.pitch / 2 + kBandGap / 2, 1e-9));
      expect(geometry.slotLeft(9) + geometry.pitch - kBandGap, greaterThan(960));
      expect(geometry.slant, closeTo(kBandTileHeight * 0.17633, 1e-3));
    });
  });

  group('BandTilePainter', () {
    testWidgets('a focused tile is at full strength', (tester) async {
      late ui.Image art;
      await tester.runAsync(() async => art = await _image(Colors.white));
      final red = await _centreRed(
        tester,
        BandTilePainter(image: art, edgeColour: Colors.white, bright: true, focused: true, slant: 10),
      );
      expect(red, greaterThan(250));
    });

    testWidgets('an unselected tile is muted to about 65%', (tester) async {
      late ui.Image art;
      await tester.runAsync(() async => art = await _image(Colors.white));
      final red = await _centreRed(
        tester,
        BandTilePainter(image: art, edgeColour: Colors.white, bright: false, focused: false, slant: 10),
      );
      expect(red, inInclusiveRange(160, 172));
    });

    testWidgets('an unselected bright tile is darker still', (tester) async {
      late ui.Image art;
      await tester.runAsync(() async => art = await _image(Colors.white));
      final red = await _centreRed(
        tester,
        BandTilePainter(image: art, edgeColour: Colors.white, bright: true, focused: false, slant: 10),
      );
      expect(red, inInclusiveRange(118, 130));
    });
  });
}
