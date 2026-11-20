import 'package:flauncher/widgets/date_time_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime fakeNow;

  setUp(() {
    // 37 s into the minute: a periodic timer started here would fire at :37 each minute.
    fakeNow = DateTime(2026, 11, 20, 23, 58, 37);
    DateTimeWidget.clock = () => fakeNow;
  });

  tearDown(() => DateTimeWidget.clock = DateTime.now);

  // Moves the wall clock together with the fake timers, in 50 ms steps.
  Future<void> advance(WidgetTester tester, Duration d) async {
    const step = Duration(milliseconds: 50);
    var left = d;
    while (left > Duration.zero) {
      final s = left < step ? left : step;
      fakeNow = fakeNow.add(s);
      await tester.pump(s);
      left -= s;
    }
  }

  Widget clock(String format) => MaterialApp(
        home: Row(children: [
          DateTimeWidget(format, key: const Key('w'), updateInterval: const Duration(minutes: 1)),
        ]),
      );

  testWidgets('a minute clock changes on the minute, not a minute after it started', (tester) async {
    await tester.pumpWidget(clock('HH:mm'));
    expect(find.text('23:58'), findsOneWidget);

    await advance(tester, const Duration(seconds: 22));
    expect(find.text('23:58'), findsOneWidget, reason: '23:58:59, still the same minute');

    await advance(tester, const Duration(seconds: 1, milliseconds: 100));
    expect(find.text('23:59'), findsOneWidget, reason: 'just after 23:59:00');

    await advance(tester, const Duration(minutes: 1));
    expect(find.text('00:00'), findsOneWidget);
  });

  testWidgets('date and time widgets turn over in the same tick at midnight', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Row(children: const [
        DateTimeWidget('EEE d MMM', key: Key('date'), updateInterval: Duration(minutes: 1)),
        DateTimeWidget('HH:mm', key: Key('time'), updateInterval: Duration(minutes: 1)),
      ]),
    ));
    await advance(tester, const Duration(minutes: 1, seconds: 23, milliseconds: 100));
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('Sat 21 Nov'), findsOneWidget);
  });

  testWidgets('ticks stay on the minute after many minutes', (tester) async {
    await tester.pumpWidget(clock('HH:mm'));
    await advance(tester, const Duration(seconds: 23, milliseconds: 100)); // 23:59:00.1
    String hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    for (var i = 0; i < 5; i++) {
      await advance(tester, const Duration(seconds: 59, milliseconds: 700)); // xx:59.8
      final before = fakeNow;
      expect(find.text(hhmm(before)), findsOneWidget, reason: 'at ${before.toIso8601String()}');
      await advance(tester, const Duration(milliseconds: 300)); // next minute, 0.1 s in
      expect(find.text(hhmm(fakeNow)), findsOneWidget, reason: 'at ${fakeNow.toIso8601String()}');
    }
  });

  testWidgets('returning to the app shows the current time at once', (tester) async {
    await tester.pumpWidget(clock('HH:mm'));
    // Time jumps (e.g. NTP sync while the launcher was hidden) without a timer firing.
    fakeNow = DateTime(2026, 11, 21, 7, 15, 10);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('07:15'), findsOneWidget);
  });
}
