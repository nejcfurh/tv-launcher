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
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'animated_character.dart';

class DateTimeWidget extends StatefulWidget {
  final Duration?   updateInterval;
  final String      _dateTimeFormatString;
  final TextStyle?  textStyle;
  final bool        animate;

  const DateTimeWidget(String dateTimeFormatString, {
    super.key,
    this.updateInterval,
    this.textStyle,
    this.animate = false,
  }) :
      _dateTimeFormatString = dateTimeFormatString;

  /// Clock source; tests replace it to move time along with fake timers.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  @override
  State<DateTimeWidget> createState() => _DateTimeWidgetState();
}

class _DateTimeWidgetState extends State<DateTimeWidget> with WidgetsBindingObserver {
  /// Fires this long after the minute turns, so the format already reads the new minute.
  static const Duration _tickSlack = Duration(milliseconds: 50);

  late DateFormat _dateFormat;
  late DateTime   _now;
  Timer?          _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dateFormat = DateFormat(widget._dateTimeFormatString, Platform.localeName);
    _now = DateTimeWidget.clock();
    _scheduleTick();
  }

  /// Returns 1-second interval if format contains seconds, otherwise 1-minute.
  Duration _defaultInterval() {
    final fmt = widget._dateTimeFormatString;
    return (fmt.contains('s') || fmt.contains('S'))
        ? const Duration(seconds: 1)
        : const Duration(minutes: 1);
  }

  /// Minute ticks land on the minute (re-aligned after every tick, so they never drift);
  /// a periodic timer would land wherever the widget happened to start, up to 59 s late.
  void _scheduleTick() {
    _timer?.cancel();
    final interval = widget.updateInterval ?? _defaultInterval();
    if (interval < const Duration(minutes: 1)) {
      _timer = Timer.periodic(interval, (_) => _refreshTime());
      return;
    }
    final current = DateTimeWidget.clock();
    final nextMinute = DateTime(current.year, current.month, current.day, current.hour, current.minute + 1);
    _timer = Timer(nextMinute.difference(current) + _tickSlack, () {
      _refreshTime();
      _scheduleTick();
    });
  }

  @override
  void didUpdateWidget(DateTimeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._dateTimeFormatString != widget._dateTimeFormatString) {
      _dateFormat = DateFormat(widget._dateTimeFormatString, Platform.localeName);
      setState(() {
        _now = DateTimeWidget.clock();
      });
    }
    if (oldWidget.updateInterval != widget.updateInterval ||
        oldWidget._dateTimeFormatString != widget._dateTimeFormatString) {
      _scheduleTick();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshTime();
      _scheduleTick();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formattedText = _dateFormat.format(_now);

    if (widget.animate) {
      return AnimatedTimeDisplay(
        displayText: formattedText,
        textStyle: widget.textStyle,
      );
    }

    return Text(formattedText, style: widget.textStyle);
  }

  /// Rebuilds only when the shown text changes.
  void _refreshTime() {
    final next = DateTimeWidget.clock();
    if (_dateFormat.format(next) == _dateFormat.format(_now)) {
      _now = next;
      return;
    }
    setState(() {
      _now = next;
    });
  }
}
