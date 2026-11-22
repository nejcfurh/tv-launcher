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
/// Focus shows a 32 dp circle of 20% white behind an 18 dp glyph (with the default padding) and
/// scales the control to 1.1. There is no outline: the fill alone marks focus.
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
    this.padding = const EdgeInsets.all(7),
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

/// Paints the translucent white fill behind a focused, hovered or pressed top bar control.
class AppBarFocusRingPainter extends CustomPainter {
  final bool isFocused;
  final bool isHovered;
  final bool isPressed;
  final double progress;

  const AppBarFocusRingPainter({
    required this.isFocused,
    required this.isHovered,
    required this.isPressed,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || progress <= 0.0) return;

    final double alpha;
    if (isPressed) {
      alpha = 0.28;
    } else if (isFocused) {
      alpha = 0.20;
    } else {
      alpha = 0.16;
    }

    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(min(size.width, size.height) / 2));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: (alpha * progress).clamp(0.0, 1.0)),
    );
  }

  @override
  bool shouldRepaint(covariant AppBarFocusRingPainter oldDelegate) =>
      oldDelegate.isFocused != isFocused ||
      oldDelegate.isHovered != isHovered ||
      oldDelegate.isPressed != isPressed ||
      oldDelegate.progress != progress;
}
