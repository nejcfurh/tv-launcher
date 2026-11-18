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
import 'dart:typed_data';

import 'package:flauncher/build_flags.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/gradients.dart';
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
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flauncher/widgets/settings/settings_panel_page.dart';
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

  testWidgets("Dock sits at the bottom of the screen", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final favorites = List.generate(
      8,
      (i) => fakeApp(packageName: "me.efesser.flauncher.$i", name: "FLauncher $i", version: "1.0.0"),
    );
    when(appsService.categoriesWithApps).thenReturn([CategoryWithApps(favoritesCategory, favorites)]);

    await _pumpWidgetWith(tester, appsService);
    await tester.pumpAndSettle();

    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    // Bottom margin (34) + tray padding (16).
    expect(tester.getBottomLeft(find.byType(CategoryCleanRow)).dy, moreOrLessEquals(screenHeight - 50, epsilon: 1.5));
    expect(tester.getBottomLeft(find.byKey(const Key("dock_tray"))).dy, moreOrLessEquals(screenHeight - 34, epsilon: 1.5));
    expect(tester.getTopLeft(find.byKey(const Key("dock_tray"))).dx, 32);
  });

  testWidgets("Dock tiles are 82x42 and spread from keyline to keyline", (tester) async {
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
    final first = findAppCard(favorites.first.packageName);
    final last = findAppCard(favorites.last.packageName);
    expect(tester.getSize(first), const Size(82, 42));
    expect(tester.getTopLeft(first).dx, 48);
    expect(tester.getTopRight(last).dx, screenWidth - 48);
  });

  testWidgets("Dock hides app names even when names are on for the grid", (tester) async {
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
    expect(nameLabel("me.efesser.grid"), findsOneWidget);
  });

  testWidgets("Focused dock tile scales up and gets the white ring; others stay as they are", (tester) async {
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

    double ringOpacity(String packageName) => tester
        .widget<AnimatedOpacity>(find.descendant(of: findAppCard(packageName), matching: find.byKey(const Key("dock_focus_ring"))))
        .opacity;
    double tileScale(String packageName) => tester
        .widget<AnimatedScale>(find.descendant(of: findAppCard(packageName), matching: find.byType(AnimatedScale)).at(1))
        .scale;

    expect(ringOpacity("me.efesser.one"), 1);
    expect(tileScale("me.efesser.one"), 1.14);
    expect(ringOpacity("me.efesser.two"), 0);
    expect(tileScale("me.efesser.two"), 1);
    // Unfocused dock tiles are not dimmed.
    expect(
      find.descendant(of: findAppCard("me.efesser.two"), matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == const Color(0x1A000000))),
      findsNothing,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(ringOpacity("me.efesser.one"), 0);
    expect(ringOpacity("me.efesser.two"), 1);
  });

  testWidgets("Dock tray is flat: no blur behind it", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    when(appsService.categoriesWithApps).thenReturn([
      CategoryWithApps(favoritesCategory, [fakeApp(packageName: "me.efesser.flauncher.1")]),
    ]);

    await _pumpWidgetWith(tester, appsService);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key("dock_tray")), findsOneWidget);
    expect(find.byType(CachedBlurBackdrop), findsNothing);
    expect(find.ancestor(of: find.byType(CategoryCleanRow), matching: find.byType(BackdropFilter)), findsNothing);
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
    // Play Store shows its own icon; the browser shows a globe whichever browser is installed.
    expect(
      find.descendant(of: find.byKey(const Key("top_bar_shortcut_com.android.vending")), matching: find.byType(Image)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const Key("top_bar_shortcut_com.tcl.browser")), matching: find.byIcon(Icons.public)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key("top_bar_shortcut_com.tcl.browser")));
    await tester.pump();
    verify(appsService.launchApp(browser));
  });

  testWidgets("Router HDD shortcut shows the bare VLC cone", (tester) async {
    final appsService = mkAppService();
    final vlc = fakeApp(packageName: "org.videolan.vlc", name: "VLC", version: "1.0.0");
    when(appsService.categoriesWithApps).thenReturn([]);
    when(appsService.getApplication("org.videolan.vlc")).thenReturn(vlc);

    await _pumpWidgetWith(tester, appsService);
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key("top_bar_shortcut_org.videolan.vlc")),
        matching: find.byWidgetPredicate(
            (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == 'assets/vlc_cone.png'),
      ),
      findsOneWidget,
    );
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
