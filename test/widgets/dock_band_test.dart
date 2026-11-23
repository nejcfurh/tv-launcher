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

    test('a logo reaching the edge does not tint the extension colour', () {
      final data = _solid(40, 20, Colors.white);
      // Red logo strokes reaching the top and bottom edges, as in a tight banner crop.
      for (var y = 0; y < 20; y++) {
        for (var x = 8; x < 14; x++) {
          data.setUint8((y * 40 + x) * 4 + 1, 0);
          data.setUint8((y * 40 + x) * 4 + 2, 0);
        }
      }
      expect(bandArtColours(data, 40)!.edge, const Color(0xFFFFFFFF));
    });

    test('a fully transparent picture has no colours', () {
      expect(bandArtColours(_solid(40, 20, const Color(0x00FFFFFF)), 40), isNull);
    });
  });

  group('bandFlattenBackground', () {
    const width = 60, height = 30;
    const fill = Color(0xFF2050A0);

    /// A left-to-right blue gradient with a white block (the "logo") in the middle.
    ByteData gradientWithLogo({int edgeAlpha = 255}) {
      final data = ByteData(width * height * 4);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final o = (y * width + x) * 4;
          final logo = x >= 25 && x < 35 && y >= 10 && y < 20;
          final edge = x == 0 || y == 0 || x == width - 1 || y == height - 1;
          data.setUint8(o, logo ? 255 : 10 + x);
          data.setUint8(o + 1, logo ? 255 : 40 + x);
          data.setUint8(o + 2, logo ? 255 : 120 + 2 * x);
          data.setUint8(o + 3, edge ? edgeAlpha : 255);
        }
      }
      return data;
    }

    List<int> at(Uint8List rgba, int x, int y) => rgba.sublist((y * width + x) * 4, (y * width + x) * 4 + 3);

    test('turns a gradient background into one colour and keeps the logo', () {
      final flat = bandFlattenBackground(gradientWithLogo(), width, fill)!;
      expect(at(flat, 2, 5), [0x20, 0x50, 0xA0]);
      expect(at(flat, 57, 25), [0x20, 0x50, 0xA0]);
      expect(at(flat, 30, 15), [255, 255, 255]);
    });

    test('ignores a logo that touches the edge when modelling the background', () {
      final data = gradientWithLogo();
      // A bit of logo on the right edge, as a tight crop can cut one.
      for (var x = 57; x < width; x++) {
        for (var y = 14; y < 16; y++) {
          for (var c = 0; c < 3; c++) {
            data.setUint8((y * width + x) * 4 + c, 255);
          }
        }
      }
      final flat = bandFlattenBackground(data, width, fill)!;
      // The background between the logo and that edge, in the same rows, is still flattened.
      expect(at(flat, 45, 14), [0x20, 0x50, 0xA0]);
      expect(at(flat, 52, 15), [0x20, 0x50, 0xA0]);
    });

    test('flattens a radial glow even when the logo runs into the edge for most of its height', () {
      final data = ByteData(width * height * 4);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final o = (y * width + x) * 4;
          final glow = 60 - ((x - 15) * (x - 15) + (y - 12) * (y - 12)) ~/ 30;
          final logo = x >= 45 && y >= 5 && y < 25;
          data.setUint8(o, logo ? 255 : 10 + glow ~/ 2);
          data.setUint8(o + 1, logo ? 255 : 50 + glow);
          data.setUint8(o + 2, logo ? 255 : 150 + glow);
          data.setUint8(o + 3, 255);
        }
      }
      final flat = bandFlattenBackground(data, width, fill)!;
      for (final (x, y) in [(15, 12), (2, 28), (40, 15), (50, 2), (58, 28)]) {
        expect(at(flat, x, y), [0x20, 0x50, 0xA0], reason: '($x, $y)');
      }
      expect(at(flat, 52, 15), [255, 255, 255]);
    });

    test('leaves art with transparent edges (an icon) alone', () {
      expect(bandFlattenBackground(gradientWithLogo(edgeAlpha: 0), width, fill), isNull);
    });

    test('leaves art that is not mostly a smooth background (a photo) alone', () {
      final data = ByteData(width * height * 4);
      for (var i = 0; i < width * height; i++) {
        final v = (i * 97) % 256;
        data.setUint8(i * 4, v);
        data.setUint8(i * 4 + 1, 255 - v);
        data.setUint8(i * 4 + 2, (v * 3) % 256);
        data.setUint8(i * 4 + 3, 255);
      }
      expect(bandFlattenBackground(data, width, fill), isNull);
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

  group('BandEdgePainter', () {
    testWidgets('fades from clear at the screen edge to the half tile colour', (tester) async {
      late ByteData bytes;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(const Rect.fromLTWH(0, 0, 120, 56), Paint()..color = Colors.white);
        const BandEdgePainter(slant: 10, clearAt: 10, solidAt: 110).paint(canvas, const Size(120, 56));
        final image = recorder.endRecording().toImageSync(120, 56);
        bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        image.dispose();
      });
      int redAt(int x) => bytes.getUint8((28 * 120 + x) * 4);
      expect(redAt(10), greaterThan(250));
      expect(redAt(60), inInclusiveRange(135, 155));
      expect(redAt(108), lessThan(45));
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
