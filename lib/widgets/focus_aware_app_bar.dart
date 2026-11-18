import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app.dart';
import '../providers/apps_service.dart';
import '../providers/launcher_state.dart';
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
          // The first glyph starts on the content keyline (x = 48); its focus circle reaches 7 dp
          // further left.
          titleSpacing: kTopBarKeyline - _kTopBarIconPadding,
          // Left side: Settings, WiFi usage, app shortcuts
          title: Padding(
            padding: const EdgeInsets.only(top: _kTopBarTopOffset),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBarFocusRing(
                  focusNode: _settingsFocusNode,
                  onPressed: () => showDialog(context: context, builder: (_) => const SettingsPanel()),
                  semanticLabel: 'Settings',
                  child: _barIcon(Icons.settings_outlined),
                ),
                const SizedBox(width: _kTopBarRingGap),
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
          ),
          // Right side: network status, date and time
          actions: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: kTopBarKeyline, top: _kTopBarTopOffset),
              child: Selector<SettingsService,
                  ({
                    bool showNetwork,
                    bool showDateInStatusBar,
                    bool showTimeInStatusBar,
                    String dateFormat,
                    String timeFormat })>(
                selector: (context, service) => (
                showNetwork: service.showNetworkIndicatorInStatusBar,
                showDateInStatusBar: service.showDateInStatusBar,
                showTimeInStatusBar: service.showTimeInStatusBar,
                dateFormat: service.dateFormat,
                timeFormat: service.timeFormat),
                builder: (context, dateTimeSettings, _) {
                  final showDate = dateTimeSettings.showDateInStatusBar;
                  final showTime = dateTimeSettings.showTimeInStatusBar;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Status only: not focusable; Wi-Fi settings stay reachable through Settings.
                      if (dateTimeSettings.showNetwork) ...[
                        const NetworkWidget(
                          key: Key("statusbar_network"),
                          size: 15,
                          color: Color(0xB3FFFFFF), // 70% white
                          padding: EdgeInsets.zero,
                          shadows: [Shadow(color: Color(0x99000000), offset: Offset(0, 1), blurRadius: 2)],
                        ),
                        if (showDate || showTime) const SizedBox(width: 10),
                      ],
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          if (showDate)
                            DateTimeWidget(
                              dateTimeSettings.dateFormat,
                              key: const Key("statusbar_date"),
                              updateInterval: const Duration(minutes: 1),
                              textStyle: _kDateTextStyle,
                            ),
                          if (showDate && showTime) const SizedBox(width: 10),
                          if (showTime)
                            DateTimeWidget(
                              dateTimeSettings.timeFormat,
                              key: const Key("statusbar_clock"),
                              updateInterval: const Duration(minutes: 1),
                              textStyle: _kTimeTextStyle,
                            ),
                        ],
                      ),
                    ],
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

/// Left edge of the top bar glyphs and right edge of the clock (x = 48 and x = 912 on a 960 dp
/// wide screen).
const kTopBarKeyline = 48.0;

/// Moves the bar's content down so the glyphs centre at y = 32.
const _kTopBarTopOffset = 8.0;

const _kTopBarIconSize = 18.0;
const _kTopBarIconPadding = 7.0;

/// 16 dp between glyphs, minus the focus circles' padding on both sides.
const _kTopBarRingGap = 16.0 - 2 * _kTopBarIconPadding;

const Color _kTopBarIconColor = Color(0xCCFFFFFF); // 80% white

/// Shadow on the characters only; there is no dark area behind the date and time.
const List<Shadow> _kClockShadows = [
  Shadow(color: Color(0x99000000), offset: Offset(0, 1), blurRadius: 3),
  Shadow(color: Color(0x80000000), blurRadius: 1),
];

const TextStyle _kDateTextStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w400,
  letterSpacing: 0,
  color: Color(0xBFFFFFFF), // 75% white
  shadows: _kClockShadows,
);

const TextStyle _kTimeTextStyle = TextStyle(
  fontSize: 22,
  fontWeight: FontWeight.bold,
  letterSpacing: 0,
  color: Colors.white,
  shadows: _kClockShadows,
);

/// Apps opened from the top bar instead of the dock. Each shortcut opens the first of its
/// packages that is installed, and is hidden when none is. It shows [asset] when set, else the
/// app's own icon with [useAppIcon], else [icon] in the style of the settings and network icons.
const List<({List<String> packageNames, IconData icon, bool useAppIcon, String? asset, String label})>
    kTopBarShortcuts = [
  (packageNames: ['com.android.vending'], icon: Icons.shop_outlined, useAppIcon: false, asset: null, label: 'Play Store'),
  (
    packageNames: ['com.phlox.tvwebbrowser', 'com.tcl.browser'],
    icon: Icons.public,
    useAppIcon: false,
    asset: null,
    label: 'Browser',
  ),
  // VLC's own icon is the cone on an orange square; the bare cone matches the other top bar icons.
  (packageNames: ['org.videolan.vlc'], icon: Icons.dns_outlined, useAppIcon: false, asset: 'assets/vlc_cone.png', label: 'Router HDD'),
];

Widget _barIcon(IconData icon) => Icon(icon, size: _kTopBarIconSize, color: _kTopBarIconColor);

Widget _shortcutIcon(({List<String> packageNames, IconData icon, bool useAppIcon, String? asset, String label}) shortcut, App app) {
  final asset = shortcut.asset;
  if (asset != null) {
    // Tinted like the glyphs around it.
    return Image.asset(
      asset,
      width: _kTopBarIconSize,
      height: _kTopBarIconSize,
      color: _kTopBarIconColor,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.medium,
    );
  }
  if (shortcut.useAppIcon) {
    return _ShortcutIcon(packageName: app.packageName, fallback: shortcut.icon);
  }
  return _barIcon(shortcut.icon);
}

class _AppShortcuts extends StatelessWidget {
  const _AppShortcuts();

  @override
  Widget build(BuildContext context) {
    final apps = context.select<AppsService, List<App?>>(
      (service) => [
        for (final shortcut in kTopBarShortcuts)
          shortcut.packageNames.map(service.getApplication).firstWhereOrNull((app) => app != null),
      ],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, shortcut) in kTopBarShortcuts.indexed)
          if (apps[index] case final app?)
            Padding(
              padding: const EdgeInsets.only(right: _kTopBarRingGap),
              child: AppBarFocusRing(
                key: Key("top_bar_shortcut_${app.packageName}"),
                onPressed: () => context.read<AppsService>().launchApp(app),
                semanticLabel: shortcut.label,
                child: _shortcutIcon(shortcut, app),
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
  static const double _size = _kTopBarIconSize;
  late final Future<Uint8List> _icon = context.read<AppsService>().getAppIcon(widget.packageName);

  @override
  Widget build(BuildContext context) {
    final fallback = _barIcon(widget.fallback);
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
