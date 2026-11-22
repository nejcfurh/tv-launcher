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

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/launcher_state.dart';

/// A focusable and hoverable control for the top bar (Settings, app shortcuts).
///
/// A glass circle sits behind the glyph at all times (44 dp around a 20 dp glyph with the default
/// padding, as tall as the time beside it): 12% white with a hairline 18% white edge. Focus brightens it to 30% white with a 70%
/// white edge and scales the control to 1.1.
/// Space between a 20 dp top bar glyph and the edge of its glass circle.
const kAppBarGlassPadding = 12.0;

class AppBarFocusRing extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  const AppBarFocusRing({
    super.key,
    required this.child,
    required this.onPressed,
    this.focusNode,
    this.padding = const EdgeInsets.all(kAppBarGlassPadding),
    this.semanticLabel,
  });

  @override
  State<AppBarFocusRing> createState() => _AppBarFocusRingState();
}

class _AppBarFocusRingState extends State<AppBarFocusRing> {
  bool _isFocused = false;
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isFocused || _isHovered;
    final targetScale = _isPressed ? 0.92 : (isHighlighted ? 1.1 : 1.0);
    final targetProgress = isHighlighted || _isPressed ? 1.0 : 0.0;

    return Semantics(
      label: widget.semanticLabel,
      button: true,
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed()),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onPressed()),
        },
        child: Focus(
          focusNode: widget.focusNode,
          onFocusChange: (hasFocus) {
            if (hasFocus) {
              context.read<LauncherState>().setAppGridFocused(false);
            }
            if (mounted) {
              setState(() => _isFocused = hasFocus);
            }
          },
          child: AnimatedScale(
            scale: targetScale,
            duration: const Duration(milliseconds: 150),
            curve: Curves.fastOutSlowIn,
            child: InkWell(
              onTap: widget.onPressed,
              onHover: (hovering) {
                if (mounted && _isHovered != hovering) {
                  setState(() => _isHovered = hovering);
                }
              },
              onHighlightChanged: (pressed) {
                if (mounted && _isPressed != pressed) {
                  setState(() => _isPressed = pressed);
                }
              },
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              customBorder: const CircleBorder(),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: targetProgress),
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                builder: (context, progress, child) {
                  return CustomPaint(
                    painter: AppBarFocusRingPainter(
                      isFocused: _isFocused,
                      isHovered: _isHovered,
                      isPressed: _isPressed,
                      progress: progress,
                      hairline: 1 / MediaQuery.devicePixelRatioOf(context),
                    ),
                    child: child,
                  );
                },
                child: Padding(
                  padding: widget.padding,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the glass circle (or pill) behind a top bar control: at rest a 12% white fill with an 18%
/// white hairline edge; focused, hovered or pressed, it blends ([progress]) to a brighter fill and a
/// 70% white edge.
class AppBarFocusRingPainter extends CustomPainter {
  final bool isFocused;
  final bool isHovered;
  final bool isPressed;
  final double progress;

  /// Width of the resting edge: one physical pixel.
  final double hairline;

  static const restFill = 0.12;
  static const restEdge = 0.18;
  static const activeEdge = 0.70;

  const AppBarFocusRingPainter({
    required this.isFocused,
    required this.isHovered,
    required this.isPressed,
    required this.progress,
    this.hairline = 1.0,
  });

  double get activeFill => isPressed ? 0.38 : (isFocused ? 0.30 : 0.24);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = progress.clamp(0.0, 1.0);
    final fill = restFill + (activeFill - restFill) * t;
    final edge = restEdge + (activeEdge - restEdge) * t;
    final edgeWidth = hairline + (1.5 - hairline) * t;

    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(min(size.width, size.height) / 2));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: fill),
    );
    canvas.drawRRect(
      rrect.deflate(edgeWidth / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = edgeWidth
        ..color = Colors.white.withValues(alpha: edge),
    );
  }

  @override
  bool shouldRepaint(covariant AppBarFocusRingPainter oldDelegate) =>
      oldDelegate.isFocused != isFocused ||
      oldDelegate.isHovered != isHovered ||
      oldDelegate.isPressed != isPressed ||
      oldDelegate.progress != progress ||
      oldDelegate.hairline != hairline;
}
