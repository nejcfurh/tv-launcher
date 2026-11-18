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

import 'package:flauncher/widgets/vlc_cone_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the calls the painter makes.
class _RecordingCanvas implements Canvas {
  final calls = <Invocation>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    return null;
  }
}

void main() {
  const color = Color(0xCCFFFFFF);

  test('the cone is drawn with strokes only, at the outlined icons\' 2/24 weight', () {
    final canvas = _RecordingCanvas();
    const VlcConeOutlinePainter(color: color).paint(canvas, const Size.square(18));

    final scale = canvas.calls.singleWhere((call) => call.memberName == #scale).positionalArguments.first as double;
    final paints = [for (final call in canvas.calls) ...call.positionalArguments.whereType<Paint>()];
    expect(paints, isNotEmpty);
    for (final paint in paints) {
      expect(paint.style, PaintingStyle.stroke, reason: 'nothing is filled');
      expect(paint.color.toARGB32(), color.toARGB32());
      expect(paint.strokeWidth * scale, 18 * 2 / 24);
    }
    // One stroke for the whole cone, so a translucent colour never doubles where lines cross.
    expect(canvas.calls.where((call) => call.memberName == #drawPath), hasLength(1));
  });

  testWidgets('VlcConeIcon takes the given size', (tester) async {
    await tester.pumpWidget(const Center(child: VlcConeIcon(size: 18, color: color)));

    expect(tester.getSize(find.byType(VlcConeIcon)), const Size(18, 18));
    expect(find.descendant(of: find.byType(VlcConeIcon), matching: find.byType(CustomPaint)), findsOneWidget);
  });
}
