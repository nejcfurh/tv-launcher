/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Dock tile size at its largest; tiles shrink evenly when more apps than fit are in the dock.
const kDockTileMaxWidth = 82.0;
const kDockTileHeight = 42.0;
const kDockTileFocusedScale = 1.14;
const kDockFocusDuration = Duration(milliseconds: 160);

const _kRingGap = 2.0;
const _kRingWidth = 2.0;
const _kRingOutset = _kRingGap + _kRingWidth;

/// The white ring around a focused dock tile: a separate shape [_kRingGap] outside the tile, so
/// it stays concentric with the tile's corners. Place it in a non-clipping [Stack] that is scaled
/// together with the tile.
class DockFocusRing extends StatelessWidget {
  final double tileRadius;
  final bool visible;

  const DockFocusRing({super.key, required this.tileRadius, required this.visible});

  @override
  Widget build(BuildContext context) => Positioned(
    left: -_kRingOutset,
    top: -_kRingOutset,
    right: -_kRingOutset,
    bottom: -_kRingOutset,
    child: IgnorePointer(
      child: AnimatedOpacity(
        key: const Key("dock_focus_ring"),
        opacity: visible ? 1 : 0,
        duration: kDockFocusDuration,
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tileRadius + _kRingOutset),
            border: Border.all(color: Colors.white, width: _kRingWidth),
          ),
        ),
      ),
    ),
  );
}

/// The drop shadow under a focused dock tile.
class DockTileShadow extends StatelessWidget {
  final double tileRadius;
  final bool visible;

  const DockTileShadow({super.key, required this.tileRadius, required this.visible});

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: AnimatedContainer(
        duration: kDockFocusDuration,
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tileRadius),
          boxShadow: visible
              ? const [BoxShadow(color: Color(0x80000000), offset: Offset(0, 6), blurRadius: 16)]
              : const [],
        ),
      ),
    ),
  );
}

/// A 1 physical pixel, 12% white line just inside the tile's edge, so dark tiles keep their shape
/// on a dark tray. Tiles whose artwork is mostly dark ([dark]) get a 1 dp, 25% line instead: the
/// hairline alone left them barely separate from the tray on the TV.
class DockTileInnerBorder extends StatelessWidget {
  final double tileRadius;
  final bool dark;

  const DockTileInnerBorder({super.key, required this.tileRadius, this.dark = false});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tileRadius),
        border: Border.all(
          color: dark ? const Color(0x40FFFFFF) : const Color(0x1FFFFFFF),
          width: dark ? 1 : 1 / MediaQuery.devicePixelRatioOf(context),
        ),
      ),
    ),
  );
}

/// Mean Rec. 709 luma (0–1) of a tile's edge band at or below which the tile counts as dark.
/// Measured on the TV's dock: black tile 0.0x, Apple TV dark grey 0.1x; PS5 blue, Disney+ teal,
/// white Netflix and YouTube well above.
const double kDarkTileLumaThreshold = 0.16;

/// Whether RGBA artwork of [width] pixels per row is dark along its edges (the outer 10% on each
/// side), which is what has to stand apart from the tray. Transparent pixels count as dark, since
/// the tray shows through them.
bool isDarkTileArt(ByteData rgba, int width) {
  final pixels = rgba.lengthInBytes ~/ 4;
  if (pixels == 0 || width <= 0) return false;
  final height = pixels ~/ width;
  final bandX = (width * 0.1).ceil();
  final bandY = (height * 0.1).ceil();
  var sum = 0.0;
  var n = 0;
  for (var y = 0; y < height; y++) {
    final inYBand = y < bandY || y >= height - bandY;
    for (var x = 0; x < width; x++) {
      if (!inYBand && x >= bandX && x < width - bandX) continue;
      final o = (y * width + x) * 4;
      final a = rgba.getUint8(o + 3) / 255;
      final luma = 0.2126 * rgba.getUint8(o) + 0.7152 * rgba.getUint8(o + 1) + 0.0722 * rgba.getUint8(o + 2);
      sum += a * luma / 255;
      n++;
    }
  }
  return n > 0 && sum / n <= kDarkTileLumaThreshold;
}

/// Decodes [provider] (normally already in the image cache) and tells whether it is dark tile art;
/// null when it cannot be read.
Future<bool?> isDarkTileImage(ImageProvider provider, ImageConfiguration configuration) async {
  final completer = Completer<ui.Image?>();
  final stream = provider.resolve(configuration);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image.clone());
      info.dispose();
    },
    onError: (_, __) {
      if (!completer.isCompleted) completer.complete(null);
    },
  );
  stream.addListener(listener);
  final image = await completer.future.timeout(const Duration(seconds: 2), onTimeout: () => null);
  stream.removeListener(listener);
  if (image == null) return null;
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return bytes == null ? null : isDarkTileArt(bytes, image.width);
  } finally {
    image.dispose();
  }
}
