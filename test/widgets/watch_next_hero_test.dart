import 'dart:typed_data';

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/app.dart';
import 'package:flauncher/models/watch_next_item.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/watch_next_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.dart';
import '../mocks.mocks.dart';

class TestWatchNextService extends ChangeNotifier implements WatchNextService {
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

    testWidgets('renders title, description, badge, and Resume button', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Severance'), findsOneWidget);
      expect(find.textContaining('Mark leads a team'), findsOneWidget);
      expect(find.text('WATCH NEXT ON'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
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
      expect(find.descendant(of: badgeRow, matching: find.byType(Image)), findsOneWidget);
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
        final badge = find.ancestor(of: find.text('WATCH NEXT ON'), matching: find.byType(Container)).first;
        return tester.getSize(badge).height;
      }

      await tester.pumpWidget(createTestWidget());
      final withLogo = await badgeHeight();

      appsService.foregroundIcon = Uint8List(0);
      watchNextService.testItems = disneyItems;
      await tester.pumpWidget(createTestWidget(items: disneyItems));
      final withName = await badgeHeight();

      expect(withName, withLogo);
    });

    testWidgets('clicking watch button triggers launchItem', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Resume'));
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

      // Find the AnimatedContainer corresponding to the button (the one with height 48)
      final watchButtonContainer = tester.widget<AnimatedContainer>(
        find.ancestor(
          of: find.text('Resume'),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(watchButtonContainer.constraints?.maxHeight ?? 48.0, 48.0);

      final initialSize = tester.getSize(
        find.ancestor(
          of: find.text('Resume'),
          matching: find.byType(AnimatedContainer),
        ),
      );

      // Focus another node or unfocus
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      final unfocusedSize = tester.getSize(
        find.ancestor(
          of: find.text('Resume'),
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
}
