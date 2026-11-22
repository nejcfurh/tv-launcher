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
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flauncher/models/app.dart';
import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/widgets/app_card.dart';
import 'package:flauncher/widgets/category_clean_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Height of a band tile (the parallelogram), without its name.
const kBandTileHeight = 56.0;

/// Lean of the tiles' sides from vertical.
const kBandSlantDegrees = 10.0;

/// Between neighbouring tiles.
const kBandGap = 2.0;

/// The focused tile grows by this about its centre.
const kBandFocusedScale = 1.15;

const kBandFocusDuration = Duration(milliseconds: 160);

/// Unselected tiles are drawn at this opacity, so the focused one leads.
const kBandMutedOpacity = 0.65;

/// Unselected tiles whose art is mostly bright (white Netflix, YouTube) are also darkened by this
/// much, so large bright blocks do not dominate the bottom of the screen.
const kBandBrightTileDim = 0.25;

/// Mean Rec. 709 luma (0–1) of a tile's art at or above which it counts as bright.
const kBandBrightLuma = 0.7;

/// Space between a tile and its name.
const kBandLabelGap = 6.0;

/// Room for the name line under the tiles.
const kBandLabelHeight = 18.0;

/// Full height of the band: tiles, names, and the focused tile's growth.
const kBandHeight = kBandTileHeight + kBandLabelGap + 4 + kBandLabelHeight;

/// The half tiles where the screen edges cut the band.
const kBandSliverColor = Color(0xFF232325);

/// Around the focused tile, so its edges stand clear of the neighbours.
const kBandCutoutColor = Color(0xFF0B0B0C);

/// Fill of a tile with no art (yet), and of the "All apps" tile.
const kBandPlainTileColor = Color(0xFF2A2A2C);

/// Where the tiles of a band [count] tiles long sit across [width]: one parallelogram per slot,
/// plus a half slot at each screen edge.
class BandGeometry {
  final double width;
  final int count;

  const BandGeometry(this.width, this.count);

  double get pitch => width / (count + 1);

  double get slant => kBandTileHeight * math.tan(kBandSlantDegrees * math.pi / 180);

  /// Width of a tile's box: the parallelogram leans [slant] to the right at the top.
  double get boxWidth => pitch - kBandGap + slant;

  /// Left of slot [slot] (0 and [count] + 1 are the edge halves; tile i is slot i + 1).
  double slotLeft(int slot) => -pitch / 2 + slot * pitch + kBandGap / 2;
}

/// A parallelogram filling [size]: its top edge starts [slant] in from the left, its bottom edge
/// ends [slant] short of the right.
Path bandTilePath(Size size, double slant) => Path()
  ..moveTo(slant, 0)
  ..lineTo(size.width, 0)
  ..lineTo(size.width - slant, size.height)
  ..lineTo(0, size.height)
  ..close();

/// The colour a tile's art is extended with (mean of its opaque edge pixels) and how bright the
/// art is (mean luma of its opaque pixels, 0–1). Null when nothing in it is opaque.
({Color edge, double luma})? bandArtColours(ByteData rgba, int width) {
  final pixels = rgba.lengthInBytes ~/ 4;
  if (pixels == 0 || width <= 0) return null;
  final height = pixels ~/ width;
  final bandX = math.max(1, (width * 0.1).ceil());
  final bandY = math.max(1, (height * 0.1).ceil());
  var r = 0.0, g = 0.0, b = 0.0, edgeN = 0;
  var lumaSum = 0.0, lumaN = 0;
  for (var y = 0; y < height; y++) {
    final inYBand = y < bandY || y >= height - bandY;
    for (var x = 0; x < width; x++) {
      final o = (y * width + x) * 4;
      if (rgba.getUint8(o + 3) < 128) continue;
      final pr = rgba.getUint8(o), pg = rgba.getUint8(o + 1), pb = rgba.getUint8(o + 2);
      lumaSum += (0.2126 * pr + 0.7152 * pg + 0.0722 * pb) / 255;
      lumaN++;
      if (inYBand || x < bandX || x >= width - bandX) {
        r += pr;
        g += pg;
        b += pb;
        edgeN++;
      }
    }
  }
  if (lumaN == 0) return null;
  final edge = edgeN == 0
      ? kBandPlainTileColor
      : Color.fromARGB(255, (r / edgeN).round(), (g / edgeN).round(), (b / edgeN).round());
  return (edge: edge, luma: lumaSum / lumaN);
}

/// Paints one band tile: the art's logo in the middle, its edge pixels stretched out to fill the
/// parallelogram, muted unless [focused]. A focused tile gets a shadow and a dark cut-out.
class BandTilePainter extends CustomPainter {
  final ui.Image? image;
  final Color edgeColour;
  final bool bright;
  final bool focused;
  final double slant;

