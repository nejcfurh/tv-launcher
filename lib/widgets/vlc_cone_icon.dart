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

/// A traffic cone drawn with strokes only, like the outlined Material icons beside it in the top
/// bar: a body narrowing to a rounded tip, VLC's two stripes, and a flat base plate.
class VlcConeIcon extends StatelessWidget {
  final double size;
  final Color color;

  const VlcConeIcon({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: VlcConeOutlinePainter(color: color)),
  );
}

/// Drawn on Material's 24-unit icon grid and scaled to the canvas, with Material's 2-unit stroke.
class VlcConeOutlinePainter extends CustomPainter {
  final Color color;

  const VlcConeOutlinePainter({required this.color});

  static const double gridSize = 24;
  static const double strokeUnits = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / gridSize;
    canvas.save();
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeUnits
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // One path, stroked once: with a translucent colour, separate strokes would show brighter
    // spots where they cross.
    final cone = Path()
      // Body: two sides meeting in a rounded tip; the base plate closes it at the bottom.
      ..moveTo(6.5, 18)
      ..lineTo(10.4, 4.6)
      ..quadraticBezierTo(12, 1.8, 13.6, 4.6)
      ..lineTo(17.5, 18);
    // The stripes span the body at their height (the sides run from x 10.4 at y 4.6 to x 6.5 at y 18).
    for (final y in const [8.6, 13.4]) {
      final inset = 10.4 - (y - 4.6) * (10.4 - 6.5) / (18 - 4.6);
      cone
        ..moveTo(inset, y)
        ..lineTo(gridSize - inset, y);
    }
    cone.addRRect(RRect.fromLTRBR(3, 18, 21, 21.5, const Radius.circular(1)));
    canvas.drawPath(cone, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(VlcConeOutlinePainter oldDelegate) => oldDelegate.color != color;
}
