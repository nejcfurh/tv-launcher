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

/// The colour a tile's art is extended with (median of its opaque edge pixels, so a logo touching
/// the edge does not tint it) and how bright the
/// art is (mean luma of its opaque pixels, 0–1). Null when nothing in it is opaque.
({Color edge, double luma})? bandArtColours(ByteData rgba, int width) {
  final pixels = rgba.lengthInBytes ~/ 4;
  if (pixels == 0 || width <= 0) return null;
  final height = pixels ~/ width;
  final bandX = math.max(1, (width * 0.1).ceil());
  final bandY = math.max(1, (height * 0.1).ceil());
  final hr = List.filled(256, 0), hg = List.filled(256, 0), hb = List.filled(256, 0);
  var edgeN = 0;
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
        hr[pr]++;
        hg[pg]++;
        hb[pb]++;
        edgeN++;
      }
    }
  }
  if (lumaN == 0) return null;
  final edge = edgeN == 0
      ? kBandPlainTileColor
      : Color.fromARGB(255, _histogramMedian(hr, edgeN), _histogramMedian(hg, edgeN), _histogramMedian(hb, edgeN));
  return (edge: edge, luma: lumaSum / lumaN);
}

int _histogramMedian(List<int> histogram, int count) {
  var seen = 0;
  for (var value = 0; value < histogram.length; value++) {
    seen += histogram[value];
    if (seen * 2 >= count) return value;
  }
  return histogram.length - 1;
}

/// How far (RGB distance, 0–441) a pixel may sit from the art's smooth background and still
/// count as background; beyond [kBandFlattenLogo] it is all logo, with a soft blend between.
const kBandFlattenBackground = 28.0;
const kBandFlattenLogo = 72.0;

/// [rgba] with its background (a smooth gradient, fitted to the whole picture while ignoring the
/// logo) replaced by the single colour [fill], keeping the logo on top. Null when the art has
/// transparent edges (an icon) or when less than half of it fits a smooth background (a photo), so
/// those are left as they are.
Uint8List? bandFlattenBackground(ByteData rgba, int width, Color fill) {
  final pixels = rgba.lengthInBytes ~/ 4;
  if (pixels == 0 || width < 2) return null;
  final height = pixels ~/ width;
  if (height < 2) return null;
  final src = rgba.buffer.asUint8List(rgba.offsetInBytes, pixels * 4);
  final bandX = math.max(1, (width * 0.05).ceil());
  final bandY = math.max(1, (height * 0.05).ceil());
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final onEdge = y < bandY || y >= height - bandY || x < bandX || x >= width - bandX;
      if (onEdge && src[(y * width + x) * 4 + 3] < 128) return null;
    }
  }

  // Quadratic surface per channel over (u, v) in 0–1, refitted to the pixels closest to it: first
  // the better half (the logo is the minority, so it drops out), then all within reach.
  List<double> basis(double u, double v) => [1, u, v, u * u, u * v, v * v];
  final step = math.max(1, math.sqrt(pixels / 4000).floor());
  final samples = <(List<double>, int)>[
    for (var y = 0; y < height; y += step)
      for (var x = 0; x < width; x += step) (basis(x / (width - 1), y / (height - 1)), (y * width + x) * 4),
  ];
  var inliers = List.filled(samples.length, true);
  late List<List<double>> coefficients;
  double distance(List<double> b, int o) {
    var d2 = 0.0;
    for (var c = 0; c < 3; c++) {
      var model = 0.0;
      for (var k = 0; k < 6; k++) {
        model += coefficients[c][k] * b[k];
      }
      final delta = src[o + c] - model;
      d2 += delta * delta;
    }
    return math.sqrt(d2);
  }

  for (var round = 0; round < 6; round++) {
    final fitted = _fitQuadratic(samples, inliers, src);
    if (fitted == null) return null;
    coefficients = fitted;
    if (round == 5) break;
    final distances = [for (final (b, o) in samples) distance(b, o)];
    final median = ([...distances]..sort())[distances.length ~/ 2];
    final cutoff = round < 3 ? median : math.max(kBandFlattenBackground, 2.5 * median);
    inliers = [for (final d in distances) d <= cutoff];
  }

  final fr = (fill.r * 255).round(), fg = (fill.g * 255).round(), fb = (fill.b * 255).round();
  final out = Uint8List(pixels * 4);
  var background = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final o = (y * width + x) * 4;
      final t = ((distance(basis(x / (width - 1), y / (height - 1)), o) - kBandFlattenBackground) /
              (kBandFlattenLogo - kBandFlattenBackground))
          .clamp(0.0, 1.0);
      final logo = t * t * (3 - 2 * t);
      if (logo < 0.5) background++;
      out[o] = (fr + (src[o] - fr) * logo).round();
      out[o + 1] = (fg + (src[o + 1] - fg) * logo).round();
      out[o + 2] = (fb + (src[o + 2] - fb) * logo).round();
      out[o + 3] = 255;
    }
  }
  return background * 2 >= pixels ? out : null;
}

