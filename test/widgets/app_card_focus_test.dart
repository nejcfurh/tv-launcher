import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/app_card.dart';
import 'package:flauncher/widgets/app_card_contour_painter.dart';
import 'package:flauncher/widgets/dock_focus_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.dart';
import '../mocks.mocks.dart';

/// A 160x90 PNG: [edge] colour on the outer 16 px, [centre] inside.
Future<Uint8List> _tileArt(Color edge, Color centre) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 160, 90), Paint()..color = edge);
  canvas.drawRect(const Rect.fromLTWH(16, 16, 128, 58), Paint()..color = centre);
  final image = recorder.endRecording().toImageSync(160, 90);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

ByteData _solid(int width, int height, Color colour) {
  final data = ByteData(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    data.setUint8(i * 4, (colour.r * 255).round());
    data.setUint8(i * 4 + 1, (colour.g * 255).round());
    data.setUint8(i * 4 + 2, (colour.b * 255).round());
    data.setUint8(i * 4 + 3, (colour.a * 255).round());
  }
  return data;
}

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

  group('dark tile art', () {
    test('a black tile is dark', () {
      expect(isDarkTileArt(_solid(40, 20, Colors.black), 40), isTrue);
    });

    test('a white tile is not dark', () {
      expect(isDarkTileArt(_solid(40, 20, Colors.white), 40), isFalse);
    });

    test('a brand-blue tile is not dark', () {
      expect(isDarkTileArt(_solid(40, 20, const Color(0xFF0070D1)), 40), isFalse);
    });

    test('a transparent tile counts as dark, since the tray shows through', () {
      expect(isDarkTileArt(_solid(40, 20, const Color(0x00FFFFFF)), 40), isTrue);
    });

    testWidgets('dark edges with a bright logo in the middle are dark; the reverse is not', (tester) async {
      Future<bool> darkness(Color edge, Color centre) async {
        late bool result;
        await tester.runAsync(() async {
          final png = await _tileArt(edge, centre);
          final image = (await (await ui.instantiateImageCodec(png)).getNextFrame()).image;
          final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          result = isDarkTileArt(bytes, image.width);
          image.dispose();
        });
        return result;
      }

      expect(await darkness(const Color(0xFF1C1C1E), Colors.white), isTrue);
      expect(await darkness(Colors.white, Colors.black), isFalse);
    });
  });

  group('dock tile inner border', () {
    Future<DockTileInnerBorder> borderFor(WidgetTester tester, Color edge) async {
      late Uint8List png;
      await tester.runAsync(() async => png = await _tileArt(edge, Colors.white));
      when(apps.getAppBanner(any)).thenAnswer((_) async => png);
      await tester.runAsync(() async {
        await tester.pumpWidget(card(dockTile: true, autofocus: false));
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      await tester.pump(const Duration(milliseconds: 300));
      return tester.widget<DockTileInnerBorder>(find.byType(DockTileInnerBorder));
    }

    testWidgets('is stronger on a tile with dark edges', (tester) async {
      expect((await borderFor(tester, const Color(0xFF1C1C1E))).dark, isTrue);
    });

    testWidgets('stays a hairline on a bright tile', (tester) async {
      expect((await borderFor(tester, const Color(0xFFE50914))).dark, isFalse);
    });
  });
}
