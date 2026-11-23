import 'dart:io';

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/launcher_backup.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/brightness_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/general_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _externalFilesDir = "/storage/emulated/0/Android/data/local.tvlauncher/files";

void main() {
  late _FakeAppsService appsService;
  late _RecordingSettingsService settingsService;
  late _FakeBrightnessService brightnessService;

  setUpAll(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1280, 720);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  setUp(() async {
    PathProviderPlatform.instance = _FakePathProviderPlatform();
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    SharedPreferences.resetStatic();
    appsService = _FakeAppsService();
    settingsService = _RecordingSettingsService(await SharedPreferences.getInstance());
    brightnessService = _FakeBrightnessService();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppsService>.value(value: appsService),
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<BrightnessService>.value(value: brightnessService),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Material(child: GeneralSettingsPage()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapTile(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets("export writes to the external files dir and shows the path", (tester) async {
    await pumpPage(tester);

    await tapTile(tester, "Export launcher setup");

    expect(appsService.exportedTo, [_externalFilesDir]);
    expect(find.textContaining("$_externalFilesDir/$launcherBackupFileName"), findsOneWidget);
  });

  testWidgets("import asks first and does nothing on Cancel", (tester) async {
    await pumpPage(tester);

    await tapTile(tester, "Import launcher setup");
    expect(find.textContaining("Replace the home screen layout"), findsOneWidget);

    await tester.tap(find.text("Cancel"));
    await tester.pumpAndSettle();

    expect(appsService.importedFrom, isEmpty);
    expect(settingsService.reloads, 0);
  });

  testWidgets("confirmed import reloads settings and lists skipped and added apps", (tester) async {
    appsService.report = const LauncherImportReport(
      categoryCount: 3,
      spacerCount: 1,
      skippedPackages: ["com.missing.one", "com.missing.two"],
      addedPackages: ["com.new.app"],
    );
    await pumpPage(tester);

    await tapTile(tester, "Import launcher setup");
    await tester.tap(find.text("Import"));
    await tester.pumpAndSettle();

    expect(appsService.importedFrom, [_externalFilesDir]);
    expect(settingsService.reloads, 1);
    expect(brightnessService.setEnabledCalls, 1);
    expect(find.textContaining("Restored. Categories: 3, spacers: 1."), findsOneWidget);
    expect(find.textContaining("com.missing.one, com.missing.two"), findsOneWidget);
    expect(find.textContaining("com.new.app"), findsOneWidget);
  });

  testWidgets("import from a newer launcher explains what to do", (tester) async {
    appsService.importError = LauncherBackupException(LauncherBackupError.unsupportedVersion, "formatVersion 2 > 1");
    await pumpPage(tester);

    await tapTile(tester, "Import launcher setup");
    await tester.tap(find.text("Import"));
    await tester.pumpAndSettle();

    expect(find.textContaining("newer version of TV Launcher"), findsOneWidget);
    expect(settingsService.reloads, 0);
  });
}

class _FakeAppsService extends Mock implements AppsService {
  final List<String> exportedTo = [];
  final List<String> importedFrom = [];
  LauncherImportReport report =
      const LauncherImportReport(categoryCount: 0, spacerCount: 0, skippedPackages: [], addedPackages: []);
  LauncherBackupException? importError;

  @override
  Future<File> exportBackup(Directory directory) async {
    exportedTo.add(directory.path);
    return File("${directory.path}/$launcherBackupFileName");
  }

  @override
  Future<LauncherImportReport> importBackup(Directory directory) async {
    importedFrom.add(directory.path);
    final error = importError;
    if (error != null) throw error;
    return report;
  }
}

class _RecordingSettingsService extends SettingsService {
  int reloads = 0;

  _RecordingSettingsService(super.sharedPreferences);

  @override
  void reload() {
    reloads++;
    super.reload();
  }
}

class _FakeBrightnessService extends Mock implements BrightnessService {
  int setEnabledCalls = 0;

  @override
  bool get isEnabled => false;

  @override
  Future<void> setEnabled(bool enabled) async => setEnabledCalls++;
}

class _FakePathProviderPlatform extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  @override
  Future<String?> getExternalStoragePath() async => _externalFilesDir;
}
