import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app.dart';
import '../providers/apps_service.dart';
import '../providers/launcher_state.dart';
import '../providers/network_service.dart';
import '../providers/settings_service.dart';
import 'app_bar_focus_ring.dart';
import 'daily_wifi_usage_widget.dart';
import 'date_time_widget.dart';
import 'network_widget.dart';

class FocusAwareAppBar extends StatefulWidget implements PreferredSizeWidget
{
  const FocusAwareAppBar({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return FocusAwareAppBarState();
  }

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight);
}

class FocusAwareAppBarState extends State<FocusAwareAppBar>
{
  bool focused = false;
  late FocusNode _settingsFocusNode;

  @override
  void initState() {
    super.initState();
    _settingsFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _settingsFocusNode.dispose();
    super.dispose();
  }

  void focusSettings() {
    _settingsFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Selector2<SettingsService, LauncherState, ({bool autoHide, bool hideInGrid, bool appGridFocused})>(
      selector: (_, settings, launcherState) => (
        autoHide: settings.autoHideAppBarEnabled,
        hideInGrid: settings.hideStatusBarInGrid,
        appGridFocused: launcherState.appGridFocused,
      ),
      builder: (context, data, widget) {
        final isVisible = focused || (!data.autoHide && !(data.hideInGrid && data.appGridFocused));

        return Focus(
          canRequestFocus: false,
          onFocusChange: (hasFocus) {
            if (hasFocus) {
              context.read<LauncherState>().setAppGridFocused(false);
            }
            setState(() {
              focused = hasFocus;
            });
          },
          child: IgnorePointer(
            ignoring: !isVisible,
            child: AnimatedOpacity(
              curve: Curves.easeInOut,
              duration: const Duration(milliseconds: 200),
              opacity: isVisible ? 1.0 : 0.0,
              child: ClipRect(
                child: AnimatedContainer(
                  curve: Curves.decelerate,
                  duration: const Duration(milliseconds: 200),
                  height: isVisible ? kToolbarHeight : 0,
                  child: OverflowBox(
                    minHeight: 0,
                    maxHeight: kToolbarHeight,
                    alignment: Alignment.topCenter,
                    child: widget!,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: RepaintBoundary(
        child: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          // Left side: Settings, Network indicator, WiFi usage
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Settings button
              AppBarFocusRing(
                focusNode: _settingsFocusNode,
                onPressed: () => showDialog(context: context, builder: (_) => const SettingsPanel()),
                semanticLabel: 'Settings',
                child: const Icon(
                  Icons.settings_outlined,
                  size: 20,
                  color: Colors.white,
                  shadows: [
                    Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Network indicator (conditionally shown)
              Selector<SettingsService, bool>(
                selector: (_, settings) => settings.showNetworkIndicatorInStatusBar,
                builder: (context, showNetwork, _) => showNetwork
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AppBarFocusRing(
                        onPressed: () => context.read<NetworkService>().openWifiSettings(),
                        semanticLabel: 'Network',
                        child: const NetworkWidget(),
                      ),
                    )
                  : const SizedBox.shrink(),
              ),
              // WiFi usage widget
              Selector<SettingsService, bool>(
                selector: (_, settings) => settings.showWifiWidgetInStatusBar,
                builder: (context, showWifi, _) => showWifi
                  ? const DailyWifiUsageWidget()
                  : const SizedBox.shrink(),
              ),
              const _AppShortcuts(),
            ],
          ),
          // Right side: Date/Time only
          actions: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 32),
              child: Selector<SettingsService,
                  ({
                    bool showDateInStatusBar,
                    bool showTimeInStatusBar,
                    String dateFormat,
                    String timeFormat })>(
                selector: (context, service) => (
                showDateInStatusBar: service.showDateInStatusBar,
                showTimeInStatusBar: service.showTimeInStatusBar,
                dateFormat: service.dateFormat,
                timeFormat: service.timeFormat),
                builder: (context, dateTimeSettings, _) {
                  // Define standard text style
                  const textStyle = TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                    shadows: [
                      Shadow(color: Colors.black54, offset: Offset(0, 2), blurRadius: 4)
                    ],
                  );

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Date
                      if (dateTimeSettings.showDateInStatusBar)
                        DateTimeWidget(
                          dateTimeSettings.dateFormat,
                          key: const Key("statusbar_date"),
                          updateInterval: const Duration(minutes: 1),
                          textStyle: textStyle,
                        ),
                      
                      if (dateTimeSettings.showDateInStatusBar && dateTimeSettings.showTimeInStatusBar)
                          const SizedBox(width: 16),

                      // Clock
                      if (dateTimeSettings.showTimeInStatusBar)
                        DateTimeWidget(
                          dateTimeSettings.timeFormat,
                          key: const Key("statusbar_clock"),
                          updateInterval: const Duration(minutes: 1),
                          textStyle: textStyle.copyWith(fontWeight: FontWeight.bold),
                        ),
                    ]
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Apps opened from the top bar instead of the dock. A shortcut only shows when its app is installed.
const List<({String packageName, IconData icon, String label})> kTopBarShortcuts = [
  (packageName: 'com.android.vending', icon: Icons.shop_outlined, label: 'Play Store'),
  (packageName: 'com.tcl.browser', icon: Icons.public, label: 'Browser'),
  (packageName: 'org.videolan.vlc', icon: Icons.dns_outlined, label: 'Router HDD'),
];

class _AppShortcuts extends StatelessWidget {
  const _AppShortcuts();

  @override
  Widget build(BuildContext context) {
    final apps = context.select<AppsService, List<App>>(
      (service) => kTopBarShortcuts.map((s) => service.getApplication(s.packageName)).whereType<App>().toList(),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final shortcut in kTopBarShortcuts)
          if (apps.firstWhereOrNull((app) => app.packageName == shortcut.packageName) case final app?)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AppBarFocusRing(
                key: Key("top_bar_shortcut_${shortcut.packageName}"),
                onPressed: () => context.read<AppsService>().launchApp(app),
                semanticLabel: shortcut.label,
                child: _ShortcutIcon(packageName: shortcut.packageName, fallback: shortcut.icon),
              ),
            ),
      ],
    );
  }
}

/// The app's own launcher icon, or [fallback] while it loads or when the app has none.
class _ShortcutIcon extends StatefulWidget {
  final String packageName;
  final IconData fallback;

  const _ShortcutIcon({required this.packageName, required this.fallback});

  @override
  State<_ShortcutIcon> createState() => _ShortcutIconState();
}

class _ShortcutIconState extends State<_ShortcutIcon> {
  static const double _size = 24;
  late final Future<Uint8List> _icon = context.read<AppsService>().getAppIcon(widget.packageName);

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      widget.fallback,
      size: 20,
      color: Colors.white,
      shadows: const [Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2))],
    );
    return SizedBox.square(
      dimension: _size,
      child: FutureBuilder<Uint8List>(
        future: _icon,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) {
            return Center(child: fallback);
          }
          return Image.memory(
            bytes,
            width: _size,
            height: _size,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => Center(child: fallback),
          );
        },
      ),
    );
  }
}
