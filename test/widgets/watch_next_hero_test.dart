import 'dart:io';

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/app.dart';
import 'package:flauncher/models/watch_next_item.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/watch_next_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.dart';
import '../mocks.mocks.dart';

class TestWatchNextService extends ChangeNotifier implements WatchNextService {
  @override
  Future<void> Function(WatchNextItem item)? heroSwitchGate;

  List<WatchNextItem> _items = [];
  int _activeHeroIndex = 0;
  WatchNextItem? launchedItem;

  @override
  List<WatchNextItem> get items => _items;

  set testItems(List<WatchNextItem> newItems) {
    _items = newItems;
    notifyListeners();
  }

  @override
  int get activeHeroIndex => _activeHeroIndex;

  @override
  WatchNextItem? get activeHeroItem =>
      _items.isNotEmpty && _activeHeroIndex < _items.length ? _items[_activeHeroIndex] : null;

  @override
  void setActiveHeroIndex(int index) {
    if (_items.isEmpty) return;
    _activeHeroIndex = index.clamp(0, _items.length - 1);
    notifyListeners();
  }

  @override
  void nextHeroItem() {
    if (_items.isEmpty) return;
    setActiveHeroIndex((_activeHeroIndex + 1) % _items.length);
  }

  @override
  void prevHeroItem() {
    if (_items.isEmpty) return;
    setActiveHeroIndex((_activeHeroIndex - 1 + _items.length) % _items.length);
  }

  @override
  Future<void> launchItem(WatchNextItem item) async {
    launchedItem = item;
  }

  @override
  bool get hasItems => _items.isNotEmpty;

  @override
  bool get hasPermission => true;

  @override
  bool get hasVisibleSection => _items.isNotEmpty;

  @override
  bool get isLoading => false;

  @override
  Future<void> checkPermission() async {}

  @override
  String? getPosterUriForItem(WatchNextItem? item) => item?.backdropUri ?? item?.posterUri;

  @override
  void ensurePosterLoaded(String? uri) {}

  @override
  Uint8List? getCachedPoster(String? uri) => null;

  @override
  bool hasPosterLoadFailed(String? uri) => false;

  @override
  bool itemHasImage(WatchNextItem item) => item.hasImage;

  @override
  Future<void> refreshItems() async {}

  @override
  Future<void> refreshPermissionAndItems() async {}

  @override
  Future<void> requestPermission() async {}

  @override
  Set<String> get availablePackageNames =>
      _items.map((e) => e.packageName).whereType<String>().toSet();

  @override
  Future<void> forceRefresh() async {}
}

class TestAppsService extends ChangeNotifier implements AppsService {
  @override
  App? getApplication(String? packageName) {
    if (packageName == 'com.netflix.ninja') {
      return fakeApp(
        packageName: 'com.netflix.ninja',
        name: 'Netflix',
      );
    }
    if (packageName == 'com.disney.disneyplus') {
      return fakeApp(packageName: 'com.disney.disneyplus', name: 'Disney+');
    }
    return null;
  }

  final List<String> foregroundIconRequests = [];
  Uint8List? foregroundIcon;

  @override
  Future<Uint8List> getAppIconForeground(String packageName) async {
    foregroundIconRequests.add(packageName);
    return foregroundIcon ?? _onePixelPng;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final Uint8List _onePixelPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
]);