/// Least squares fit of the six quadratic terms to the RGB of the [inliers] among [samples]:
/// one coefficient list per channel, or null when too few samples are left to fit.
List<List<double>>? _fitQuadratic(List<(List<double>, int)> samples, List<bool> inliers, Uint8List src) {
  final a = List.generate(6, (_) => List.filled(6, 0.0));
  final rhs = List.generate(3, (_) => List.filled(6, 0.0));
  var used = 0;
  for (var i = 0; i < samples.length; i++) {
    if (!inliers[i]) continue;
    final (b, o) = samples[i];
    used++;
    for (var r = 0; r < 6; r++) {
      for (var c = 0; c < 6; c++) {
        a[r][c] += b[r] * b[c];
      }
      for (var ch = 0; ch < 3; ch++) {
        rhs[ch][r] += b[r] * src[o + ch];
      }
    }
  }
  if (used < 12) return null;
  // Gaussian elimination with partial pivoting, all three channels at once.
  for (var col = 0; col < 6; col++) {
    var pivot = col;
    for (var r = col + 1; r < 6; r++) {
      if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
    }
    if (a[pivot][col].abs() < 1e-9) return null;
    if (pivot != col) {
      final row = a[col];
      a[col] = a[pivot];
      a[pivot] = row;
      for (final v in rhs) {
        final t = v[col];
        v[col] = v[pivot];
        v[pivot] = t;
      }
    }
    for (var r = col + 1; r < 6; r++) {
      final f = a[r][col] / a[col][col];
      for (var c = col; c < 6; c++) {
        a[r][c] -= f * a[col][c];
      }
      for (final v in rhs) {
        v[r] -= f * v[col];
      }
    }
  }
  return [
    for (final v in rhs)
      () {
        final x = List.filled(6, 0.0);
        for (var r = 5; r >= 0; r--) {
          var sum = v[r];
          for (var c = r + 1; c < 6; c++) {
            sum -= a[r][c] * x[c];
          }
          x[r] = sum / a[r][r];
        }
        return x;
      }(),
  ];
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
    var art = image;
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      colours = bytes == null ? null : bandArtColours(bytes, image.width);
      final flat = bytes == null || colours == null ? null : bandFlattenBackground(bytes, image.width, colours.edge);
      if (flat != null) {
        final completer = Completer<ui.Image>();
        ui.decodeImageFromPixels(flat, image.width, image.height, ui.PixelFormat.rgba8888, completer.complete);
        art = await completer.future;
        image.dispose();
      }
    } catch (_) {
      colours = null;
    }
    if (!mounted || generation != _generation) {
      art.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = art;
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
              child: CustomPaint(
                painter: BandEdgePainter(
                  slant: geometry.slant,
                  clearAt: slotIndex == 0
                      ? -geometry.slotLeft(slotIndex)
                      : geometry.width - geometry.slotLeft(slotIndex),
                  solidAt: slotIndex == 0 ? geometry.boxWidth : 0,
                ),
              ),
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
        return ClipRect(
          clipper: const BandSideClipper(),
          child: Stack(clipBehavior: Clip.none, children: [sliver(0), sliver(_count + 1), ...tiles]),
        );
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

/// Cuts the band at the screen's sides only, so the focused tile can grow, and cast its shadow,
/// above the band's top edge.
class BandSideClipper extends CustomClipper<Rect> {
  const BandSideClipper();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, -kBandTileHeight, size.width, size.height + kBandTileHeight);

  @override
  bool shouldReclip(covariant BandSideClipper oldClipper) => false;
}

/// A half tile at a screen edge: clear where the screen cuts it ([clearAt], in its own
/// coordinates), fading in to [kBandSliverColor] at [solidAt].
class BandEdgePainter extends CustomPainter {
  final double slant;
  final double clearAt;
  final double solidAt;

  const BandEdgePainter({required this.slant, required this.clearAt, required this.solidAt});

  @override
  void paint(Canvas canvas, Size size) {
    final shader = ui.Gradient.linear(
      Offset(clearAt, 0),
      Offset(solidAt, 0),
      [kBandSliverColor.withAlpha(0), kBandSliverColor],
    );
    canvas.drawPath(bandTilePath(size, slant), Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant BandEdgePainter old) =>
      old.slant != slant || old.clearAt != clearAt || old.solidAt != solidAt;
}
