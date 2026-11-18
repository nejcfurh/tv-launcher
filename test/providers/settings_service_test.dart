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

//import 'dart:html';

import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/date_time_format_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

//import '../mocks.mocks.dart';

void main() async {
  SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
  final sharedPreferences = await SharedPreferences.getInstance();
  final settingsService = SettingsService(sharedPreferences);

  setUp(() async {
    await sharedPreferences.clear();
  });

  test("watchNextBigPictureMode default and update", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);

    expect(settingsService.watchNextBigPictureMode, isFalse);

    await settingsService.setWatchNextBigPictureMode(true);
    expect(settingsService.watchNextBigPictureMode, isTrue);

    await settingsService.setWatchNextBigPictureMode(false);
    expect(settingsService.watchNextBigPictureMode, isFalse);
  });

  test("watchNextMaxItems default and update", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);

    expect(settingsService.watchNextMaxItems, equals(0));

    await settingsService.setWatchNextMaxItems(10);
    expect(settingsService.watchNextMaxItems, equals(10));

    await settingsService.setWatchNextMaxItems(0);
    expect(settingsService.watchNextMaxItems, equals(0));
  });

  test("watchNextExcludedPackages default and toggle", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);

    expect(settingsService.watchNextExcludedPackages, isEmpty);
    expect(settingsService.isWatchNextPackageExcluded("com.plexapp.android"), isFalse);

    await settingsService.toggleWatchNextExcludedPackage("com.plexapp.android");
    expect(settingsService.watchNextExcludedPackages, ["com.plexapp.android"]);
    expect(settingsService.isWatchNextPackageExcluded("com.plexapp.android"), isTrue);

    await settingsService.toggleWatchNextExcludedPackage("com.netflix.ninja");
    expect(settingsService.watchNextExcludedPackages, ["com.plexapp.android", "com.netflix.ninja"]);

    await settingsService.toggleWatchNextExcludedPackage("com.plexapp.android");
    expect(settingsService.watchNextExcludedPackages, ["com.netflix.ninja"]);
    expect(settingsService.isWatchNextPackageExcluded("com.plexapp.android"), isFalse);
  });


  test("setUse24HourTimeFormat", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);
    final expected = "XYZ";

    await settingsService.setDateTimeFormat("", expected);

    expect(settingsService.timeFormat, expected);
  });

  test("setGradientUuid", () async {
    final sharedPreferences = await SharedPreferences.getInstance();
    final settingsService = SettingsService(sharedPreferences);

    await settingsService.setGradientUuid("4730aa2d-1a90-49a6-9942-ffe82f470e26");

    expect(sharedPreferences.getString("gradient_uuid"), "4730aa2d-1a90-49a6-9942-ffe82f470e26");
  });


  group("getGradientUuid", () {
    test("without uuid from shared preferences", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.clear();
      final settingsService = SettingsService(sharedPreferences);

      final gradientUuid = settingsService.gradientUuid;

      expect(gradientUuid, null);
    });

    test("with uuid from shared preferences", () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      await sharedPreferences.clear();
      sharedPreferences.setString("gradient_uuid", "4730aa2d-1a90-49a6-9942-ffe82f470e26");
      final settingsService = SettingsService(sharedPreferences);

      final gradientUuid = settingsService.gradientUuid;

      expect(gradientUuid, "4730aa2d-1a90-49a6-9942-ffe82f470e26");
    });
  });

  group("getDateFormat", ()  {
    test("with default", () async {
      expect(settingsService.dateFormat, SettingsService.defaultDateFormat);
    });

    test("defaults to the short weekday, day and month, which is a preset", () async {
      await initializeDateFormatting('en');
      expect(SettingsService.defaultDateFormat, "EEE d MMM");
      expect(dateFormatPresets.map((preset) => preset.$1), contains(SettingsService.defaultDateFormat));
      expect(DateFormat(SettingsService.defaultDateFormat, 'en').format(DateTime(2026, 11, 17)), "Tue 17 Nov");
    });

    test("with value set", () async {
      final expected = "XYZ";

      settingsService.setDateTimeFormat(expected, "");

      expect(settingsService.dateFormat, expected);
    });
  });

  group("unsplash slideshow", () {
    test("stays disabled without an access key", () async {
      await settingsService.setUnsplashSlideshowEnabled(true);

      expect(settingsService.unsplashSlideshowEnabled, isFalse);
    });

    test("runs once a key is set, and clearing the key disables it", () async {
      await settingsService.setUnsplashAccessKey("  abc  ");
      await settingsService.setUnsplashSlideshowEnabled(true);

      expect(settingsService.unsplashAccessKey, "abc");
      expect(settingsService.unsplashSlideshowEnabled, isTrue);

      await settingsService.setUnsplashAccessKey("");
      await settingsService.setUnsplashAccessKey("abc");

      expect(settingsService.unsplashSlideshowEnabled, isFalse);
    });

    test("has defaults for interval and sources", () {
      expect(settingsService.unsplashIntervalMinutes, 10);
      expect(settingsService.unsplashDaySources, ['nature', 'wallpapers', '3d-renders']);
      expect(settingsService.unsplashNightSources, ['milkyway']);
    });
  });

  group("hideStatusBarInGrid", () {
    test("defaults to false", () {
      expect(settingsService.hideStatusBarInGrid, isFalse);
    });

    test("persists value", () async {
      await settingsService.setHideStatusBarInGrid(true);
      expect(settingsService.hideStatusBarInGrid, isTrue);
      expect(sharedPreferences.getBool("hide_status_bar_in_grid"), isTrue);

      await settingsService.setHideStatusBarInGrid(false);
      expect(settingsService.hideStatusBarInGrid, isFalse);
      expect(sharedPreferences.getBool("hide_status_bar_in_grid"), isFalse);
    });
  });

  group("watchNextHideProgramsWithoutImages", () {
    test("defaults to false", () {
      expect(settingsService.watchNextHideProgramsWithoutImages, isFalse);
    });

    test("persists value", () async {
      await settingsService.setWatchNextHideProgramsWithoutImages(true);
      expect(settingsService.watchNextHideProgramsWithoutImages, isTrue);
      expect(sharedPreferences.getBool("watch_next_hide_programs_without_images"), isTrue);

      await settingsService.setWatchNextHideProgramsWithoutImages(false);
      expect(settingsService.watchNextHideProgramsWithoutImages, isFalse);
      expect(sharedPreferences.getBool("watch_next_hide_programs_without_images"), isFalse);
    });
  });

  group("cardCornerRadius", () {
    test("defaults to 12", () {
      expect(settingsService.cardCornerRadius, CARD_CORNER_RADIUS_DEFAULT);
    });

    test("cycles through options and wraps", () async {
      final seen = <double>[];
      for (var i = 0; i < CARD_CORNER_RADIUS_OPTIONS.length; i++) {
        await settingsService.cycleCardCornerRadius();
        seen.add(settingsService.cardCornerRadius);
      }
      expect(seen, [20.0, 28.0, 6.0, 12.0]);
    });

    test("restarts at first option when stored value is not an option", () async {
      await settingsService.setCardCornerRadius(15.0);
      await settingsService.cycleCardCornerRadius();
      expect(settingsService.cardCornerRadius, CARD_CORNER_RADIUS_OPTIONS.first);
    });
  });

  group("appNamesOnFocusOnly", () {
    test("defaults to true", () {
      expect(settingsService.appNamesOnFocusOnly, isTrue);
    });

    test("persists value", () async {
      await settingsService.setAppNamesOnFocusOnly(false);
      expect(settingsService.appNamesOnFocusOnly, isFalse);
      expect(sharedPreferences.getBool("app_names_on_focus_only"), isFalse);
    });
  });

  group("customAppLabel", () {
    test("is null when unset", () {
      expect(settingsService.customAppLabel("com.example"), isNull);
    });

    test("stores a trimmed label per package", () async {
      await settingsService.setCustomAppLabel("com.example", "  Sky  ");
      expect(settingsService.customAppLabel("com.example"), "Sky");
      expect(settingsService.customAppLabel("com.other"), isNull);
    });

    test("blank label removes the custom label", () async {
      await settingsService.setCustomAppLabel("com.example", "Sky");
      await settingsService.setCustomAppLabel("com.example", "   ");
      expect(settingsService.customAppLabel("com.example"), isNull);
    });
  });
}
