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

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/models/category.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String launcherBackupFileName = "tv-launcher-backup.json";
const String launcherBackupFormat = "tv-launcher-backup";
const int launcherBackupFormatVersion = 1;

const String _customAppLabelPrefix = "custom_app_label:";

// Left out of a backup and left alone by an import: paths into this TV's
// private storage, the credit of the wallpaper on screen, and API credentials.
const List<String> _machineLocalPrefixes = ["custom_banner_"];
const Set<String> _machineLocalKeys = {
  "unsplash_author",
  "reddit_current_title",
  "reddit_current_author",
  "reddit_current_subreddit",
  "unsplash_access_key",
  "reddit_client_id",
  "reddit_client_secret",
};

bool isMachineLocalPreference(String key) =>
    _machineLocalKeys.contains(key) || _machineLocalPrefixes.any(key.startsWith);

enum LauncherBackupError { notFound, invalid, unsupportedVersion }

class LauncherBackupException implements Exception {
  final LauncherBackupError error;
  final String detail;

  LauncherBackupException(this.error, this.detail);

  @override
  String toString() => "LauncherBackupException(${error.name}): $detail";
}

class LauncherImportReport {
  final int categoryCount;
  final int spacerCount;

  /// Packages the backup mentions that are not installed on this TV.
  final List<String> skippedPackages;

  /// Installed packages the backup does not know, placed like a fresh install.
  final List<String> addedPackages;

  const LauncherImportReport({
    required this.categoryCount,
    required this.spacerCount,
    required this.skippedPackages,
    required this.addedPackages,
  });
}

Future<Map<String, Object?>> exportLauncherBackup(
  FLauncherDatabase database,
  SharedPreferences preferences, {
  DateTime? now,
}) async {
  final categories = await database.getCategories();
  final spacers = await database.getLauncherSpacers();
  final appsCategories = await database.getAppsCategories();
  final apps = await database.getApplications();

  final List<(int, Map<String, Object?>)> sections = [
    for (final category in categories)
      (
        category.order,
        {
          "kind": "category",
          "name": category.name,
          "sort": category.sort.name,
          "type": category.type.name,
          "rowHeight": category.rowHeight,
          "columnsCount": category.columnsCount,
          "apps": (appsCategories.where((entry) => entry.categoryId == category.id).toList()
                ..sort((a, b) => a.order.compareTo(b.order)))
              .map((entry) => entry.appPackageName)
              .toList(),
        }
      ),
    for (final spacer in spacers) (spacer.order, {"kind": "spacer", "height": spacer.height}),
  ];
  sections.sort((a, b) => a.$1.compareTo(b.$1));

  final sortedApps = apps.toList()..sort((a, b) => a.packageName.compareTo(b.packageName));
  final preferenceKeys = preferences.getKeys().where((key) => !isMachineLocalPreference(key)).toList()..sort();

  return {
    "format": launcherBackupFormat,
    "formatVersion": launcherBackupFormatVersion,
    "exportedAt": (now ?? DateTime.now()).toUtc().toIso8601String(),
    "sections": sections.map((section) => section.$2).toList(),
    "apps": [
      for (final app in sortedApps) {"packageName": app.packageName, "hidden": app.hidden},
    ],
    "preferences": {
      for (final key in preferenceKeys)
        if (_encodePreference(preferences.get(key)) case final encoded?) key: encoded,
    },
  };
}

