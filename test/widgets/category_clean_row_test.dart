import 'package:flauncher/widgets/category_clean_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dockTileSize', () {
    test('keeps tiles at 82x42 while they fit', () {
      expect(dockTileSize(864, 8), const Size(82, 42));
      expect(dockTileSize(864, 3), const Size(82, 42));
    });

    test('shrinks every tile evenly, keeping the shape, when too many apps are in the dock', () {
      final size = dockTileSize(864, 20);
      // 20 tiles and 19 gaps of 12 fill the width exactly.
      expect(size.width * 20 + 19 * kDockMinTileGap, moreOrLessEquals(864));
      expect(size.width / size.height, moreOrLessEquals(82 / 42));
    });

    test('shares the width with a square tile as tall as the app tiles', () {
      expect(dockTileSize(864, 8, withSquareTile: true), const Size(82, 42));
      final size = dockTileSize(864, 20, withSquareTile: true);
      // 20 tiles, one square and 20 gaps of 12 fill the width exactly.
      expect(size.width * 20 + size.height + 20 * kDockMinTileGap, moreOrLessEquals(864));
    });

    test('never returns a negative size', () {
      expect(dockTileSize(10, 5).width, 0);
      expect(dockTileSize(864, 0), const Size(82, 42));
    });
  });
}
