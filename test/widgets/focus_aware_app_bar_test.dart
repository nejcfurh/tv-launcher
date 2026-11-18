import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/providers/network_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/app_bar_focus_ring.dart';
import 'package:flauncher/widgets/focus_aware_app_bar.dart';
import 'package:flauncher/widgets/network_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

void main() {
  group('FocusAwareAppBar', () {
    late MockSettingsService settingsService;
    late LauncherState launcherState;
    late GlobalKey<FocusAwareAppBarState> appBarKey;

    setUp(() {
      settingsService = MockSettingsService();
      launcherState = LauncherState();
      appBarKey = GlobalKey<FocusAwareAppBarState>();

      when(settingsService.autoHideAppBarEnabled).thenReturn(false);
      when(settingsService.hideStatusBarInGrid).thenReturn(false);
      when(settingsService.showDateInStatusBar).thenReturn(false);
      when(settingsService.showTimeInStatusBar).thenReturn(true);
      when(settingsService.showWifiWidgetInStatusBar).thenReturn(false);
      when(settingsService.showNetworkIndicatorInStatusBar).thenReturn(false);
      when(settingsService.timeFormat).thenReturn('HH:mm');
      when(settingsService.dateFormat).thenReturn('yyyy-MM-dd');
      when(settingsService.accentColorHex).thenReturn('6750A4');
    });

    Widget createTestWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settingsService),
          ChangeNotifierProvider<LauncherState>.value(value: launcherState),
          ChangeNotifierProvider<AppsService>.value(value: MockAppsService()),
          ChangeNotifierProvider(create: (_) => NetworkService(FLauncherChannel())),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: FocusAwareAppBar(key: appBarKey),
            body: const SizedBox.expand(),
          ),
        ),
      );
    }

    testWidgets('settings glyph starts and the clock ends on the 48 dp keylines', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(tester.getTopLeft(find.byIcon(Icons.settings_outlined)).dx, 48);
      expect(tester.getSize(find.byIcon(Icons.settings_outlined)), const Size(18, 18));
      expect(tester.getTopRight(find.byKey(const Key('statusbar_clock'))).dx, width - 48);
    });

    testWidgets('network status sits with the clock and cannot take focus', (tester) async {
      when(settingsService.showNetworkIndicatorInStatusBar).thenReturn(true);
      when(settingsService.showDateInStatusBar).thenReturn(true);
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final network = find.byType(NetworkWidget);
      expect(network, findsOneWidget);
      expect(find.ancestor(of: network, matching: find.byType(AppBarFocusRing)), findsNothing);
      expect(find.descendant(of: network, matching: find.byType(InkWell)), findsNothing);
      expect(tester.getCenter(network).dx, greaterThan(tester.getCenter(find.byIcon(Icons.settings_outlined)).dx));
      expect(tester.getTopRight(network).dx, lessThan(tester.getTopLeft(find.byKey(const Key('statusbar_date'))).dx));
    });

    testWidgets('date and time share a baseline and have no backdrop', (tester) async {
      when(settingsService.showDateInStatusBar).thenReturn(true);
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final date = find.descendant(of: find.byKey(const Key('statusbar_date')), matching: find.byType(Text));
      final time = find.descendant(of: find.byKey(const Key('statusbar_clock')), matching: find.byType(Text));
      final dateStyle = tester.widget<Text>(date).style!;
      final timeStyle = tester.widget<Text>(time).style!;
      expect(dateStyle.fontSize, 14);
      expect(timeStyle.fontSize, 22);
      expect(dateStyle.shadows, isNotEmpty);
      expect(timeStyle.shadows, isNotEmpty);
      double baseline(Finder f) {
        final text = tester.widget<Text>(f);
        final painter = TextPainter(
          text: TextSpan(text: text.data, style: DefaultTextStyle.of(tester.element(f)).style.merge(text.style)),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(tester.element(f)),
        )..layout();
        final distance = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
        painter.dispose();
        return tester.getTopLeft(f).dy + distance;
      }
      expect(baseline(date), moreOrLessEquals(baseline(time), epsilon: 0.5));
      // Nothing with a visible fill sits behind the characters.
      bool visibleFill(Widget w) =>
          (w is ColoredBox && w.color.a > 0) ||
          (w is DecoratedBox && w.decoration is BoxDecoration && ((w.decoration as BoxDecoration).color?.a ?? 0) > 0);
      expect(find.ancestor(of: date, matching: find.byWidgetPredicate(visibleFill)), findsNothing);
    });

    testWidgets('status bar is fully visible when neither autoHide nor hideInGrid is active', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsOneWidget);
      final container = tester.widget<AnimatedContainer>(
        find.descendant(of: find.byType(FocusAwareAppBar), matching: find.byType(AnimatedContainer)),
      );
      final opacity = tester.widget<AnimatedOpacity>(
        find.descendant(of: find.byType(FocusAwareAppBar), matching: find.byType(AnimatedOpacity)),
      );
      expect(container.constraints?.maxHeight, kToolbarHeight);
      expect(opacity.opacity, 1.0);
    });

    testWidgets('hides status bar when in grid if hideStatusBarInGrid is true', (tester) async {
      when(settingsService.hideStatusBarInGrid).thenReturn(true);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Initially on home/dock (appGridFocused is false), status bar is visible
      AnimatedContainer container = tester.widget<AnimatedContainer>(
        find.descendant(of: find.byType(FocusAwareAppBar), matching: find.byType(AnimatedContainer)),
      );
      AnimatedOpacity opacity = tester.widget<AnimatedOpacity>(
        find.descendant(of: find.byType(FocusAwareAppBar), matching: find.byType(AnimatedOpacity)),
      );
      expect(container.constraints?.maxHeight, kToolbarHeight);
      expect(opacity.opacity, 1.0);

      // User navigates down into the grid
      launcherState.setAppGridFocused(true);
      await tester.pumpAndSettle();

      // Status bar should be hidden
      container = tester.widget<AnimatedContainer>(
        find.descendant(of: find.byType(FocusAwareAppBar), matching: find.byType(AnimatedContainer)),
      );
      opacity = tester.widget<AnimatedOpacity>(
        find.descendant(of: find.byType(FocusAwareAppBar), matching: find.byType(AnimatedOpacity)),
      );
      expect(container.constraints?.maxHeight, 0.0);
      expect(opacity.opacity, 0.0);

      // User navigates back up to dock
      launcherState.setAppGridFocused(false);
      await tester.pumpAndSettle();

      // Status bar should be visible again
      container = tester.widget<AnimatedContainer>(
        find.descendant(of: find.byType(FocusAwareAppBar), matching: find.byType(AnimatedContainer)),
      );
      opacity = tester.widget<AnimatedOpacity>(
        find.descendant(of: find.byType(FocusAwareAppBar), matching: find.byType(AnimatedOpacity)),
      );
      expect(container.constraints?.maxHeight, kToolbarHeight);
      expect(opacity.opacity, 1.0);
    });

    testWidgets('remains visible in grid if hideStatusBarInGrid is false', (tester) async {
      when(settingsService.hideStatusBarInGrid).thenReturn(false);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      launcherState.setAppGridFocused(true);
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('focusing settings button makes status bar visible even when autoHide is true', (tester) async {
      when(settingsService.autoHideAppBarEnabled).thenReturn(true);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Initially auto-hidden
      AnimatedContainer container = tester.widget<AnimatedContainer>(
        find.descendant(of: find.byType(FocusAwareAppBar), matching: find.byType(AnimatedContainer)),
      );
      AnimatedOpacity opacity = tester.widget<AnimatedOpacity>(
        find.descendant(of: find.byType(FocusAwareAppBar), matching: find.byType(AnimatedOpacity)),
      );
      IgnorePointer ignorePointer = tester.widget<IgnorePointer>(
        find.descendant(of: find.byType(FocusAwareAppBar), matching: find.byType(IgnorePointer)),
      );
      expect(container.constraints?.maxHeight, 0.0);
      expect(opacity.opacity, 0.0);
      expect(ignorePointer.ignoring, isTrue);

      // Focus settings
      appBarKey.currentState?.focusSettings();
      await tester.pumpAndSettle();

      container = tester.widget<AnimatedContainer>(
        find.descendant(of: find.byType(FocusAwareAppBar), matching: find.byType(AnimatedContainer)),
      );
      opacity = tester.widget<AnimatedOpacity>(
        find.descendant(of: find.byType(FocusAwareAppBar), matching: find.byType(AnimatedOpacity)),
      );
      ignorePointer = tester.widget<IgnorePointer>(
        find.descendant(of: find.byType(FocusAwareAppBar), matching: find.byType(IgnorePointer)),
      );
      expect(container.constraints?.maxHeight, kToolbarHeight);
      expect(opacity.opacity, 1.0);
      expect(ignorePointer.ignoring, isFalse);
    });

    testWidgets('focusing settings resets appGridFocused and reveals status bar', (tester) async {
      when(settingsService.hideStatusBarInGrid).thenReturn(true);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      launcherState.setAppGridFocused(true);
      await tester.pumpAndSettle();

      expect(launcherState.appGridFocused, isTrue);
      AnimatedContainer container = tester.widget<AnimatedContainer>(
        find.descendant(of: find.byType(FocusAwareAppBar), matching: find.byType(AnimatedContainer)),
      );
      expect(container.constraints?.maxHeight, 0.0);

      appBarKey.currentState?.focusSettings();
      await tester.pumpAndSettle();

      expect(launcherState.appGridFocused, isFalse);
      container = tester.widget<AnimatedContainer>(
        find.descendant(of: find.byType(FocusAwareAppBar), matching: find.byType(AnimatedContainer)),
      );
      expect(container.constraints?.maxHeight, kToolbarHeight);
    });
  });
}
