import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flauncher/database.dart';
import 'package:flauncher/launcher_backup.dart';
import 'package:flauncher/models/category.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

Future<void> _installApps(FLauncherDatabase database, List<String> packageNames) => database.persistApps([
      for (final packageName in packageNames)
        AppsCompanion.insert(packageName: packageName, name: packageName, version: "1.0"),
    ]);

/// Two categories with a spacer between them, a hidden app and app orders out of insertion order.
Future<void> _seedSourceLayout(FLauncherDatabase database) async {
  await _installApps(database, ["a", "b", "c", "d", "e"]);
  final favorites = await database.insertCategory(CategoriesCompanion.insert(
    name: "Favorites",
    order: 0,
    type: const Value(CategoryType.row),
  ));
  await database.insertSpacer(LauncherSpacersCompanion.insert(height: 24, order: 1));
  final allApps = await database.insertCategory(CategoriesCompanion.insert(
    name: "All Apps",
    order: 2,
    type: const Value(CategoryType.grid),
    sort: const Value(CategorySort.alphabetical),
    rowHeight: const Value(140),
    columnsCount: const Value(5),
  ));
  await database.insertAppsCategories([
    AppsCategoriesCompanion.insert(categoryId: favorites, appPackageName: "b", order: 0),
    AppsCategoriesCompanion.insert(categoryId: favorites, appPackageName: "a", order: 1),
    AppsCategoriesCompanion.insert(categoryId: allApps, appPackageName: "d", order: 0),
    AppsCategoriesCompanion.insert(categoryId: allApps, appPackageName: "c", order: 1),
  ]);
  await database.updateApp("e", const AppsCompanion(hidden: Value(true)));
}

Future<void> _seedSourcePreferences(SharedPreferences preferences) async {
  await preferences.setBool("show_category_titles", true);
  await preferences.setInt("watch_next_max_items", 15);
  await preferences.setDouble("card_corner_radius", 20.0);
  await preferences.setString("accent_color", "00BFA5");
  await preferences.setStringList("reddit_subreddits", ["EarthPorn", "SpacePorn"]);
  await preferences.setString("custom_app_label:b", "EON TV");
  await preferences.setString("custom_banner_b", "/data/user/0/local.tvlauncher/app_flutter/banner_b");
  await preferences.setString("unsplash_access_key", "source-key");
}

