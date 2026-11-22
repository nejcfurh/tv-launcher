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
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flauncher/build_flags.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher.dart';
import 'package:flauncher/widgets/dock_band.dart';
import 'package:flauncher/widgets/home_idle_dimmer.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/gradients.dart';
import 'package:flauncher/models/watch_next_item.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/providers/network_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/application_info_panel.dart';
import 'package:flauncher/widgets/apps_grid.dart';
import 'package:flauncher/widgets/cached_blur_backdrop.dart';
import 'package:flauncher/widgets/category_clean_row.dart';
import 'package:flauncher/widgets/category_row.dart';
import 'package:flauncher/widgets/focus_aware_app_bar.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flauncher/widgets/settings/settings_panel_page.dart';
import 'package:flauncher/widgets/vlc_cone_icon.dart';
import 'package:flauncher/widgets/watch_next_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'helpers.dart';
import 'mocks.dart';
import 'mocks.mocks.dart';


void main() {
  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.window.physicalSizeTestValue = Size(1280, 720);
    binding.window.devicePixelRatioTestValue = 1.0;
    // Scale-down the font size because the font 'Ahem' used when running tests is much wider than Roboto
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
  });

  testWidgets("Home page shows categories with apps", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final applicationsCategory = fakeCategory(name: "Applications", order: 1);
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(favoritesCategory, [
        fakeApp(
          packageName: "me.efesser.flauncher.1",
          name: "FLauncher 1",
          version: "1.0.0",
        )
      ]),
      CategoryWithApps(applicationsCategory, [
        fakeApp(
          packageName: "me.efesser.flauncher.2",
          name: "FLauncher 2",
          version: "2.0.0",
        )
      ]),
    ]);

    await _pumpWidgetWith(tester, appsService);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text("Applications"), findsOneWidget);
    expect(find.byType(SliverGrid), findsOneWidget);
    expect(findAppCard("me.efesser.flauncher.2"), findsOneWidget);
    expect(findAppCard("me.efesser.flauncher.1"), findsOneWidget);
  });

  testWidgets("Dock shows every favorite when there are more than six", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final favorites = List.generate(
      8,
      (i) => fakeApp(packageName: "me.efesser.flauncher.$i", name: "FLauncher $i", version: "1.0.0"),
    );
    when(appsService.categoriesWithApps).thenReturn([CategoryWithApps(favoritesCategory, favorites)]);

    await _pumpWidgetWith(tester, appsService);
    await tester.pumpAndSettle();

    for (final app in favorites) {
      expect(findAppCard(app.packageName), findsOneWidget);
    }
  });

  testWidgets("The dock band spans the screen width and ends 24 dp above the bottom edge", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final favorites = List.generate(
      8,
      (i) => fakeApp(packageName: "me.efesser.flauncher.$i", name: "FLauncher $i", version: "1.0.0"),
    );
    when(appsService.categoriesWithApps).thenReturn([CategoryWithApps(favoritesCategory, favorites)]);

    await _pumpWidgetWith(tester, appsService);
    await tester.pumpAndSettle();

    final screenWidth = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final band = find.byKey(const Key("dock_band"));
    expect(tester.getTopLeft(band).dx, 0);
    expect(tester.getTopRight(band).dx, screenWidth);
    expect(tester.getBottomLeft(band).dy, moreOrLessEquals(screenHeight - 24, epsilon: 1.5));
  });

  testWidgets("Band tiles are identical, named, and the screen edges cut a half tile at each end", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final favorites = List.generate(
      8,
      (i) => fakeApp(packageName: "me.efesser.flauncher.$i", name: "FLauncher $i", version: "1.0.0"),
    );
    when(appsService.categoriesWithApps).thenReturn([CategoryWithApps(favoritesCategory, favorites)]);

    await _pumpWidgetWith(tester, appsService);
    await tester.pumpAndSettle();

    final screenWidth = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final geometry = BandGeometry(screenWidth, favorites.length);
    for (final (i, app) in favorites.indexed) {
      final card = findAppCard(app.packageName);
      expect(tester.getSize(card), Size(geometry.boxWidth, kBandHeight), reason: app.packageName);
      expect(tester.getTopLeft(card).dx, moreOrLessEquals(geometry.slotLeft(i + 1)), reason: app.packageName);
      expect(tester.widget<Text>(find.byKey(Key("band_label_${app.packageName}"))).data, app.name);
    }
    // Half tiles, no app repeated: one starts left of the screen, the other ends right of it.
    final left = tester.getRect(find.byKey(const Key("dock_band_edge_0")));
    final right = tester.getRect(find.byKey(Key("dock_band_edge_${favorites.length + 1}")));
    expect(left.left, lessThan(0));
    expect(left.right, greaterThan(0));
    expect(right.left, lessThan(screenWidth));
    expect(right.right, greaterThan(screenWidth));
    expect(geometry.slant, moreOrLessEquals(kBandTileHeight * tan(10 * pi / 180)));
  });

  testWidgets("The band ends with an All apps tile, sized like the app tiles, when apps are listed below it", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final applicationsCategory = fakeCategory(name: "Applications", order: 1);
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(favoritesCategory, [fakeApp(packageName: "me.efesser.dock")]),
      CategoryWithApps(applicationsCategory, [fakeApp(packageName: "me.efesser.grid")]),
    ]);

    await _pumpWidgetWith(tester, appsService);
    await tester.pumpAndSettle();

    final screenWidth = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final geometry = BandGeometry(screenWidth, 2);
    final tile = find.byType(DockAllAppsTile);
    expect(tile, findsOneWidget);
    expect(tester.getSize(tile), tester.getSize(findAppCard("me.efesser.dock")));
    expect(tester.getTopLeft(tile).dx, moreOrLessEquals(geometry.slotLeft(2)));
    expect(tester.getTopLeft(findAppCard("me.efesser.dock")).dx, moreOrLessEquals(geometry.slotLeft(1)));
  });

  testWidgets("Dock has no All apps tile when nothing is listed below it", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(favoritesCategory, [fakeApp(packageName: "me.efesser.dock")]),
    ]);

    await _pumpWidgetWith(tester, appsService);
    await tester.pumpAndSettle();

    expect(find.byType(DockAllAppsTile), findsNothing);
  });

  testWidgets("All apps moves focus to the first app below the dock, and Back returns to it", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final applicationsCategory = fakeCategory(name: "Applications", order: 1);
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(favoritesCategory, [fakeApp(packageName: "me.efesser.dock")]),
      CategoryWithApps(applicationsCategory, [
        fakeApp(packageName: "me.efesser.grid1"),
        fakeApp(packageName: "me.efesser.grid2"),
      ]),
    ]);

    await _pumpWidgetWith(tester, appsService);
    await tester.pumpAndSettle();
    expect(isAppCardFocused(tester, "me.efesser.dock"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final allAppsElement = tester.element(find.byType(DockAllAppsTile));
    bool allAppsFocused() => tester.widget<DockAllAppsTile>(find.byType(DockAllAppsTile)).focusNode!.hasPrimaryFocus;
    expect(allAppsFocused(), isTrue);

    // The focused grid tile pulses forever, so step time instead of settling.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(isAppCardFocused(tester, "me.efesser.grid1"), isTrue);
    final launcherState = Provider.of<LauncherState>(allAppsElement, listen: false);
    expect(launcherState.appGridFocused, isTrue);

    launcherState.handleBackNavigation(allAppsElement);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(allAppsFocused(), isTrue);
    expect(launcherState.appGridFocused, isFalse);
    expect(tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!.offset, 0);
  });

  testWidgets("The band names its tiles under them; the grid keeps its own name labels", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final applicationsCategory = fakeCategory(name: "Applications", order: 1);
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(favoritesCategory, [fakeApp(packageName: "me.efesser.dock", name: "Dock app")]),
      CategoryWithApps(applicationsCategory, [fakeApp(packageName: "me.efesser.grid", name: "Grid app")]),
    ]);

    await _pumpWidgetWith(tester, appsService);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    Finder nameLabel(String packageName) => find.descendant(
      of: findAppCard(packageName),
      matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_AppNameLabel'),
    );
    expect(nameLabel("me.efesser.dock"), findsNothing);
    expect(find.byKey(const Key("band_label_me.efesser.dock")), findsOneWidget);
    expect(nameLabel("me.efesser.grid"), findsOneWidget);
  });

  testWidgets("The focused band tile is larger and at full strength; the others are muted", (tester) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    final appsService = mkAppService();
    final settingsService = mkSettingsService();
    when(settingsService.showFocusBorders).thenReturn(true);
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(favoritesCategory, [
        fakeApp(packageName: "me.efesser.one", name: "One"),
        fakeApp(packageName: "me.efesser.two", name: "Two"),
      ]),
    ]);

    await _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, settingsService);
    await tester.pumpAndSettle();
    expect(isAppCardFocused(tester, "me.efesser.one"), isTrue);

    bool full(String packageName) => tester
        .widget<BandTileFace>(find.descendant(of: findAppCard(packageName), matching: find.byType(BandTileFace)))
        .focused;
    double tileScale(String packageName) => tester
        .widget<AnimatedScale>(find.descendant(of: findAppCard(packageName), matching: find.byType(AnimatedScale)).first)
        .scale;
    FontWeight? labelWeight(String packageName) =>
        tester.widget<Text>(find.byKey(Key("band_label_$packageName"))).style!.fontWeight;

    expect(full("me.efesser.one"), isTrue);
    expect(tileScale("me.efesser.one"), kBandFocusedScale);
    expect(labelWeight("me.efesser.one"), FontWeight.w500);
    expect(full("me.efesser.two"), isFalse);
    expect(tileScale("me.efesser.two"), 1);
    expect(labelWeight("me.efesser.two"), FontWeight.w400);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(full("me.efesser.one"), isFalse);
    expect(full("me.efesser.two"), isTrue);
    expect(tileScale("me.efesser.two"), kBandFocusedScale);
  });

  testWidgets("Right from the last band tile goes to the first, Left from the first to the last", (tester) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(favoritesCategory, [
        fakeApp(packageName: "me.efesser.one", name: "One"),
        fakeApp(packageName: "me.efesser.two", name: "Two"),
        fakeApp(packageName: "me.efesser.three", name: "Three"),
      ]),
    ]);

    await _pumpWidgetWith(tester, appsService);
    await tester.pumpAndSettle();
    expect(isAppCardFocused(tester, "me.efesser.one"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(isAppCardFocused(tester, "me.efesser.three"), isTrue, reason: 'Left from the first');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(isAppCardFocused(tester, "me.efesser.one"), isTrue, reason: 'Right from the last');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(isAppCardFocused(tester, "me.efesser.two"), isTrue, reason: 'an ordinary step');
  });

  testWidgets("The grid's first heading stays below the screen edge until the grid is focused", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final applicationsCategory = fakeCategory(name: "Applications", order: 1);
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(favoritesCategory, [fakeApp(packageName: "me.efesser.dock")]),
      CategoryWithApps(applicationsCategory, [fakeApp(packageName: "me.efesser.grid")]),
    ]);

    await _pumpWidgetWith(tester, appsService);
    await tester.pumpAndSettle();

    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(tester.getBottomLeft(find.byKey(const Key("dock_band"))).dy, moreOrLessEquals(screenHeight - 24, epsilon: 1.5));
    expect(tester.getTopLeft(find.text("Applications", skipOffstage: false)).dy, greaterThanOrEqualTo(screenHeight - 0.5));
  });

  testWidgets("The dock band is flat: no blur behind it", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(favoritesCategory, [fakeApp(packageName: "me.efesser.flauncher.1")]),
    ]);

    await _pumpWidgetWith(tester, appsService);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key("dock_band")), findsOneWidget);
    expect(find.byType(CachedBlurBackdrop), findsNothing);
    expect(find.ancestor(of: find.byType(DockBand), matching: find.byType(BackdropFilter)), findsNothing);
  });

  testWidgets("Top bar shows shortcuts for installed apps and launches them", (tester) async {
    final appsService = mkAppService();
    final browser = fakeApp(packageName: "com.tcl.browser", name: "Browser", version: "1.0.0");
    final playStore = fakeApp(packageName: "com.android.vending", name: "Play Store", version: "1.0.0");
    when(appsService.categoriesWithApps).thenReturn([]);
    when(appsService.getApplication("com.tcl.browser")).thenReturn(browser);
    when(appsService.getApplication("com.android.vending")).thenReturn(playStore);

    await _pumpWidgetWith(tester, appsService);
    await tester.pump();

    expect(find.byKey(const Key("top_bar_shortcut_com.tcl.browser")), findsOneWidget);
    expect(find.byKey(const Key("top_bar_shortcut_org.videolan.vlc")), findsNothing);
    // The Play Store shows its own icon in grayscale; the browser is a globe glyph.
    expect(_grayscaleAppIcon("com.android.vending"), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key("top_bar_shortcut_com.android.vending")), matching: find.byIcon(Icons.shop_outlined)),
      findsNothing,
    );
    verify(appsService.getAppIcon("com.android.vending"));
    expect(
      find.descendant(of: find.byKey(const Key("top_bar_shortcut_com.tcl.browser")), matching: find.byIcon(Icons.public)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key("top_bar_shortcut_com.tcl.browser")));
    await tester.pump();
    verify(appsService.launchApp(browser));
  });

  testWidgets("A band tile shows a plain fill until its art is in, then the art", (tester) async {
    final appsService = mkAppService();
    final mock = appsService as MockAppsService;
    // No banner, so the tile loads the icon; the icon arrives when the test says so.
    when(mock.getAppBanner(any)).thenAnswer((_) async => Uint8List(0));
    final icon = Completer<Uint8List>();
    final png = await mkAppService().getAppIcon("any");
    when(mock.getAppIcon(any)).thenAnswer((_) => icon.future);
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final app = fakeApp(packageName: "me.efesser.flauncher", name: "FLauncher", version: "1.0.0");
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(favoritesCategory, [app]),
    ]);
    await _pumpWidgetWith(tester, appsService);
    BandTilePainter painter() => tester
        .widget<CustomPaint>(find.descendant(
          of: findAppCard(app.packageName),
          matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BandTilePainter),
        ))
        .painter! as BandTilePainter;

    await tester.pump(const Duration(seconds: 5));
    expect(painter().image, isNull, reason: 'no icon yet');
    expect(painter().edgeColour, kBandPlainTileColor);

    icon.complete(png);
    for (var i = 0; i < 50 && painter().image == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(painter().image, isNotNull);
  });

  testWidgets("The dock stays on the bottom edge in the frame the Watch Next hero appears", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final favorites = List.generate(
      5,
      (i) => fakeApp(packageName: "me.efesser.flauncher.$i", name: "FLauncher $i", version: "1.0.0"),
    );
    when(appsService.categoriesWithApps).thenReturn([CategoryWithApps(favoritesCategory, favorites)]);
    final settingsService = mkSettingsService();
    when(settingsService.showWatchNextSection).thenReturn(true);
    when(settingsService.watchNextBigPictureMode).thenReturn(true);
    // Permission granted, items not loaded yet: what the home screen shows first after a cold start.
    final watchNextService = mkWatchNextService();
    when(watchNextService.hasPermission).thenReturn(true);

    await _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, settingsService, watchNextService);
    await tester.pumpAndSettle();
    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final tray = find.byKey(const Key("dock_band"));
    expect(tester.getBottomLeft(tray).dy, moreOrLessEquals(screenHeight - 24, epsilon: 1.5));

    // The items arrive.
    final item = WatchNextItem(id: 1, title: "The Office", posterUri: "content://poster/1");
    when(watchNextService.items).thenReturn([item]);
    when(watchNextService.hasItems).thenReturn(true);
    when(watchNextService.hasVisibleSection).thenReturn(true);
    when(watchNextService.activeHeroItem).thenReturn(item);
    tester.element(find.byType(FLauncher)).markNeedsBuild();
    await tester.pump();

    expect(find.text("The Office"), findsWidgets, reason: 'the hero is on screen in this frame');
    expect(tester.getBottomLeft(tray).dy, moreOrLessEquals(screenHeight - 24, epsilon: 1.5));
  });

  testWidgets("The hero follows the dock tile that focus rests on, not every tile it passes", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final favorites = [
      fakeApp(packageName: "com.playstation.hdmi", name: "PS5", version: "1.0.0"),
      fakeApp(packageName: "com.netflix.ninja", name: "Netflix", version: "1.0.0"),
      fakeApp(packageName: "com.google.android.youtube.tv", name: "YouTube", version: "1.0.0"),
    ];
    when(appsService.categoriesWithApps).thenReturn([CategoryWithApps(favoritesCategory, favorites)]);
    final watchNextService = mkWatchNextService();

    await _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, mkSettingsService(), watchNextService);
    await tester.pumpAndSettle();
    await tester.pump(kDockHeroFollowDelay * 2);
    clearInteractions(watchNextService);

    // Across Netflix to YouTube, faster than the delay.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(kDockHeroFollowDelay - const Duration(milliseconds: 50));
    verifyNever(watchNextService.showFirstItemFor("com.google.android.youtube.tv"));

    await tester.pump(const Duration(milliseconds: 100));
    verify(watchNextService.showFirstItemFor("com.google.android.youtube.tv")).called(1);
    verifyNever(watchNextService.showFirstItemFor("com.netflix.ninja"));
  });

  testWidgets("Dock tiles decode their picture at the size they are shown, grid tiles at 480 px", (tester) async {
    final appsService = mkAppService();
    when((appsService as MockAppsService).getAppBanner(any)).thenAnswer((_) async => Uint8List(0));
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final applicationsCategory = fakeCategory(name: "Applications", order: 1);
    final docked = fakeApp(packageName: "me.efesser.flauncher.1", name: "FLauncher 1", version: "1.0.0");
    final gridApp = fakeApp(packageName: "me.efesser.flauncher.2", name: "FLauncher 2", version: "2.0.0");
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(favoritesCategory, [docked]),
      CategoryWithApps(applicationsCategory, [gridApp]),
    ]);
    await _pumpWidgetWith(tester, appsService);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pumpAndSettle();

    int? decodeWidth(String packageName) {
      final ink = tester.widget<Ink>(find.descendant(of: findAppCard(packageName), matching: find.byType(Ink)).first);
      return ((ink.decoration! as BoxDecoration).image!.image as ResizeImage).width;
    }
    final bandImage = tester
        .widget<BandTileFace>(find.descendant(of: findAppCard(docked.packageName), matching: find.byType(BandTileFace)))
        .image;

    expect((bandImage! as ResizeImage).width, (82 * 1.14 * tester.view.devicePixelRatio).ceil());
    expect(decodeWidth(gridApp.packageName), 480);
  });

  testWidgets("A backdrop prepared for an item that is never shown is released", (tester) async {
    var openImages = 0;
    final previousOnCreate = ui.Image.onCreate;
    final previousOnDispose = ui.Image.onDispose;
    ui.Image.onCreate = (_) => openImages++;
    ui.Image.onDispose = (_) => openImages--;
    addTearDown(() {
      ui.Image.onCreate = previousOnCreate;
      ui.Image.onDispose = previousOnDispose;
    });

    final settingsService = mkSettingsService();
    when(settingsService.showWatchNextSection).thenReturn(true);
    when(settingsService.watchNextBigPictureMode).thenReturn(true);
    final first = WatchNextItem(id: 1, title: "The Office", posterUri: "content://poster/1");
    final second = WatchNextItem(id: 2, title: "Nihce", posterUri: "content://poster/2");
    final third = WatchNextItem(id: 3, title: "Ted Lasso", posterUri: "content://poster/3");
    final posters = {for (final item in [first, second, third]) item.posterUri!: _onePixelPng()};
    var shown = first;
    final watchNextService = mkWatchNextService();
    when(watchNextService.activeHeroItem).thenAnswer((_) => shown);
    when(watchNextService.getPosterUriForItem(any))
        .thenAnswer((invocation) => (invocation.positionalArguments.single as WatchNextItem?)?.posterUri);
    when(watchNextService.getCachedPoster(any))
        .thenAnswer((invocation) => posters[invocation.positionalArguments.single]);

    await _pumpWidgetWithProviders(tester, mkWallpaperService(), mkAppService(), settingsService, watchNextService);
    final gate = verify(watchNextService.heroSwitchGate = captureAny).captured.single as Future<void> Function(WatchNextItem);
    final heroBackdrop = find.descendant(of: find.byKey(const ValueKey('hero_bg')), matching: find.byType(RawImage));

    ui.Image? shownImage;
    Future<void> showAndSettle(WatchNextItem item) async {
      final before = shownImage;
      shown = item;
      tester.element(find.byType(FLauncher)).markNeedsBuild();
      await tester.pump();
      // Until this item's picture is the only one on screen.
      for (var i = 0; i < 100; i++) {
        final images = tester.widgetList<RawImage>(heroBackdrop).map((raw) => raw.image).toList();
        if (images.length == 1 && images.single != null && !identical(images.single, before)) {
          shownImage = images.single;
          break;
        }
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(shownImage, isNot(same(before)), reason: '${item.title} is on screen');
      // The switch and the delayed release of the old textures.
      await tester.pump(kHeroCarouselDuration);
      await tester.pump(const Duration(seconds: 2));
    }

    await showAndSettle(first);
    final steady = openImages;

    // The next item is baked ahead, but the hero moves to another one instead.
    await tester.runAsync(() => gate(second));
    await showAndSettle(third);

    expect(openImages, steady, reason: 'one item shown again, nothing kept for the item that was skipped');
  });

  testWidgets("A prepared hero backdrop starts its transition in the frame the hero item changes", (tester) async {
    final settingsService = mkSettingsService();
    when(settingsService.showWatchNextSection).thenReturn(true);
    when(settingsService.watchNextBigPictureMode).thenReturn(true);
    final first = WatchNextItem(id: 1, title: "The Office", posterUri: "content://poster/1");
    final second = WatchNextItem(id: 2, title: "Nihce", posterUri: "content://poster/2");
    // Two separate buffers: the backdrop is keyed on the bytes' identity.
    final posters = {"content://poster/1": _onePixelPng(), "content://poster/2": _onePixelPng()};
    var shown = first;
    final watchNextService = mkWatchNextService();
    when(watchNextService.activeHeroItem).thenAnswer((_) => shown);
    when(watchNextService.getPosterUriForItem(any))
        .thenAnswer((invocation) => (invocation.positionalArguments.single as WatchNextItem?)?.posterUri);
    when(watchNextService.getCachedPoster(any))
        .thenAnswer((invocation) => posters[invocation.positionalArguments.single]);

    await _pumpWidgetWithProviders(tester, mkWallpaperService(), mkAppService(), settingsService, watchNextService);
    final gate = verify(watchNextService.heroSwitchGate = captureAny).captured.single as Future<void> Function(WatchNextItem);

    // The first backdrop bakes on its own.
    final heroBackdrop = find.descendant(of: find.byKey(const ValueKey('hero_bg')), matching: find.byType(RawImage));
    for (var i = 0; i < 20 && heroBackdrop.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(heroBackdrop, findsOneWidget);
    await tester.pump(kHeroCarouselDuration);
    final firstImage = tester.widget<RawImage>(heroBackdrop).image;

    // The service waits for the gate, then shows the next item.
    await tester.runAsync(() => gate(second));
    shown = second;
    tester.element(find.byType(FLauncher)).markNeedsBuild();
    await tester.pump();

    // Old picture leaving and new picture arriving, from the very first frame of the change.
    final images = tester.widgetList<RawImage>(heroBackdrop).map((raw) => raw.image).toList();
    expect(images, hasLength(2));
    expect(images.where((image) => image != firstImage), hasLength(1));

    // While the pictures slide, the leaving and the arriving one are both zoomed to keep covering
    // the screen, so neither uncovers a band at the side.
    await tester.pump(const Duration(milliseconds: 300));
    final zooms = find.descendant(of: find.byKey(const ValueKey('hero_bg')), matching: find.byType(ScaleTransition));
    expect(tester.widgetList<ScaleTransition>(zooms).map((zoom) => zoom.scale.value), [
      for (var i = 0; i < 2; i++) greaterThan(1),
    ]);
    expect(find.descendant(of: find.byKey(const ValueKey('hero_bg')), matching: find.byType(ShaderMask)), findsNothing);

    // The old picture is released a second after it leaves.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets("Router HDD shortcut shows an outline cone in the top bar glyph style", (tester) async {
    final appsService = mkAppService();
    final vlc = fakeApp(packageName: "org.videolan.vlc", name: "VLC", version: "1.0.0");
    when(appsService.categoriesWithApps).thenReturn([]);
    when(appsService.getApplication("org.videolan.vlc")).thenReturn(vlc);

    await _pumpWidgetWith(tester, appsService);
    await tester.pump();

    final shortcut = find.byKey(const Key("top_bar_shortcut_org.videolan.vlc"));
    final cone = find.descendant(of: shortcut, matching: find.byType(VlcConeIcon));
    expect(cone, findsOneWidget);
    expect(tester.widget<VlcConeIcon>(cone).color, const Color(0xCCFFFFFF));
    // Same box as the settings and globe glyphs, and drawn, not a picture.
    expect(tester.getSize(cone), const Size(18, 18));
    expect(find.descendant(of: shortcut, matching: find.byType(Image)), findsNothing);
    verifyNever(appsService.getAppIcon("org.videolan.vlc"));

    await tester.tap(shortcut);
    await tester.pump();
    verify(appsService.launchApp(vlc));
  });

  testWidgets("Browser shortcut prefers TV Bro over the TCL browser", (tester) async {
    final appsService = mkAppService();
    final tvBro = fakeApp(packageName: "com.phlox.tvwebbrowser", name: "TV Bro", version: "1.0.0");
    final tclBrowser = fakeApp(packageName: "com.tcl.browser", name: "Browser", version: "1.0.0");
    when(appsService.categoriesWithApps).thenReturn([]);
    when(appsService.getApplication("com.phlox.tvwebbrowser")).thenReturn(tvBro);
    when(appsService.getApplication("com.tcl.browser")).thenReturn(tclBrowser);

    await _pumpWidgetWith(tester, appsService);
    await tester.pump();

    expect(find.byKey(const Key("top_bar_shortcut_com.phlox.tvwebbrowser")), findsOneWidget);
    expect(find.byKey(const Key("top_bar_shortcut_com.tcl.browser")), findsNothing);
  });

  testWidgets("Home page shows category empty-state", (tester) async {
    final appsService = mkAppService();
    when(appsService.categoriesWithApps).thenReturn([]);

    await _pumpWidgetWith(tester, appsService);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text("Loading"), findsOneWidget);
  });

  testWidgets("Home page displays background image", (tester) async {
    final appsService = mkAppService();
    when(appsService.categoriesWithApps).thenReturn([]);

    await _pumpWidgetWith(tester, appsService);

    expect(find.byType(Image), findsWidgets);
  });

  testWidgets("Home page displays background gradient", (tester) async {
    final appsService = mkAppService();
    when(appsService.categoriesWithApps).thenReturn([]);

    await _pumpWidgetWithProviders(tester, mkWallpaperService(false), appsService, mkSettingsService());

    expect(find.byKey(Key("background")), findsOneWidget);
  });

  testWidgets("Wallpaper gets the top and bottom scrims", (tester) async {
    final appsService = mkAppService();
    when(appsService.categoriesWithApps).thenReturn([]);

    await _pumpWidgetWith(tester, appsService);

    expect(find.byKey(const Key("wallpaper_scrim")), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key("wallpaper_scrim"))), tester.view.physicalSize / tester.view.devicePixelRatio);
  });

  testWidgets("Home dims its UI and darkens the backdrop after three minutes without a key", (tester) async {
    final appsService = mkAppService();
    when(appsService.categoriesWithApps).thenReturn([]);

    await _pumpWidgetWith(tester, appsService);
    double opacity(String key) => tester.widget<AnimatedOpacity>(find.byKey(Key(key))).opacity;
    expect(opacity("home_idle_foreground"), 1);
    expect(opacity("home_idle_backdrop_dim"), 0);

    await tester.pump(kHomeIdleTimeout + const Duration(milliseconds: 100));
    expect(opacity("home_idle_foreground"), 0);
    expect(opacity("home_idle_backdrop_dim"), kHomeIdleBackdropDim);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(opacity("home_idle_foreground"), 1);
    expect(opacity("home_idle_backdrop_dim"), 0);
  });

  testWidgets("Default build credits the Unsplash photographer", (tester) async {
    final appsService = mkAppService();
    when(appsService.categoriesWithApps).thenReturn([]);
    final wallpaperService = mkWallpaperService();
    when(wallpaperService.slideshowAuthor).thenReturn("Jane Doe");

    await _pumpWidgetWithProviders(tester, wallpaperService, appsService, mkSettingsService());

    // Only builds made with HIDE_UNSPLASH_CREDIT=true leave the credit out.
    expect(kHideUnsplashCredit, isFalse);
    expect(find.text("Photo: Jane Doe / Unsplash"), findsOneWidget);
  });

  testWidgets("Home page builds the blur layer when background blur is enabled", (tester) async {
    final appsService = mkAppService();
    when(appsService.categoriesWithApps).thenReturn([]);

    await _pumpWidgetWith(tester, appsService);

    expect(find.byType(CachedBlurLayer), findsOneWidget);
  });

  testWidgets("Home page does not build the blur layer when background blur is disabled", (tester) async {
    final appsService = mkAppService();
    when(appsService.categoriesWithApps).thenReturn([]);
    final settingsService = mkSettingsService();
    when(settingsService.backgroundBlurDisabled).thenReturn(true);

    await _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, settingsService);

    expect(find.byType(CachedBlurLayer), findsNothing);
  });

  testWidgets("Pressing select on settings icon opens SettingsPanel", (tester) async {
    final appsService = mkAppService();
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(fakeCategory(name: "Favorites", order: 0), []),
      CategoryWithApps(fakeCategory(name: "Applications", order: 1), []),
    ]);
    await _pumpWidgetWith(tester, appsService);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPanel), findsOneWidget);
  });

  testWidgets("HOME closes an open SettingsPanel and returns the page to the top", (tester) async {
    final appsService = mkAppService();
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(fakeCategory(name: "Favorites", order: 0), []),
      CategoryWithApps(fakeCategory(name: "Applications", order: 1), []),
    ]);
    await _pumpWidgetWith(tester, appsService);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPanel), findsOneWidget);

    final reply = Completer<ByteData?>();
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'me.efesser.flauncher/method',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('homePressed')),
      reply.complete,
    );
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPanel), findsNothing);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.pixels, scrollable.position.minScrollExtent);
  });

  testWidgets("Pressing select on app launches app", (tester) async {
    final appsService = mkAppService();
    final app = fakeApp(
      packageName: "me.efesser.flauncher",
      name: "FLauncher",
      version: "1.0.0",
    );
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(fakeCategory(name: "Favorites", order: 0), [app]),
    ]);
    await _pumpWidgetWith(tester, appsService);

    await tester.tap(findAppCard("me.efesser.flauncher"));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 550));

    verify(appsService.launchApp(app));
  });

  testWidgets("Pressing select launches the app without waiting for the press animation", (tester) async {
    final appsService = mkAppService();
    final app = fakeApp(packageName: "me.efesser.flauncher", name: "FLauncher", version: "1.0.0");
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(fakeCategory(name: "Favorites", order: 0), [app]),
    ]);
    await _pumpWidgetWith(tester, appsService);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    verify(appsService.launchApp(app));

    // Let the reset timer finish so the test ends with no pending timers.
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets("Long pressing on app opens ApplicationInfoPanel", (tester) async {
    final appsService = mkAppService();
    final app = fakeApp(
      packageName: "me.efesser.flauncher",
      name: "FLauncher",
      version: "1.0.0",
    );
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(fakeCategory(name: "Favorites", order: 0), [app]),
    ]);
    await _pumpWidgetWith(tester, appsService);

    await tester.longPress(findAppCard("me.efesser.flauncher"));
    await tester.pumpAndSettle();

    expect(find.byType(ApplicationInfoPanel), findsOneWidget);
  });

  testWidgets("AppCard moves in grid", (tester) async {
    final appsService = mkAppService();
    final applicationsCategory = fakeCategory(name: "Applications", order: 0, type: CategoryType.grid);
    final categoryWithApps = CategoryWithApps(applicationsCategory, [
      fakeApp(
        packageName: "me.efesser.flauncher",
        name: "FLauncher",
        version: "1.0.0",
      ),
      fakeApp(
        packageName: "me.efesser.flauncher.2",
        name: "FLauncher 2",
        version: "1.0.0",
      )
    ]);
    when(appsService.categoriesWithApps).thenReturn([categoryWithApps]);
    await _pumpWidgetWith(tester, appsService);

    await tester.longPress(findAppCard("me.efesser.flauncher"));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Reorder"));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    verify(appsService.reorderApplication(categoryWithApps, 0, 1));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    verify(appsService.saveApplicationOrderInCategory(categoryWithApps));
  });

  testWidgets("AppCard moves in row", (tester) async {
    final appsService = mkAppService();
    final applicationsCategory = fakeCategory(name: "Applications", order: 0, type: CategoryType.row);
    final categoryWithApps = CategoryWithApps(applicationsCategory, [
      fakeApp(
        packageName: "me.efesser.flauncher",
        name: "FLauncher",
        version: "1.0.0",
      ),
      fakeApp(
        packageName: "me.efesser.flauncher.2",
        name: "FLauncher 2",
        version: "1.0.0",
      )
    ]);
    when(appsService.categoriesWithApps).thenReturn([categoryWithApps]);
    await _pumpWidgetWith(tester, appsService);

    await tester.longPress(findAppCard("me.efesser.flauncher"));
    await tester.pumpAndSettle();

    await tester.tap(find.text("Reorder"));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    verify(appsService.reorderApplication(categoryWithApps, 0, 1));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    verify(appsService.saveApplicationOrderInCategory(categoryWithApps));
  });

  testWidgets("Moving down does not skip row", (tester) async {
    // given
    final appsService = mkAppService();

    /*
     * we are creating 3 rows like the following:
     * ▭ ▭ ▭
     * ▭ ▭
     * ▭ ▭ ▭
     */
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(fakeCategory(name: "tv", order: 0), [
        fakeApp(
          packageName: "me.efesser.tv1",
          name: "tv 1",
          version: "1.0.0",
        ),
        fakeApp(
          packageName: "me.efesser.tv2",
          name: "tv 2",
          version: "1.0.0",
        ),
        fakeApp(
          packageName: "me.efesser.tv3",
          name: "tv 3",
          version: "1.0.0",
        )
      ]),
      CategoryWithApps(fakeCategory(name: "music", order: 1), [
        fakeApp(
          packageName: "me.efesser.music1",
          name: "music 1",
          version: "1.0.0",
        ),
        fakeApp(
          packageName: "me.efesser.music2",
          name: "music 2",
          version: "1.0.0",
        )
      ]),
      CategoryWithApps(fakeCategory(name: "games", order: 2), [
        fakeApp(
          packageName: "me.efesser.game1",
          name: "game 1",
          version: "1.0.0",
        ),
        fakeApp(
          packageName: "me.efesser.game2",
          name: "game 2",
          version: "1.0.0",
        ),
        fakeApp(
          packageName: "me.efesser.game3",
          name: "game 3",
          version: "1.0.0",
        )
      ]),
    ]);

    await _pumpWidgetWith(tester, appsService);
    // when
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    // then
    expect(isAppCardFocused(tester, "me.efesser.tv1"), isFalse);
    expect(isAppCardFocused(tester, "me.efesser.music2"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(isAppCardFocused(tester, "me.efesser.tv1"), isFalse);
    expect(isAppCardFocused(tester, "me.efesser.music2"), isFalse);
    expect(isAppCardFocused(tester, "me.efesser.game2"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(isAppCardFocused(tester, "me.efesser.tv1"), isFalse);
    expect(isAppCardFocused(tester, "me.efesser.music2"), isTrue);
    expect(isAppCardFocused(tester, "me.efesser.game2"), isFalse);
  });

  testWidgets("Moving left or right stays on the same row", (tester) async {
    // given
    final appsService = mkAppService();

    /*
     * we are creating 2 rows like the following:
     * ▭ ▭
     * ▭ ▭ ▭ ▭ ▭
     */
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(fakeCategory(name: "tv", order: 0), [
        fakeApp(
          packageName: "me.efesser.tv1",
          name: "tv 1",
          version: "1.0.0",
        ),
        fakeApp(
          packageName: "me.efesser.tv2",
          name: "tv 2",
          version: "1.0.0",
        ),
      ]),
      CategoryWithApps(fakeCategory(name: "music", order: 1, columnsCount: 5), [
        fakeApp(
          packageName: "me.efesser.music1",
          name: "music 1",
          version: "1.0.0",
        ),
        fakeApp(
          packageName: "me.efesser.music2",
          name: "music 2",
          version: "1.0.0",
        ),
        fakeApp(
          packageName: "me.efesser.music3",
          name: "music 3",
          version: "1.0.0",
        ),
        fakeApp(
          packageName: "me.efesser.music4",
          name: "music 4",
          version: "1.0.0",
        ),
        fakeApp(
          packageName: "me.efesser.music5",
          name: "music 5",
          version: "1.0.0",
        ),
      ]),
    ]);

    await _pumpWidgetWith(tester, appsService);

    // then
    expect(isAppCardFocused(tester, "me.efesser.tv1"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(isAppCardFocused(tester, "me.efesser.tv1"), isFalse);
    expect(isAppCardFocused(tester, "me.efesser.music1"), isTrue);

    // check right direction
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(isAppCardFocused(tester, "me.efesser.tv1"), isFalse);
    expect(isAppCardFocused(tester, "me.efesser.music1"), isFalse);
    expect(isAppCardFocused(tester, "me.efesser.music2"), isTrue);

    // check if right on the last app stays on the same app
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(isAppCardFocused(tester, "me.efesser.music5"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(isAppCardFocused(tester, "me.efesser.tv2"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(isAppCardFocused(tester, "me.efesser.music2"), isTrue);

    // check left direction
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(isAppCardFocused(tester, "me.efesser.music1"), isTrue);

    // check if going left on the first app stays on the same app
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(isAppCardFocused(tester, "me.efesser.music1"), isTrue);
  });

  testWidgets("Moving right or up can go the settings icon", (tester) async {
    // given
    final appsService = mkAppService();

    /*
     * we are creating 2 rows like the following:
     * ▭ ▭
     * ▭ ▭ ▭
     */
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(fakeCategory(name: "tv", order: 0), [
        fakeApp(
          packageName: "me.efesser.tv1",
          name: "tv 1",
          version: "1.0.0",
        ),
        fakeApp(
          packageName: "me.efesser.tv2",
          name: "tv 2",
          version: "1.0.0",
        ),
      ]),
      CategoryWithApps(fakeCategory(name: "music", order: 1), [
        fakeApp(
          packageName: "me.efesser.music1",
          name: "music 1",
          version: "1.0.0",
        ),
        fakeApp(
          packageName: "me.efesser.music2",
          name: "music 2",
          version: "1.0.0",
        ),
        fakeApp(
          packageName: "me.efesser.music3",
          name: "music 3",
          version: "1.0.0",
        ),
      ]),
    ]);

    await _pumpWidgetWith(tester, appsService);

    // then
    expect(isAppCardFocused(tester, "me.efesser.tv1"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(isAppCardFocused(tester, "me.efesser.tv1"), isFalse);
    expect(isSettingsIconFocused(tester), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(isSettingsIconFocused(tester), isFalse);
    expect(isAppCardFocused(tester, "me.efesser.tv1"), isTrue);
  });
}

SettingsService mkSettingsService() {
  final settingsService = MockSettingsService();
  when(settingsService.dateFormat).thenReturn(SettingsService.defaultDateFormat);
  when(settingsService.timeFormat).thenReturn(SettingsService.defaultTimeFormat);
  when(settingsService.appHighlightAnimationEnabled).thenReturn(true);
  when(settingsService.showAppNamesBelowIcons).thenReturn(true);
  when(settingsService.backgroundBlurDisabled).thenReturn(false);
  when(settingsService.showWatchNextSection).thenReturn(false);
  when(settingsService.watchNextBigPictureMode).thenReturn(false);
  when(settingsService.watchNextHideProgramsWithoutImages).thenReturn(false);
  when(settingsService.watchNextMaxItems).thenReturn(0);
  when(settingsService.watchNextExcludedPackages).thenReturn([]);
  when(settingsService.showCategoryTitles).thenReturn(true);
  when(settingsService.dockBackdropFilterDisabled).thenReturn(false);
  when(settingsService.dockDarkBackground).thenReturn(false);
  when(settingsService.dockShadowEnabled).thenReturn(false);
  when(settingsService.autoHideAppBarEnabled).thenReturn(false);
  when(settingsService.hideStatusBarInGrid).thenReturn(false);
  when(settingsService.showNetworkIndicatorInStatusBar).thenReturn(false);
  when(settingsService.showWifiWidgetInStatusBar).thenReturn(false);
  when(settingsService.showDateInStatusBar).thenReturn(false);
  when(settingsService.showTimeInStatusBar).thenReturn(false);
  when(settingsService.focusBorderThickness).thenReturn(3.0);
  when(settingsService.cardCornerRadius).thenReturn(CARD_CORNER_RADIUS_DEFAULT);
  when(settingsService.appNamesOnFocusOnly).thenReturn(false);
  when(settingsService.customAppLabel(any)).thenReturn(null);
  when(settingsService.screensaverClockStyle).thenReturn('minimal');
  when(settingsService.accentColorHex).thenReturn(ACCENT_COLOR_WHITE);
  return settingsService;
}

WatchNextService mkWatchNextService() {
  final watchNextService = MockWatchNextService();
  when(watchNextService.hasPermission).thenReturn(false);
  when(watchNextService.hasItems).thenReturn(false);
  when(watchNextService.hasVisibleSection).thenReturn(false);
  when(watchNextService.items).thenReturn([]);
  when(watchNextService.activeHeroItem).thenReturn(null);
  when(watchNextService.refreshPermissionAndItems()).thenAnswer((_) async {});
  return watchNextService;
}

WallpaperService mkWallpaperService([bool wallpaper = true]) {
  final wallpaperService = MockWallpaperService();
  when(wallpaperService.gradient).thenReturn(FLauncherGradients.greatWhale);
  when(wallpaperService.wallpaper).thenReturn(wallpaper ? Image.asset('assets/icon.png').image : null);
  when(wallpaperService.wallpaperVideoFile).thenReturn(null);
  when(wallpaperService.wallpaperRevision).thenReturn(0);
  when(wallpaperService.slideshowAuthor).thenReturn(null);
  when(wallpaperService.redditWallpaperCredit).thenReturn(null);
  return wallpaperService;
}

/// A valid 1×1 PNG in a new buffer each call.
Uint8List _onePixelPng() => Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
      0x42, 0x60, 0x82, //
    ]);

/// An app's launcher icon (from [AppsService.getAppIcon]) under the grayscale filter, inside the
/// top bar shortcut for [packageName].
Finder _grayscaleAppIcon(String packageName) => find.descendant(
      of: find.byKey(Key("top_bar_shortcut_$packageName")),
      matching: find.byWidgetPredicate((w) =>
          w is ColorFiltered &&
          w.colorFilter == kTopBarGrayscale &&
          w.child is Image &&
          (w.child as Image).image is MemoryImage),
    );

AppsService mkAppService() {
  final appsService = MockAppsService();
  when(appsService.initialized).thenReturn(true);
  when(appsService.layoutVersion).thenReturn(0);
  when(appsService.getAppIcon(any)).thenAnswer((_) => Future.value(Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
  ])));
  when(appsService.getAppBanner(any)).thenAnswer((_) => Future.value(null));
  when(appsService.hasCustomBanner(any)).thenAnswer((_) => Future.value(false));
  when(appsService.isAppInFavorites(any)).thenReturn(false);
  return appsService;
}


Future<void> _pumpWidgetWith(
  WidgetTester tester,
  AppsService appsService,
  ) async {
  return _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, mkSettingsService(), mkWatchNextService());
}

Future<void> _pumpWidgetWithProviders(
  WidgetTester tester,
  WallpaperService wallpaperService,
  AppsService appsService,
  SettingsService settingsService,
  [WatchNextService? watchNextService,]
) async {
  try {
    final cwa = appsService.categoriesWithApps;
    when(appsService.categories).thenReturn(cwa);
    when(appsService.launcherSections).thenReturn(cwa);
  } catch (_) {}

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<WallpaperService>.value(value: wallpaperService),
        ChangeNotifierProvider<AppsService>.value(value: appsService),
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<WatchNextService>.value(value: watchNextService ?? mkWatchNextService()),
        ChangeNotifierProvider(create: (_) => LauncherState()),
        ChangeNotifierProvider(create: (_) => NetworkService(FLauncherChannel())),
      ],
      builder: (_, __) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FLauncher(),
      ),
    ),
  );
  await tester.pump(Duration(seconds: 30), EnginePhase.sendSemanticsUpdate);
}