Future<LauncherImportReport> importLauncherBackup(
  Map<String, Object?> backup,
  FLauncherDatabase database,
  SharedPreferences preferences,
) async {
  final parsed = _ParsedBackup.parse(backup);

  final installedApps = await database.getApplications();
  final installed = {for (final app in installedApps) app.packageName};

  final mentioned = <String>{
    ...?parsed.knownPackages,
    ...?parsed.hiddenPackages,
    for (final section in parsed.sections)
      if (section is _CategorySection) ...section.apps,
    for (final key in parsed.preferences?.keys ?? const <String>[])
      if (key.startsWith(_customAppLabelPrefix)) key.substring(_customAppLabelPrefix.length),
  };
  final added = installedApps
      .where((app) => !mentioned.contains(app.packageName))
      .map((app) => app.packageName)
      .toList()
    ..sort();

  int categoryCount = 0;
  int spacerCount = 0;
  bool placedNewApps = false;
  await database.transaction(() async {
    await database.delete(database.appsCategories).go();
    await database.delete(database.categories).go();
    await database.delete(database.launcherSpacers).go();

    final rows = <AppsCategoriesCompanion>[];
    final categoryIds = <(String, int)>[];
    for (final (order, section) in parsed.sections.indexed) {
      switch (section) {
        case _CategorySection():
          final id = await database.insertCategory(CategoriesCompanion.insert(
            name: section.name,
            order: order,
            sort: Value(section.sort),
            type: Value(section.type),
            rowHeight: Value(section.rowHeight),
            columnsCount: Value(section.columnsCount),
          ));
          categoryIds.add((section.name, id));
          categoryCount++;
          final present = section.apps.where(installed.contains).toList();
          for (final (appOrder, packageName) in present.indexed) {
            rows.add(AppsCategoriesCompanion.insert(categoryId: id, appPackageName: packageName, order: appOrder));
          }
        case _SpacerSection():
          await database.insertSpacer(LauncherSpacersCompanion.insert(height: section.height, order: order));
          spacerCount++;
      }
    }

    final targetId = _targetCategoryForNewApps(categoryIds);
    if (targetId != null) {
      placedNewApps = true;
      final start = rows.where((row) => row.categoryId.value == targetId).length;
      for (final (index, packageName) in added.indexed) {
        rows.add(AppsCategoriesCompanion.insert(categoryId: targetId, appPackageName: packageName, order: start + index));
      }
    }
    await database.insertAppsCategories(rows);

    final hiddenPackages = parsed.hiddenPackages;
    if (hiddenPackages == null) {
      return;
    }
    await database.update(database.apps).write(const AppsCompanion(hidden: Value(false)));
    final hidden = hiddenPackages.where(installed.contains).toList();
    if (hidden.isNotEmpty) {
      await (database.update(database.apps)..where((tbl) => tbl.packageName.isIn(hidden)))
          .write(const AppsCompanion(hidden: Value(true)));
    }
  });

  final backupPreferences = parsed.preferences ?? const <String, Object>{};
  if (parsed.preferences != null) {
    for (final key in preferences.getKeys().toList()) {
      if (!isMachineLocalPreference(key) && !backupPreferences.containsKey(key)) {
        await preferences.remove(key);
      }
    }
  }
  for (final MapEntry(:key, :value) in backupPreferences.entries) {
    if (isMachineLocalPreference(key)) {
      continue;
    }
    if (key.startsWith(_customAppLabelPrefix) && !installed.contains(key.substring(_customAppLabelPrefix.length))) {
      continue;
    }
    await _writePreference(preferences, key, value);
  }

  return LauncherImportReport(
    categoryCount: categoryCount,
    spacerCount: spacerCount,
    skippedPackages: (mentioned.difference(installed).toList()..sort()),
    addedPackages: placedNewApps ? added : const [],
  );
}

Future<File> writeLauncherBackupFile(
  Directory directory,
  FLauncherDatabase database,
  SharedPreferences preferences,
) async {
  final backup = await exportLauncherBackup(database, preferences);
  await directory.create(recursive: true);
  final file = File("${directory.path}/$launcherBackupFileName");
  await file.writeAsString(const JsonEncoder.withIndent("  ").convert(backup), flush: true);
  return file;
}

Future<LauncherImportReport> importLauncherBackupFile(
  Directory directory,
  FLauncherDatabase database,
  SharedPreferences preferences,
) async {
  final file = File("${directory.path}/$launcherBackupFileName");
  if (!await file.exists()) {
    throw LauncherBackupException(LauncherBackupError.notFound, file.path);
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(await file.readAsString());
  } on FormatException catch (e) {
    throw LauncherBackupException(LauncherBackupError.invalid, e.message);
  }
  if (decoded is! Map<String, Object?>) {
    throw LauncherBackupException(LauncherBackupError.invalid, "top level is not an object");
  }
  return importLauncherBackup(decoded, database, preferences);
}

// Same rule as a newly installed app: "All Apps", else the first category
// that is not the dock, else the first one.
int? _targetCategoryForNewApps(List<(String, int)> categories) {
  for (final (name, id) in categories) {
    if (name.toLowerCase() == "all apps") return id;
  }
  for (final (name, id) in categories) {
    if (name.toLowerCase() != "favorites") return id;
  }
  return categories.isEmpty ? null : categories.first.$2;
}

Map<String, Object?>? _encodePreference(Object? value) => switch (value) {
      bool() => {"type": "bool", "value": value},
      int() => {"type": "int", "value": value},
      double() => {"type": "double", "value": value},
      String() => {"type": "string", "value": value},
      List() => {"type": "stringList", "value": value.cast<String>()},
      _ => null,
    };

