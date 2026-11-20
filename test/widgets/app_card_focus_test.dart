import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/app_card.dart';
import 'package:flauncher/widgets/app_card_contour_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.dart';
import '../mocks.mocks.dart';

void main() {
  late MockSettingsService settings;
  late MockAppsService apps;

  setUp(() {
    settings = MockSettingsService();
    apps = MockAppsService();
    when(settings.accentColorHex).thenReturn('7C4DFF');
    when(settings.showFocusBorders).thenReturn(true);
    when(settings.focusBorderThickness).thenReturn(2);
    when(settings.appHighlightAnimationEnabled).thenReturn(true);
    when(settings.showAppNamesBelowIcons).thenReturn(false);
    when(settings.appNamesOnFocusOnly).thenReturn(false);
    when(settings.cardCornerRadius).thenReturn(12);
    when(settings.customAppLabel(any)).thenReturn(null);
    // No artwork: the tile shows its fallback, which is enough for the focus tests.
    when(apps.getAppBanner(any)).thenAnswer((_) async => throw StateError('no artwork'));
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  });

  tearDown(() {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  Widget card({required bool dockTile, bool autofocus = true}) => MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<AppsService>.value(value: apps),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 164,
                height: 92,
                child: AppCard(
                  application: fakeApp(packageName: 'app.test'),
                  category: fakeCategory(),
                  autofocus: autofocus,
                  onMove: (_) {},
                  onMoveEnd: () {},
                  enforceAspectRatio: false,
                  dockTile: dockTile,
                ),
              ),
            ),
          ),
        ),
      );

  group('focused grid tile with the highlight animation on', () {
    testWidgets('pulses a few times, then stops scheduling frames', (tester) async {
      await tester.pumpWidget(card(dockTile: false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.hasScheduledFrame, isTrue, reason: 'pulsing right after focus');

      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('ends on a fully opaque outline', (tester) async {
      await tester.pumpWidget(card(dockTile: false));
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final painter = tester
          .widget<CustomPaint>(find.byWidgetPredicate(
              (w) => w is CustomPaint && w.foregroundPainter is AppCardContourPainter))
          .foregroundPainter! as AppCardContourPainter;
      expect(painter.alpha, 1.0);
    });
  });
}
