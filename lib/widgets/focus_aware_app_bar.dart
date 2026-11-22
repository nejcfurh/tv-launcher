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
import 'vlc_cone_icon.dart';

class FocusAwareAppBar extends StatefulWidget implements PreferredSizeWidget
{
  const FocusAwareAppBar({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return FocusAwareAppBarState();
  }

  @override
  Size get preferredSize => const Size.fromHeight(kTopBarHeight);
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
                  height: isVisible ? kTopBarHeight : 0,
                  child: OverflowBox(
                    minHeight: 0,
                    maxHeight: kTopBarHeight,
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
          toolbarHeight: kTopBarHeight,
          // The first glyph starts on the content keyline (x = 48); its glass circle reaches
          // [kAppBarGlassPadding] further left.
          titleSpacing: kTopBarKeyline - _kTopBarIconPadding,
          // Left side: Settings, WiFi usage, app shortcuts
          title: SizedBox(
            height: kTopBarHeight,
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
            padding: const EdgeInsets.only(top: _kTopBarContentTop),
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
            ),
          ),
          // Right side: time, with network status and date under it
          actions: [
            SizedBox(
              height: kTopBarHeight,
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
              padding: const EdgeInsets.only(left: 16, right: kTopBarKeyline, top: _kTopBarContentTop),
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
                  final dateLine = [
                    // Status only: not focusable; Wi-Fi settings stay reachable through Settings.
                    if (dateTimeSettings.showNetwork)
                      const NetworkWidget(
                        key: Key("statusbar_network"),
                        size: 15,
                        color: Color(0xB3FFFFFF), // 70% white
                        padding: EdgeInsets.zero,
                        shadows: [Shadow(color: Color(0x99000000), offset: Offset(0, 1), blurRadius: 2)],
                      ),
                    if (dateTimeSettings.showNetwork && showDate) const SizedBox(width: 8),
                    if (showDate)
                      DateTimeWidget(
                        dateTimeSettings.dateFormat,
                        key: const Key("statusbar_date"),
                        updateInterval: const Duration(minutes: 1),
                        textStyle: _kDateTextStyle,
                      ),
                  ];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (showTime)
                        DateTimeWidget(
                          dateTimeSettings.timeFormat,
                          key: const Key("statusbar_clock"),
                          updateInterval: const Duration(minutes: 1),
                          textStyle: _kTimeTextStyle,
                        ),
                      if (showTime && dateLine.isNotEmpty) const SizedBox(height: _kClockLineGap),
                      if (dateLine.isNotEmpty)
                        Row(mainAxisSize: MainAxisSize.min, children: dateLine),
                    ],
                  );
                },
              ),
                ),
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

/// Height of the top bar: the two-line clock (time, then date) needs more than a toolbar.
const kTopBarHeight = 80.0;

/// Top of the button circles and of the time line; both are [_kTopBarControlHeight] tall, so they
/// centre at y = 32.
const _kTopBarContentTop = 10.0;

/// The time's font size, and the diameter of the button circles beside it.
const _kTopBarControlHeight = 44.0;

/// Between the time and the date line under it.
const _kClockLineGap = 2.0;

const _kTopBarIconSize = 20.0;
const _kTopBarIconPadding = kAppBarGlassPadding;

/// 12 dp between the glass circles.
const _kTopBarRingGap = 12.0;

const Color _kTopBarIconColor = Color(0xCCFFFFFF); // 80% white

/// Shadow on the characters only; there is no dark area behind the date and time.
const List<Shadow> _kClockShadows = [
  Shadow(color: Color(0x99000000), offset: Offset(0, 1), blurRadius: 3),
  Shadow(color: Color(0x80000000), blurRadius: 1),
];

const TextStyle _kDateTextStyle = TextStyle(
  fontSize: 16,
  height: 1.2,
  fontWeight: FontWeight.w400,
  letterSpacing: 0,
  color: Color(0xBFFFFFFF), // 75% white
  shadows: _kClockShadows,
);

const TextStyle _kTimeTextStyle = TextStyle(
  fontSize: _kTopBarControlHeight,
  height: 1.0,
  fontWeight: FontWeight.bold,
  letterSpacing: 0,
  color: Colors.white,
  shadows: _kClockShadows,
);

/// Apps opened from the top bar instead of the dock. Each shortcut opens the first of its
/// packages that is installed, and is hidden when none is. It shows [glyph] when set, else the
/// app's own icon in grayscale with [useAppIcon], else [icon] in the style of the settings and
/// network icons.
typedef TopBarShortcut = ({List<String> packageNames, IconData icon, bool useAppIcon, Widget? glyph, String label});

const List<TopBarShortcut> kTopBarShortcuts = [
  (packageNames: ['com.android.vending'], icon: Icons.shop_outlined, useAppIcon: true, glyph: null, label: 'Play Store'),
  (
    packageNames: ['com.phlox.tvwebbrowser', 'com.tcl.browser'],
    icon: Icons.public,
    useAppIcon: false,
    glyph: null,
    label: 'Browser',
  ),
  (
    packageNames: ['org.videolan.vlc'],
    icon: Icons.dns_outlined,
    useAppIcon: false,
    glyph: VlcConeIcon(size: _kTopBarIconSize, color: _kTopBarIconColor),
    label: 'Router HDD',
  ),
];

/// Rec. 709 luma weights: app icons keep their shapes and shading but lose their colour, so they
/// sit with the white glyphs around them.
const ColorFilter kTopBarGrayscale = ColorFilter.matrix([
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
]);

Widget _barIcon(IconData icon) => Icon(icon, size: _kTopBarIconSize, color: _kTopBarIconColor);

Widget _shortcutIcon(TopBarShortcut shortcut, App app) {
  final glyph = shortcut.glyph;
  if (glyph != null) return glyph;
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

/// The app's own launcher icon in grayscale, or [fallback] while it loads or when the app has none.
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
          return ColorFiltered(
            colorFilter: kTopBarGrayscale,
            child: Image.memory(
              bytes,
              width: _size,
              height: _size,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => Center(child: fallback),
            ),
          );
        },
      ),
    );
  }
}