Future<void> _writePreference(SharedPreferences preferences, String key, Object value) => switch (value) {
      bool() => preferences.setBool(key, value),
      int() => preferences.setInt(key, value),
      double() => preferences.setDouble(key, value),
      String() => preferences.setString(key, value),
      List<String>() => preferences.setStringList(key, value),
      _ => throw StateError("unreachable preference type for $key"),
    };

sealed class _Section {}

class _CategorySection extends _Section {
  final String name;
  final CategorySort sort;
  final CategoryType type;
  final int rowHeight;
  final int columnsCount;
  final List<String> apps;

  _CategorySection(this.name, this.sort, this.type, this.rowHeight, this.columnsCount, this.apps);
}

class _SpacerSection extends _Section {
  final int height;

  _SpacerSection(this.height);
}

/// Validates the whole file before anything on this TV is changed.
class _ParsedBackup {
  final List<_Section> sections;

  // Null when the file has no such part: that part of this TV is left alone.
  final Set<String>? knownPackages;
  final Set<String>? hiddenPackages;
  final Map<String, Object>? preferences;

  _ParsedBackup(this.sections, this.knownPackages, this.hiddenPackages, this.preferences);

  static Never _invalid(String detail) => throw LauncherBackupException(LauncherBackupError.invalid, detail);

  static _ParsedBackup parse(Map<String, Object?> json) {
    if (json["format"] != launcherBackupFormat) {
      _invalid("not a $launcherBackupFormat file");
    }
    final version = json["formatVersion"];
    if (version is! int || version < 1) {
      _invalid("formatVersion $version");
    }
    if (version > launcherBackupFormatVersion) {
      throw LauncherBackupException(
          LauncherBackupError.unsupportedVersion, "formatVersion $version > $launcherBackupFormatVersion");
    }

    final sections = <_Section>[];
    for (final section in _list(json["sections"], "sections")) {
      if (section is! Map) _invalid("section is not an object");
      switch (section["kind"]) {
        case "category":
          final name = section["name"];
          if (name is! String) _invalid("category without a name");
          sections.add(_CategorySection(
            name,
            CategorySort.values.asNameMap()[section["sort"]] ?? Category.Sort,
            CategoryType.values.asNameMap()[section["type"]] ?? Category.Type,
            _int(section["rowHeight"]) ?? Category.RowHeight,
            _int(section["columnsCount"]) ?? Category.ColumnsCount,
            _strings(section["apps"] ?? const [], "category apps"),
          ));
        case "spacer":
          final height = _int(section["height"]);
          if (height == null) _invalid("spacer without a height");
          sections.add(_SpacerSection(height));
        default:
          _invalid("section kind ${section["kind"]}");
      }
    }

    Set<String>? known;
    Set<String>? hidden;
    if (json.containsKey("apps")) {
      known = {};
      hidden = {};
      for (final app in _list(json["apps"], "apps")) {
        if (app is! Map || app["packageName"] is! String) _invalid("app without a packageName");
        final packageName = app["packageName"] as String;
        known.add(packageName);
        if (app["hidden"] == true) hidden.add(packageName);
      }
    }

    Map<String, Object>? preferences;
    if (json.containsKey("preferences")) {
      final rawPreferences = json["preferences"];
      if (rawPreferences is! Map) _invalid("preferences is not an object");
      preferences = {};
      for (final MapEntry(:key, :value) in rawPreferences.entries) {
        if (key is! String || value is! Map) _invalid("preference $key");
        preferences[key] = _decodePreference(key, value["type"], value["value"]);
      }
    }

    return _ParsedBackup(sections, known, hidden, preferences);
  }

  static Object _decodePreference(String key, Object? type, Object? value) => switch ((type, value)) {
        ("bool", bool value) => value,
        ("int", int value) => value,
        ("double", num value) => value.toDouble(),
        ("string", String value) => value,
        ("stringList", List value) => _strings(value, "preference $key"),
        _ => _invalid("preference $key has type $type and value $value"),
      };

  static List<Object?> _list(Object? value, String what) => value is List ? value : _invalid("$what is not a list");

  static List<String> _strings(Object? value, String what) {
    final list = _list(value, what);
    if (list.any((item) => item is! String)) _invalid("$what holds a non-string");
    return list.cast<String>().toList();
  }

  static int? _int(Object? value) => value is int ? value : null;
}