/// Sections as (name, type, sort, rowHeight, columnsCount, "package@order,...") or "spacer:height".
Future<List<Object>> _layout(FLauncherDatabase database) async {
  final categories = await database.getCategories();
  final spacers = await database.getLauncherSpacers();
  final appsCategories = await database.getAppsCategories();
  final sections = <(int, Object)>[
    for (final category in categories)
      (
        category.order,
        (
          category.name,
          category.type,
          category.sort,
          category.rowHeight,
          category.columnsCount,
          (appsCategories.where((entry) => entry.categoryId == category.id).toList()
                ..sort((a, b) => a.order.compareTo(b.order)))
              .map((entry) => "${entry.appPackageName}@${entry.order}")
              .join(","),
        )
      ),
    for (final spacer in spacers) (spacer.order, "spacer:${spacer.height}"),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return sections.map((section) => section.$2).toList();
}

Future<Set<String>> _hidden(FLauncherDatabase database) async =>
    (await database.getApplications()).where((app) => app.hidden).map((app) => app.packageName).toSet();

/// What a file written on one TV and read on another looks like.
Map<String, Object?> _throughJson(Map<String, Object?> backup) =>
    jsonDecode(jsonEncode(backup)) as Map<String, Object?>;

void main() {
  // Source and target TVs are two separate in-memory databases on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FLauncherDatabase source;
  late FLauncherDatabase target;
  late SharedPreferences preferences;

  setUp(() async {
    source = FLauncherDatabase.inMemory();
    target = FLauncherDatabase.inMemory();
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    SharedPreferences.resetStatic();
    preferences = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  test("round trip restores layout, hidden apps and preferences on another TV", () async {
    await _seedSourceLayout(source);
    await _seedSourcePreferences(preferences);

    final backup = _throughJson(await exportLauncherBackup(source, preferences));
    final sourceLayout = await _layout(source);
    final sourcePreferences = {
      for (final key in preferences.getKeys()) key: preferences.get(key),
    };

    // The new TV: same apps, a default layout, its own key and a stale label.
    await preferences.clear();
    await preferences.setString("unsplash_access_key", "target-key");
    await preferences.setString("custom_app_label:c", "Stale");
    await preferences.setBool("show_category_titles", false);
    await _installApps(target, ["a", "b", "c", "d", "e"]);
    await target.insertCategory(CategoriesCompanion.insert(name: "All Apps", order: 0));

    final report = await importLauncherBackup(backup, target, preferences);

    expect(await _layout(target), sourceLayout);
    expect(await _hidden(target), {"e"});
    expect(report.categoryCount, 2);
    expect(report.spacerCount, 1);
    expect(report.skippedPackages, isEmpty);
    expect(report.addedPackages, isEmpty);

    expect(preferences.getBool("show_category_titles"), isTrue);
    expect(preferences.getInt("watch_next_max_items"), 15);
    expect(preferences.getDouble("card_corner_radius"), 20.0);
    expect(preferences.getString("accent_color"), "00BFA5");
    expect(preferences.getStringList("reddit_subreddits"), ["EarthPorn", "SpacePorn"]);
    expect(preferences.getString("custom_app_label:b"), "EON TV");
    expect(preferences.containsKey("custom_app_label:c"), isFalse);
    // API credentials move with the setup; machine-local keys do not.
    expect(preferences.getString("unsplash_access_key"), "source-key");
    expect(preferences.containsKey("custom_banner_b"), isFalse);
    expect(sourcePreferences.keys.where((key) => !isMachineLocalPreference(key)).toSet(),
        preferences.getKeys().where((key) => !isMachineLocalPreference(key)).toSet());
  });

  test("export carries API credentials and leaves out image paths", () async {
    await _seedSourcePreferences(preferences);
    await preferences.setString("reddit_client_secret", "secret");
    await preferences.setString("unsplash_author", "Someone");

    final backup = await exportLauncherBackup(source, preferences);
    final exported = (backup["preferences"] as Map).keys.toSet();

    expect(backup["format"], launcherBackupFormat);
    expect(backup["formatVersion"], launcherBackupFormatVersion);
    expect(exported, contains("custom_app_label:b"));
    expect(exported, contains("unsplash_access_key"));
    expect(exported, contains("reddit_client_secret"));
    expect(exported, isNot(contains("unsplash_author")));
    expect(exported, isNot(contains("custom_banner_b")));
  });

  test("apps missing on the new TV are skipped and reported, new apps go to All Apps", () async {
    await _seedSourceLayout(source);
    await _seedSourcePreferences(preferences);
    final backup = _throughJson(await exportLauncherBackup(source, preferences));
    await preferences.clear();

    // "b" (in Favorites, with a custom label) and hidden "e" are not installed; "z" is new.
    await _installApps(target, ["a", "c", "d", "z"]);

    final report = await importLauncherBackup(backup, target, preferences);

    expect(report.skippedPackages, ["b", "e"]);
    expect(report.addedPackages, ["z"]);
    expect(await _layout(target), [
      ("Favorites", CategoryType.row, CategorySort.manual, Category.RowHeight, Category.ColumnsCount, "a@0"),
      "spacer:24",
      ("All Apps", CategoryType.grid, CategorySort.alphabetical, 140, 5, "d@0,c@1,z@2"),
    ]);
    expect(await _hidden(target), isEmpty);
    expect((await target.getApplications()).map((app) => app.packageName).toSet(), {"a", "c", "d", "z"});
    expect(preferences.containsKey("custom_app_label:b"), isFalse);
    expect(preferences.getString("accent_color"), "00BFA5");
  });

  test("a newer format version is refused before anything changes", () async {
    await _installApps(target, ["a"]);
    await target.insertCategory(CategoriesCompanion.insert(name: "All Apps", order: 0));
    await preferences.setBool("show_category_titles", true);
    final before = await _layout(target);

    final backup = {
      "format": launcherBackupFormat,
      "formatVersion": launcherBackupFormatVersion + 1,
      "sections": [],
      "preferences": {},
    };

    await expectLater(
      importLauncherBackup(backup, target, preferences),
      throwsA(isA<LauncherBackupException>()
          .having((e) => e.error, "error", LauncherBackupError.unsupportedVersion)),
    );
    expect(await _layout(target), before);
    expect(preferences.getBool("show_category_titles"), isTrue);
  });

  test("a version 1 file without the optional parts imports with defaults and keeps the rest", () async {
    await _installApps(target, ["a", "b", "c"]);
    await target.updateApp("c", const AppsCompanion(hidden: Value(true)));
    await preferences.setString("accent_color", "F50057");

    // Hand-written minimal file: no "apps", no "preferences", category fields left out.
    final backup = {
      "format": launcherBackupFormat,
      "formatVersion": 1,
      "sections": [
        {"kind": "category", "name": "Favorites", "apps": ["b"]},
        {"kind": "category", "name": "Movies", "type": "row", "sort": "lastUsed"},
      ],
    };

    final report = await importLauncherBackup(backup, target, preferences);

    expect(await _layout(target), [
      ("Favorites", Category.Type, Category.Sort, Category.RowHeight, Category.ColumnsCount, "b@0"),
      ("Movies", CategoryType.row, CategorySort.lastUsed, Category.RowHeight, Category.ColumnsCount, "a@0,c@1"),
    ]);
    expect(report.addedPackages, ["a", "c"]);
    expect(await _hidden(target), {"c"});
    expect(preferences.getString("accent_color"), "F50057");
  });

  test("a malformed file is refused before anything changes", () async {
    await _installApps(target, ["a"]);
    await target.insertCategory(CategoriesCompanion.insert(name: "All Apps", order: 0));
    final before = await _layout(target);

    final backup = {
      "format": launcherBackupFormat,
      "formatVersion": 1,
      "sections": [
        {"kind": "category", "name": "Favorites"},
        {"kind": "spacer"},
      ],
    };

    await expectLater(
      importLauncherBackup(backup, target, preferences),
      throwsA(isA<LauncherBackupException>().having((e) => e.error, "error", LauncherBackupError.invalid)),
    );
    expect(await _layout(target), before);
  });

  test("the file written by export is read back by import", () async {
    final directory = await Directory.systemTemp.createTemp("launcher_backup_test");
    addTearDown(() => directory.delete(recursive: true));

    await expectLater(
      importLauncherBackupFile(directory, target, preferences),
      throwsA(isA<LauncherBackupException>().having((e) => e.error, "error", LauncherBackupError.notFound)),
    );

    await _seedSourceLayout(source);
    await _seedSourcePreferences(preferences);
    final file = await writeLauncherBackupFile(directory, source, preferences);
    expect(file.path, endsWith("/$launcherBackupFileName"));

    await _installApps(target, ["a", "b", "c", "d", "e"]);
    await importLauncherBackupFile(directory, target, preferences);
    expect(await _layout(target), await _layout(source));

    await file.writeAsString("{not json");
    await expectLater(
      importLauncherBackupFile(directory, target, preferences),
      throwsA(isA<LauncherBackupException>().having((e) => e.error, "error", LauncherBackupError.invalid)),
    );
  });
}