  const BandTilePainter({
    required this.image,
    required this.edgeColour,
    required this.bright,
    required this.focused,
    required this.slant,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = bandTilePath(size, slant);
    final bounds = Offset.zero & size;
    if (focused) {
      canvas.drawShadow(path, Colors.black, 10, false);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeJoin = StrokeJoin.miter
          ..color = kBandCutoutColor,
      );
    } else {
      canvas.saveLayer(bounds, Paint()..color = Color.fromRGBO(0, 0, 0, kBandMutedOpacity));
    }
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(bounds, Paint()..color = edgeColour);
    final art = image;
    if (art != null) {
      final logo = bandLogoRect(size, slant, Size(art.width.toDouble(), art.height.toDouble()));
      final matrix = Matrix4.identity()
        ..translateByDouble(logo.left, logo.top, 0, 1)
        ..scaleByDouble(logo.width / art.width, logo.height / art.height, 1, 1);
      canvas.drawRect(
        bounds,
        Paint()
          ..shader = ImageShader(art, TileMode.clamp, TileMode.clamp, matrix.storage)
          ..filterQuality = FilterQuality.medium,
      );
    }
    if (!focused && bright) {
      canvas.drawRect(bounds, Paint()..color = Color.fromRGBO(0, 0, 0, kBandBrightTileDim));
    }
    canvas.restore();
    if (!focused) canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BandTilePainter old) =>
      old.image != image ||
      old.edgeColour != edgeColour ||
      old.bright != bright ||
      old.focused != focused ||
      old.slant != slant;
}

/// Where the logo goes in a tile of [size]: centred, at most 60% of the tile's height, and short of
/// the slanted sides.
Rect bandLogoRect(Size size, double slant, Size art) {
  var height = size.height * 0.6;
  var width = height * art.width / art.height;
  final maxWidth = size.width - 2 * slant - 12;
  if (width > maxWidth) {
    width = maxWidth;
    height = width * art.height / art.width;
  }
  return Rect.fromCenter(center: size.center(Offset.zero), width: width, height: height);
}

/// A band tile's face: resolves [image], samples its colours once, and paints it with
/// [BandTilePainter]. [child] sits on top (the focusable part and any move arrows).
class BandTileFace extends StatefulWidget {
  final ImageProvider? image;
  final bool focused;
  final double slant;
  final Widget? child;

  /// For tiles without art (the "All apps" tile).
  final Color? plainColour;

  const BandTileFace({
    super.key,
    required this.image,
    required this.focused,
    required this.slant,
    this.child,
    this.plainColour,
  });

  @override
  State<BandTileFace> createState() => _BandTileFaceState();
}

class _BandTileFaceState extends State<BandTileFace> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _image;
  Color _edge = kBandPlainTileColor;
  bool _bright = false;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(BandTileFace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) _resolve();
  }

  void _resolve() {
    final provider = widget.image;
    if (provider == null) {
      _stopListening();
      return;
    }
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stopListening();
    _stream = stream;
    _listener = ImageStreamListener((info, _) => _onImage(info));
    stream.addListener(_listener!);
  }

  Future<void> _onImage(ImageInfo info) async {
    final generation = ++_generation;
    final image = info.image.clone();
    info.dispose();
    ({Color edge, double luma})? colours;
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      colours = bytes == null ? null : bandArtColours(bytes, image.width);
    } catch (_) {
      colours = null;
    }
    if (!mounted || generation != _generation) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _edge = colours?.edge ?? kBandPlainTileColor;
      _bright = (colours?.luma ?? 0) >= kBandBrightLuma;
    });
  }

  void _stopListening() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _stopListening();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: BandTilePainter(
          image: widget.plainColour == null ? _image : null,
          edgeColour: widget.plainColour ?? _edge,
          bright: widget.plainColour == null && _bright,
          focused: widget.focused,
          slant: widget.slant,
        ),
        child: widget.child,
      );
}

/// The dock as a band of parallelograms across the whole screen: one per app, a half at each
/// screen edge, the focused one larger and the others muted, names underneath. Right from the
/// last tile goes to the first, Left from the first to the last.
class DockBand extends StatefulWidget {
  final Category category;
  final List<App> applications;
  final bool isFirstSection;
  final VoidCallback? onAppFocused;
  final void Function(App app)? onDockAppFocused;

  /// Shows an "All apps" tile at the end when set.
  final VoidCallback? onAllAppsPressed;
  final FocusNode? allAppsFocusNode;

  const DockBand({
    super.key,
    required this.category,
    required this.applications,
    this.isFirstSection = false,
    this.onAppFocused,
    this.onDockAppFocused,
    this.onAllAppsPressed,
    this.allAppsFocusNode,
  });

  @override
  State<DockBand> createState() => _DockBandState();
}

