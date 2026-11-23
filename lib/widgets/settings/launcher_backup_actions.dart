import 'dart:io';

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/launcher_backup.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/brightness_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

// The app's external files dir (/sdcard/Android/data/<package>/files) is
// reachable with adb pull and adb push without root.
Future<Directory> _backupDirectory() async {
  final directory = await getExternalStorageDirectory();
  if (directory == null) {
    throw const FileSystemException("External storage is not available");
  }
  return directory;
}

Future<void> exportLauncherSetup(BuildContext context) async {
  final localizations = AppLocalizations.of(context)!;
  final appsService = context.read<AppsService>();
  String message;
  try {
    final file = await appsService.exportBackup(await _backupDirectory());
    message = localizations.exportLauncherSetupDone(file.path);
  } catch (e) {
    message = localizations.launcherBackupFailed(e.toString());
  }
  if (context.mounted) {
    await _showMessage(context, localizations.exportLauncherSetup, message);
  }
}

Future<void> importLauncherSetup(BuildContext context) async {
  final localizations = AppLocalizations.of(context)!;
  final appsService = context.read<AppsService>();
  final settingsService = context.read<SettingsService>();
  final brightnessService = context.read<BrightnessService>();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(localizations.importLauncherSetup),
      content: Text(localizations.importLauncherSetupConfirm),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(MaterialLocalizations.of(dialogContext).cancelButtonLabel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(localizations.importLauncherSetupConfirmButton),
        ),
      ],
    ),
  );
  if (confirmed != true) {
    return;
  }

  String message;
  try {
    final report = await appsService.importBackup(await _backupDirectory());
    settingsService.reload();
    // Starts or stops the scheduler to match the imported preference.
    await brightnessService.setEnabled(brightnessService.isEnabled);
    message = [
      localizations.importLauncherSetupDone(report.categoryCount, report.spacerCount),
      if (report.skippedPackages.isNotEmpty)
        localizations.importLauncherSetupSkipped(report.skippedPackages.join(", ")),
      if (report.addedPackages.isNotEmpty) localizations.importLauncherSetupAdded(report.addedPackages.join(", ")),
    ].join("\n\n");
  } on LauncherBackupException catch (e) {
    message = switch (e.error) {
      LauncherBackupError.notFound => localizations.launcherBackupNotFound(e.detail),
      LauncherBackupError.invalid => "${localizations.launcherBackupInvalid}\n${e.detail}",
      LauncherBackupError.unsupportedVersion => localizations.launcherBackupNewerVersion,
    };
  } catch (e) {
    message = localizations.launcherBackupFailed(e.toString());
  }
  if (context.mounted) {
    await _showMessage(context, localizations.importLauncherSetup, message);
  }
}

Future<void> _showMessage(BuildContext context, String title, String message) => showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: SingleChildScrollView(child: Text(message)),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
          ),
        ],
      ),
    );
