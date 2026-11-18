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
/// on a dark tray.
class DockTileInnerBorder extends StatelessWidget {
  final double tileRadius;

  const DockTileInnerBorder({super.key, required this.tileRadius});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tileRadius),
        border: Border.all(
          color: const Color(0x1FFFFFFF),
          width: 1 / MediaQuery.devicePixelRatioOf(context),
        ),
      ),
    ),
  );
}