class _DockBandState extends State<DockBand> {
  /// One per tile; an ancestor of the tile's own focus node, used to wrap focus round the ends.
  final List<FocusNode> _slots = [];

  /// The tile that last took focus; painted last, so it grows over its neighbours.
  int? _focusedIndex;

  void _tileFocused(int index) {
    if (_focusedIndex != index) setState(() => _focusedIndex = index);
  }

  int get _count => widget.applications.length + (widget.onAllAppsPressed != null ? 1 : 0);

  void _syncSlots() {
    while (_slots.length < _count) {
      _slots.add(FocusNode(debugLabel: 'band_slot_${_slots.length}', skipTraversal: true, canRequestFocus: false));
    }
    while (_slots.length > _count) {
      _slots.removeLast().dispose();
    }
  }

  @override
  void dispose() {
    for (final node in _slots) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _wrap(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final int target;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight && index == _count - 1) {
      target = 0;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft && index == 0) {
      target = _count - 1;
    } else {
      return KeyEventResult.ignored;
    }
    if (target == index) return KeyEventResult.handled;
    final node = _slots[target].descendants.where((n) => n.canRequestFocus && !n.skipTraversal).firstOrNull;
    node?.requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    _syncSlots();
    return SizedBox(
      key: const Key('dock_band'),
      height: kBandHeight,
      child: LayoutBuilder(builder: (context, constraints) {
        final geometry = BandGeometry(constraints.maxWidth, _count);
        Widget slot(int index, Widget child) => Positioned(
              key: ValueKey('dock_band_slot_$index'),
              left: geometry.slotLeft(index + 1),
              top: 0,
              width: geometry.boxWidth,
              height: kBandHeight,
              child: Focus(
                focusNode: _slots[index],
                onKeyEvent: (_, event) => _wrap(index, event),
                child: child,
              ),
            );
        Widget sliver(int slotIndex) => Positioned(
              key: Key('dock_band_edge_$slotIndex'),
              left: geometry.slotLeft(slotIndex),
              top: 0,
              width: geometry.boxWidth,
              height: kBandTileHeight,
              child: CustomPaint(painter: _SliverPainter(geometry.slant)),
            );
        final tiles = <Widget>[
          for (final (index, application) in widget.applications.indexed)
            slot(
              index,
              AppCard(
                key: ValueKey(application.packageName),
                category: widget.category,
                application: application,
                autofocus: index == 0,
                handleUpNavigationToSettings: widget.isFirstSection,
                scrollAlignment: 1.0,
                enforceAspectRatio: false,
                dockTile: true,
                bandSlant: geometry.slant,
                onFocused: () {
                  _tileFocused(index);
                  widget.onAppFocused?.call();
                  widget.onDockAppFocused?.call(application);
                },
                onMove: (direction) => _onMove(context, direction, index),
                onMoveEnd: () => _onMoveEnd(context),
              ),
            ),
          if (widget.onAllAppsPressed != null)
            slot(
              widget.applications.length,
              DockAllAppsTile(
                focusNode: widget.allAppsFocusNode,
                onPressed: widget.onAllAppsPressed!,
                onFocused: () {
                  _tileFocused(widget.applications.length);
                  widget.onAppFocused?.call();
                },
                handleUpNavigationToSettings: widget.isFirstSection,
                bandSlant: geometry.slant,
              ),
            ),
        ];
        final focused = _focusedIndex;
        if (focused != null && focused < tiles.length) tiles.add(tiles.removeAt(focused));
        return Stack(clipBehavior: Clip.hardEdge, children: [sliver(0), sliver(_count + 1), ...tiles]);
      }),
    );
  }

  void _onMove(BuildContext context, AxisDirection direction, int index) {
    final int newIndex;
    if (direction == AxisDirection.right && index < widget.applications.length - 1) {
      newIndex = index + 1;
    } else if (direction == AxisDirection.left && index > 0) {
      newIndex = index - 1;
    } else {
      return;
    }
    final appsService = context.read<AppsService>();
    final movingApp = widget.applications[index];
    final realOldIndex = widget.category.applications.indexOf(movingApp);
    final realNewIndex = widget.category.applications.indexOf(widget.applications[newIndex]);
    if (realOldIndex >= 0 && realNewIndex >= 0) {
      appsService.reorderApplication(widget.category, realOldIndex, realNewIndex);
      appsService.setPendingReorderFocus(movingApp.packageName, widget.category.id);
    }
  }

  void _onMoveEnd(BuildContext context) {
    context.read<AppsService>().saveApplicationOrderInCategory(widget.category);
  }
}

class _SliverPainter extends CustomPainter {
  final double slant;

  const _SliverPainter(this.slant);

  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawPath(bandTilePath(size, slant), Paint()..color = kBandSliverColor);

  @override
  bool shouldRepaint(covariant _SliverPainter old) => old.slant != slant;
}