void main() {
  group('WatchNextHero', () {
    late MockSettingsService settingsService;
    late TestWatchNextService watchNextService;
    late TestAppsService appsService;

    final sampleItems = [
      WatchNextItem(
        id: 1,
        title: 'Severance',
        description: 'Mark leads a team of office workers whose memories have been surgically divided.',
        packageName: 'com.netflix.ninja',
        backdropUri: 'https://example.com/severance_backdrop.jpg',
        posterUri: 'https://example.com/severance_poster.jpg',
        progressPercent: 45,
      ),
      WatchNextItem(
        id: 2,
        title: 'Ted Lasso',
        description: 'An American college football coach heads to the UK to manage a British football team.',
        packageName: 'com.netflix.ninja',
        backdropUri: 'https://example.com/ted_lasso_backdrop.jpg',
        posterUri: 'https://example.com/ted_lasso_poster.jpg',
        progressPercent: 0,
      ),
    ];

    setUp(() {
      settingsService = MockSettingsService();
      when(settingsService.showFocusBorders).thenReturn(true);
      when(settingsService.focusBorderThickness).thenReturn(1.5);
      when(settingsService.appKeyClickEnabled).thenReturn(false);

      watchNextService = TestWatchNextService();
      watchNextService.testItems = sampleItems;

      appsService = TestAppsService();
    });

    Widget createTestWidget({List<WatchNextItem>? items}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settingsService),
          ChangeNotifierProvider<WatchNextService>.value(value: watchNextService),
          ChangeNotifierProvider<AppsService>.value(value: appsService),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: WatchNextHero(
              items: items ?? sampleItems,
              isFirstSection: true,
            ),
          ),
        ),
      );
    }

    testWidgets('renders title, badge and Watch, and never the synopsis', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Severance'), findsOneWidget);
      expect(find.textContaining('Mark leads a team'), findsNothing);
      expect(find.text('WATCH NEXT ON'), findsOneWidget);
      // The label stays "Watch" even for an item with progress.
      expect(find.text('Watch'), findsOneWidget);
      expect(find.text('Resume'), findsNothing);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('badge reads WATCH NEXT ON followed by the white Netflix logo', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final badgeRow = find.ancestor(of: find.text('WATCH NEXT ON'), matching: find.byType(Row)).first;
      expect(
        find.descendant(
          of: badgeRow,
          matching: find.byWidgetPredicate(
              (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/logo_netflix.png'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('NETFLIX'), findsNothing);
      expect(appsService.foregroundIconRequests, isEmpty);
    });

    final disneyItems = [
      WatchNextItem(id: 3, title: 'black-ish', packageName: 'com.disney.disneyplus'),
    ];

    testWidgets('badge uses the app icon layer for apps without a bundled logo', (tester) async {
      watchNextService.testItems = disneyItems;
      await tester.pumpWidget(createTestWidget(items: disneyItems));
      await tester.pumpAndSettle();

      expect(appsService.foregroundIconRequests, contains('com.disney.disneyplus'));
      final badgeRow = find.ancestor(of: find.text('WATCH NEXT ON'), matching: find.byType(Row)).first;
      final logo = tester.widget<Image>(find.descendant(of: badgeRow, matching: find.byType(Image)));
      expect(logo.color, Colors.white);
      expect(logo.colorBlendMode, BlendMode.srcIn);
      expect(find.textContaining('DISNEY'), findsNothing);
    });

    testWidgets('badge names the source app when it has no icon', (tester) async {
      appsService.foregroundIcon = Uint8List(0);
      watchNextService.testItems = disneyItems;
      await tester.pumpWidget(createTestWidget(items: disneyItems));
      await tester.pumpAndSettle();

      expect(find.text('WATCH NEXT ON'), findsOneWidget);
      expect(find.text(' DISNEY+'), findsOneWidget);
    });

    testWidgets('badge keeps the same height with a logo and with only a name', (tester) async {
      Future<double> badgeHeight() async {
        await tester.pumpAndSettle();
        return tester.getSize(find.byKey(const Key('hero_service_row'))).height;
      }

      await tester.pumpWidget(createTestWidget());
      final withLogo = await badgeHeight();

      appsService.foregroundIcon = Uint8List(0);
      watchNextService.testItems = disneyItems;
      await tester.pumpWidget(createTestWidget(items: disneyItems));
      final withName = await badgeHeight();

      expect(withName, withLogo);
    });

    testWidgets('service row has no border or fill', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(
        find.ancestor(
          of: find.text('WATCH NEXT ON'),
          matching: find.byWidgetPredicate((w) => w is Container && w.decoration != null),
        ),
        findsNothing,
      );
    });

    final fullSeriesItem = WatchNextItem(
      id: 10,
      title: 'The Office (U.S.)',
      packageName: 'com.netflix.ninja',
      programType: kWatchNextTypeTvEpisode,
      seasonNumber: '5',
      episodeNumber: '12',
      duration: 22 * 60000,
      playbackPositionMillis: 13 * 60000,
      progressPercent: 59,
      genres: const ['COMEDY'],
    );

    testWidgets('series shows season, episode, time left, genre and progress', (tester) async {
      watchNextService.testItems = [fullSeriesItem];
      await tester.pumpWidget(createTestWidget(items: [fullSeriesItem]));
      await tester.pumpAndSettle();

      expect(find.text('Season 5 · Episode 12 · 9 min left'), findsOneWidget);
      expect(find.text('Comedy'), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('hero_progress'))), const Size(160, 2));
    });

    testWidgets('with every row present the Watch button ends exactly at the bottom of the hero box', (tester) async {
      watchNextService.testItems = [fullSeriesItem];
      await tester.pumpWidget(createTestWidget(items: [fullSeriesItem]));
      await tester.pumpAndSettle();

      final heroTop = tester.getTopLeft(find.byType(WatchNextHero)).dy;
      final button = find.ancestor(of: find.text('Watch'), matching: find.byType(AnimatedContainer));
      expect(tester.getBottomLeft(button).dy - heroTop, moreOrLessEquals(kWatchNextHeroHeight, epsilon: 0.5));
      // Rows sit where the spec puts them, relative to the service row at y = 226.
      expect(tester.getTopLeft(find.byKey(const Key('hero_title'))).dy - heroTop, moreOrLessEquals(29, epsilon: 0.5));
      expect(tester.getTopLeft(find.byKey(const Key('hero_meta_1'))).dy - heroTop, moreOrLessEquals(80, epsilon: 0.5));
      expect(tester.getTopLeft(find.byKey(const Key('hero_progress'))).dy - heroTop, moreOrLessEquals(127, epsilon: 0.5));
    });

    testWidgets('missing rows are removed and the Watch button moves up', (tester) async {
      watchNextService.testItems = [fullSeriesItem];
      await tester.pumpWidget(createTestWidget(items: [fullSeriesItem]));
      await tester.pumpAndSettle();
      final fullButtonTop = tester.getTopLeft(find.text('Watch')).dy;
      final heroHeight = tester.getSize(find.byType(WatchNextHero)).height;

      final bare = WatchNextItem(id: 11, title: 'Bare item', packageName: 'com.netflix.ninja', description: 'A synopsis');
      watchNextService.testItems = [bare];
      await tester.pumpWidget(createTestWidget(items: [bare]));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hero_meta_1')), findsNothing);
      expect(find.byKey(const Key('hero_meta_2')), findsNothing);
      expect(find.byKey(const Key('hero_progress')), findsNothing);
      expect(find.text('A synopsis'), findsNothing);
      expect(tester.getTopLeft(find.text('Watch')).dy, lessThan(fullButtonTop));
      // The hero keeps its height, so the dock below does not move.
      expect(tester.getSize(find.byType(WatchNextHero)).height, heroHeight);
    });

    testWidgets('no playback position: no progress bar and no time left', (tester) async {
      final noPosition = WatchNextItem(
        id: 12,
        title: 'The Office (U.S.)',
        packageName: 'com.netflix.ninja',
        programType: kWatchNextTypeTvEpisode,
        seasonNumber: '5',
        episodeNumber: '12',
        duration: 22 * 60000,
      );
      watchNextService.testItems = [noPosition];
      await tester.pumpWidget(createTestWidget(items: [noPosition]));
      await tester.pumpAndSettle();

      expect(find.text('Season 5 · Episode 12'), findsOneWidget);
      expect(find.textContaining('left'), findsNothing);
      expect(find.byKey(const Key('hero_progress')), findsNothing);
    });

    testWidgets('chevrons show only while the hero has focus and there is more than one item', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      // The Watch button autofocuses (isFirstSection).
      expect(find.byKey(const Key('hero_chevron_left')), findsOneWidget);
      expect(find.byKey(const Key('hero_chevron_right')), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const Key('hero_chevron_left'))).dx, 14);
      final width = tester.getSize(find.byType(WatchNextHero)).width;
      expect(tester.getTopRight(find.byKey(const Key('hero_chevron_right'))).dx, width - 14);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hero_chevron_left')), findsNothing);
      expect(find.byKey(const Key('hero_chevron_right')), findsNothing);
    });

    testWidgets('a single item has no chevrons and no dots', (tester) async {
      final single = [sampleItems.first];
      watchNextService.testItems = single;
      await tester.pumpWidget(createTestWidget(items: single));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hero_chevron_left')), findsNothing);
      expect(find.byKey(const Key('hero_dots')), findsNothing);
    });

    testWidgets('dots end on the right keyline, centred on the Watch button', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      final width = tester.getSize(find.byType(WatchNextHero)).width;
      final dots = find.byKey(const Key('hero_dots'));
      expect(tester.getTopRight(dots).dx, width - 48);
      expect(tester.getSize(dots).height, 6);
      final button = find.ancestor(of: find.text('Watch'), matching: find.byType(AnimatedContainer));
      expect(tester.getCenter(dots).dy, moreOrLessEquals(tester.getCenter(button).dy, epsilon: 0.5));
      expect(tester.getSize(button).height, 36);
    });

    testWidgets('Left and Right swap the text in 400 ms without showing both items at once', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      double opacityOf(String title) {
        final finder = find.text(title);
        if (finder.evaluate().isEmpty) return 0;
        return tester
            .widgetList<FadeTransition>(find.ancestor(of: finder, matching: find.byType(FadeTransition)))
            .fold(1.0, (opacity, fade) => opacity * fade.opacity.value);
      }

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      var sawOld = false;
      var sawNew = false;
      for (var elapsed = 0; elapsed < 400; elapsed += 20) {
        final old = opacityOf('Severance');
        final next = opacityOf('Ted Lasso');
        expect(old > 0 && next > 0, isFalse, reason: 'both visible at $elapsed ms: $old / $next');
        sawOld |= old > 0;
        sawNew |= next > 0;
        if (elapsed == 100) expect(next, 0, reason: 'the new item waits until the old one is gone');
        if (elapsed == 300) expect(old, 0, reason: 'the old item is gone by the second half');
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(sawOld, isTrue);
      expect(sawNew, isTrue);

      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Severance'), findsNothing);
      expect(opacityOf('Ted Lasso'), 1);
    });

    test('every bundled source logo exists', () {
      for (final logo in kSourceAppLogoAssets.values) {
        expect(File(logo.asset).existsSync(), isTrue, reason: logo.asset);
        expect(logo.height, inInclusiveRange(10, 18), reason: logo.asset);
      }
      expect(kSourceAppLogoAssets['com.skyshowtime.skyshowtime.google']?.asset, 'assets/logo_skyshowtime.png');
      // HBO and SkyShowtime are wide, heavy wordmarks, so they are shown smaller than the 18 px maximum.
      expect(kSourceAppLogoAssets['com.wbd.stream']!.height, 13);
      expect(kSourceAppLogoAssets['com.skyshowtime.skyshowtime.google']!.height, 14);
    });

    testWidgets('clicking watch button triggers launchItem', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Watch'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(watchNextService.launchedItem?.title, 'Severance');
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('next and prev navigation switches active item', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Severance'), findsOneWidget);

      watchNextService.nextHeroItem();
      await tester.pumpAndSettle();

      expect(find.text('Ted Lasso'), findsOneWidget);
      expect(find.text('Watch'), findsOneWidget);

      watchNextService.prevHeroItem();
      await tester.pumpAndSettle();

      expect(find.text('Severance'), findsOneWidget);
    });

    testWidgets('Watch button does not change size on focus/hover', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final buttonFinder = find.byType(AnimatedContainer);
      expect(buttonFinder, findsWidgets);

      // Find the AnimatedContainer corresponding to the button (the one with height 36)
      final watchButtonContainer = tester.widget<AnimatedContainer>(
        find.ancestor(
          of: find.text('Watch'),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(watchButtonContainer.constraints?.maxHeight, 36.0);

      final initialSize = tester.getSize(
        find.ancestor(
          of: find.text('Watch'),
          matching: find.byType(AnimatedContainer),
        ),
      );

      // Focus another node or unfocus
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      final unfocusedSize = tester.getSize(
        find.ancestor(
          of: find.text('Watch'),
          matching: find.byType(AnimatedContainer),
        ),
      );

      expect(unfocusedSize, equals(initialSize));
    });

    testWidgets('WatchNextHero maintains fixed height between items with and without synopsis', (tester) async {
      final items = [
        WatchNextItem(
          id: 101,
          title: 'Program With Full Synopsis',
          description: 'This is a complete two-line synopsis that gives detailed information about the episode and plot.',
          packageName: 'com.plexapp.android',
          progressPercent: 55,
        ),
        WatchNextItem(
          id: 102,
          title: 'Program Without Any Synopsis',
          description: null,
          packageName: 'com.plexapp.android',
          progressPercent: 0,
        ),
      ];

      watchNextService.testItems = items;
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final heroFinder = find.byType(WatchNextHero);
      expect(heroFinder, findsOneWidget);

      final sizeWithSynopsis = tester.getSize(heroFinder);

      // Switch to program without synopsis
      watchNextService.nextHeroItem();
      await tester.pumpAndSettle();

      final sizeWithoutSynopsis = tester.getSize(heroFinder);

      expect(sizeWithoutSynopsis.height, equals(sizeWithSynopsis.height));
    });
  });

  group('carouselDirection', () {
    test('next and previous, wrapping around the ends', () {
      expect(carouselDirection(0, 1, 6), 1);
      expect(carouselDirection(5, 0, 6), 1);
      expect(carouselDirection(1, 0, 6), -1);
      expect(carouselDirection(0, 5, 6), -1);
    });

    test('a jump goes the way the index moved', () {
      expect(carouselDirection(1, 4, 6), 1);
      expect(carouselDirection(4, 1, 6), -1);
    });
  });

  group('carouselTransition', () {
    // An AnimatedSwitcher runs the incoming child 0 → 1 and the outgoing one 1 → 0 over the same
    // time, so at elapsed fraction t the incoming value is t and the outgoing value is 1 - t.
    double opacityAt(double value, {required bool incoming}) {
      final fade = carouselTransition(
        child: const SizedBox(),
        animation: AlwaysStoppedAnimation(value),
        incoming: incoming,
        direction: 1,
      ) as FadeTransition;
      return fade.opacity.value;
    }

    test('the outgoing child is gone before the incoming one appears', () {
      for (var t = 0.0; t <= 1.0; t += 0.05) {
        final outgoing = opacityAt(1 - t, incoming: false);
        final incoming = opacityAt(t, incoming: true);
        expect(outgoing > 0 && incoming > 0, isFalse, reason: 't = $t: $outgoing / $incoming');
      }
      expect(opacityAt(1, incoming: false), 1);
      expect(opacityAt(0.5, incoming: false), 0);
      expect(opacityAt(0.5, incoming: true), 0);
      expect(opacityAt(1, incoming: true), 1);
    });
  });
}
