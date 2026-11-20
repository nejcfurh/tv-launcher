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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How long Home waits without a key press before it dims.
const kHomeIdleTimeout = Duration(minutes: 3);

/// Fade into the dimmed state, and back out of it.
const kHomeIdleDimDuration = Duration(milliseconds: 1500);
const kHomeIdleWakeDuration = Duration(milliseconds: 300);

/// Opacity of the black layer over the backdrop while dimmed.
const kHomeIdleBackdropDim = 0.5;

/// Dims Home after [timeout] without a key press: [builder] gets `dimmed` and fades the UI out and
/// darkens the backdrop. The first key press only wakes it: focus waits on a hidden node while
/// dimmed, so the press (and its key up and repeats) never reaches a tile, and focus returns to
/// where it was once the key is released. Nothing animates while dimmed.
class HomeIdleDimmer extends StatefulWidget {
  final Widget Function(BuildContext context, bool dimmed) builder;
  final Duration timeout;

  /// Asked when the timeout runs out; Home stays lit while it returns false (a panel or dialog
  /// is open over it).
  final bool Function()? canDim;

  const HomeIdleDimmer({super.key, required this.builder, this.timeout = kHomeIdleTimeout, this.canDim});

  @override
  State<HomeIdleDimmer> createState() => HomeIdleDimmerState();
}

class HomeIdleDimmerState extends State<HomeIdleDimmer> with WidgetsBindingObserver {
  final FocusNode _wakeNode = FocusNode(debugLabel: 'home_idle_wake', skipTraversal: true);
  Timer? _timer;
  bool _dimmed = false;
  FocusNode? _restoreFocus;

  /// The key that woke Home; its repeats and key up are swallowed as well.
  PhysicalKeyboardKey? _wakeKey;

  bool get dimmed => _dimmed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onAnyKey);
    _restartTimer();
  }

  @override
  void didUpdateWidget(HomeIdleDimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeout != widget.timeout && !_dimmed) _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onAnyKey);
    WidgetsBinding.instance.removeObserver(this);
    _wakeNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restartTimer();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _timer?.cancel();
      _wakeKey = null;
      wake();
    }
  }

  /// Lights Home again and restarts the timeout (also used for the remote's Home button).
  void wake() {
    if (_dimmed) {
      setState(() => _dimmed = false);
      if (_wakeKey == null) _restorePreviousFocus();
    }
    _restartTimer();
  }

  /// Observes every key press on its way to the focus system; only restarts the timeout.
  bool _onAnyKey(KeyEvent event) {
    if (!_dimmed && _wakeKey == null) _restartTimer();
    return false;
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer(widget.timeout, _dim);
  }

  void _dim() {
    if (!mounted || _dimmed) return;
    if (!(widget.canDim?.call() ?? true)) {
      _restartTimer();
      return;
    }
    final current = FocusManager.instance.primaryFocus;
    _restoreFocus = current == _wakeNode ? null : current;
    setState(() => _dimmed = true);
    _wakeNode.requestFocus();
  }

  void _restorePreviousFocus() {
    final target = _restoreFocus;
    _restoreFocus = null;
    if (target != null && target.context != null && target.canRequestFocus) {
      target.requestFocus();
    } else if (_wakeNode.hasFocus) {
      _wakeNode.unfocus();
    }
  }

  KeyEventResult _onWakeNodeKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && _dimmed && _wakeKey == null) {
      _wakeKey = event.physicalKey;
      wake();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && _wakeKey != null && event.physicalKey != _wakeKey) {
      // The waking key's release never came (or two keys at once): give focus back now.
      _wakeKey = null;
      _restorePreviousFocus();
      _restartTimer();
      return KeyEventResult.handled;
    }
    if (event.physicalKey == _wakeKey) {
      if (event is KeyUpEvent) {
        _wakeKey = null;
        _restorePreviousFocus();
        _restartTimer();
      }
      return KeyEventResult.handled;
    }
    // Another key while the waking one is still held: swallowed too, focus returns on key up.
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.passthrough,
        children: [
          widget.builder(context, _dimmed),
          // A leaf, so it only ever sees keys while it holds focus itself.
          Focus(focusNode: _wakeNode, onKeyEvent: _onWakeNodeKey, child: const SizedBox.shrink()),
        ],
      );
}
