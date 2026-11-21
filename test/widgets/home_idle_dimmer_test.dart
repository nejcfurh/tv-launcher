import 'package:flauncher/widgets/home_idle_dimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const timeout = Duration(seconds: 10);

  late FocusNode first;
  late FocusNode second;
  late int presses;
  late bool allowDim;
  late GlobalKey<HomeIdleDimmerState> dimmerKey;

  setUp(() {
    first = FocusNode(debugLabel: 'first');
    second = FocusNode(debugLabel: 'second');
    presses = 0;
    allowDim = true;
    dimmerKey = GlobalKey();
  });

  tearDown(() {
    first.dispose();
    second.dispose();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeIdleDimmer(
        key: dimmerKey,
        timeout: timeout,
        canDim: () => allowDim,
        builder: (context, dimmed) => Column(children: [
          Text(dimmed ? 'dimmed' : 'lit'),
          TextButton(focusNode: first, autofocus: true, onPressed: () => presses++, child: const Text('first')),
          TextButton(focusNode: second, onPressed: () {}, child: const Text('second')),
        ]),
      ),
    ));
    await tester.pump();
  }

  testWidgets('dims after the timeout without a key press', (tester) async {
    await pumpHome(tester);
    expect(find.text('lit'), findsOneWidget);

    await tester.pump(timeout + const Duration(milliseconds: 100));

    expect(find.text('dimmed'), findsOneWidget);
  });

  testWidgets('a key press restarts the timeout', (tester) async {
    await pumpHome(tester);
    await tester.pump(timeout - const Duration(seconds: 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(seconds: 5));

    expect(find.text('lit'), findsOneWidget);
    await tester.pump(timeout);
    expect(find.text('dimmed'), findsOneWidget);
  });

  testWidgets('the first press only wakes Home; the tile gets the next one', (tester) async {
    await pumpHome(tester);
    await tester.pump(timeout + const Duration(milliseconds: 100));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.text('lit'), findsOneWidget);
    expect(presses, 0, reason: 'the waking press must not activate the tile');
    expect(first.hasPrimaryFocus, isTrue, reason: 'focus is back where it was');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 1);
  });

  testWidgets('an arrow that wakes Home does not move focus', (tester) async {
    await pumpHome(tester);
    await tester.pump(timeout + const Duration(milliseconds: 100));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(first.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(second.hasPrimaryFocus, isTrue);
  });

  testWidgets('a held key that wakes Home is swallowed until it is released', (tester) async {
    await pumpHome(tester);
    await tester.pump(timeout + const Duration(milliseconds: 100));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(presses, 0);
    expect(first.hasPrimaryFocus, isTrue);
  });

  testWidgets('stays lit while something is open over Home', (tester) async {
    allowDim = false;
    await pumpHome(tester);

    await tester.pump(timeout * 3);

    expect(find.text('lit'), findsOneWidget);
    expect(first.hasPrimaryFocus, isTrue);
  });

  testWidgets('the Home button wakes it and gives focus back', (tester) async {
    await pumpHome(tester);
    await tester.pump(timeout + const Duration(milliseconds: 100));

    dimmerKey.currentState!.wake();
    await tester.pump();

    expect(find.text('lit'), findsOneWidget);
    expect(first.hasPrimaryFocus, isTrue);
  });

  testWidgets('leaving the app wakes it', (tester) async {
    await pumpHome(tester);
    await tester.pump(timeout + const Duration(milliseconds: 100));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(dimmerKey.currentState!.dimmed, isFalse);

    // Frames are off while paused; back on Home, it is lit and focus is where it was.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('lit'), findsOneWidget);
    expect(first.hasPrimaryFocus, isTrue);
  });

  testWidgets('nothing keeps animating once dimmed', (tester) async {
    await pumpHome(tester);
    await tester.pump(timeout + const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2));

    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
