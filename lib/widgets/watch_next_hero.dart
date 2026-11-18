/*
 * FLauncher
 * Copyright (C) 2021 Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';

import 'package:flauncher/actions.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/watch_next_item.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/watch_next_hero_metadata.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

void _playFocusSound(BuildContext context) {
  final settingsService = context.read<SettingsService>();
  if (settingsService.appKeyClickEnabled) {
    Feedback.forTap(context);
  } else {
    context.findRenderObject()?.sendSemanticsEvent(const TapSemanticEvent());
  }
}

/// The hero text starts on the content keyline (x = 48), like the top bar and the dock tiles.
const double _kWatchNextHeroHorizontalPadding = 48;

/// From the top of the service row to the bottom of the Watch button, with every row present
/// (y = 226 to 405 on a 540 dp tall screen). Rows that are missing leave space at the bottom
/// instead of moving the hero, so the dock below never shifts.
const double kWatchNextHeroHeight = 179;

const double _kWatchButtonHeight = 36;

/// Duration of the carousel change: the old item leaves in the first half, the new one arrives in
/// the second, for the text and the backdrop alike.
const kHeroCarouselDuration = Duration(milliseconds: 400);

/// +1 when the carousel moved to the next item (wrapping around), -1 for the previous one.
int carouselDirection(int from, int to, int count) {
  if (count <= 1 || from == to) return 1;
  if (to == (from + 1) % count) return 1;
  if (to == (from - 1 + count) % count) return -1;
  return to > from ? 1 : -1;
}

/// A slide by [distance] (a fraction of the child's width) and a fade. The incoming child comes
/// from the side of [direction]; the outgoing one leaves towards the other side.
///
/// Only the upper half of [animation] moves the child, so the two never show at once: an
/// AnimatedSwitcher runs the outgoing child from 1 down to 0 (gone by 0.5) while the incoming one
/// runs from 0 up to 1 (visible from 0.5).
Widget carouselTransition({
  required Widget child,
  required Animation<double> animation,
  required bool incoming,
  required int direction,
  double distance = 0.06,
  bool fadeEdges = false,
}) {
  final begin = Offset((incoming ? direction : -direction) * distance, 0);
  final curved = CurvedAnimation(parent: animation, curve: const Interval(0.5, 1, curve: Curves.easeOutCubic));
  final position = Tween(begin: begin, end: Offset.zero).animate(curved);
  final slid = SlideTransition(position: position, child: child);
  return FadeTransition(
    opacity: curved,
    child: fadeEdges
        ? AnimatedBuilder(
            animation: position,
            builder: (context, slid) => _TrailingEdgeFade(shift: position.value.dx, child: slid!),
            child: slid,
          )
        : slid,
  );
}

/// How far the trailing edge fades in, as a multiple of how far the child has slid.
const double kCarouselEdgeFadeFactor = 4;

/// Fades the edge a slid child leaves behind into whatever is under it, so a full-screen picture
/// moving sideways shows a soft edge instead of a hard band. Nothing is faded at rest.
///
/// The mask sits outside the slide, in the unmoved box: it stays clear over the strip the child
/// left and ramps up from the child's edge. Inside the slide, its edge would fall between pixels
/// and leave the child's first, partly covered column unmasked.
class _TrailingEdgeFade extends StatelessWidget {
  /// How far the child has slid, as a fraction of its width (positive: moved right).
  final double shift;
  final Widget child;

  const _TrailingEdgeFade({required this.shift, required this.child});

  @override
  Widget build(BuildContext context) {
    final gap = shift.abs().clamp(0.0, 0.5);
    final feather = (gap * kCarouselEdgeFadeFactor).clamp(0.0, 0.5);
    if (feather == 0) return child;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        // Moved right: the left edge is the one on screen.
        begin: shift > 0 ? Alignment.centerLeft : Alignment.centerRight,
        end: shift > 0 ? Alignment.centerRight : Alignment.centerLeft,
        colors: const [Color(0x00FFFFFF), Color(0x00FFFFFF), Color(0xFFFFFFFF)],
        stops: [0, gap, gap + feather],
      ).createShader(bounds),
      child: child,
    );
  }
}

class WatchNextHero extends StatefulWidget {
  final List<WatchNextItem> items;
  final bool isFirstSection;
  final bool handleUpNavigationToSettings;
  final VoidCallback? onItemFocused;

  const WatchNextHero({
    super.key,
    required this.items,
    this.isFirstSection = false,
    this.handleUpNavigationToSettings = false,
    this.onItemFocused,
  });

  @override
  State<WatchNextHero> createState() => _WatchNextHeroState();
}

class _WatchNextHeroState extends State<WatchNextHero> {
  bool _hasFocus = false;
  int? _lastIndex;
  int _direction = 1;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    final watchNextService = context.watch<WatchNextService>();
    final activeItem = watchNextService.activeHeroItem ?? items.first;
    final activeIndex = watchNextService.activeHeroIndex.clamp(0, items.length - 1);
    if (_lastIndex != null && _lastIndex != activeIndex) {
      _direction = carouselDirection(_lastIndex!, activeIndex, items.length);
    }
    _lastIndex = activeIndex;

    final appsService = context.watch<AppsService>();
    final app = activeItem.packageName != null ? appsService.getApplication(activeItem.packageName) : null;
    final appName = app?.name;
    final localizations = AppLocalizations.of(context)!;
    final sourceBadge = (appName != null ? localizations.watchNextOn : localizations.watchNextSectionTitle)
        .toUpperCase();
    final infoKey = ValueKey(activeItem.id);

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (_hasFocus != hasFocus) setState(() => _hasFocus = hasFocus);
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _kWatchNextHeroHorizontalPadding),
            child: SizedBox(
              height: kWatchNextHeroHeight,
              // Rows are anchored at the top and keep their natural height; a large font scale spills
              // past the box instead of failing layout.
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxHeight: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSize(
                      duration: kHeroCarouselDuration,
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topLeft,
                      child: AnimatedSwitcher(
                        duration: kHeroCarouselDuration,
                        layoutBuilder: (current, previous) =>
                            Stack(alignment: Alignment.topLeft, children: [...previous, if (current != null) current]),
                        transitionBuilder: (child, animation) => carouselTransition(
                          child: child,
                          animation: animation,
                          incoming: child.key == infoKey,
                          direction: _direction,
                        ),
                        child: _HeroInfo(
                          key: infoKey,
                          sourceBadge: sourceBadge,
                          sourcePackageName: app?.packageName,
                          sourceAppName: appName,
                          item: activeItem,
                        ),
                      ),
                    ),

                    // Watch button, and the carousel dots right-aligned on the x = 912 keyline.
                    SizedBox(
                      height: _kWatchButtonHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _HeroWatchButton(
                            item: activeItem,
                            autofocus: widget.isFirstSection,
                            handleUpNavigationToSettings: widget.handleUpNavigationToSettings,
                            onItemFocused: widget.onItemFocused,
                            onPrev: watchNextService.prevHeroItem,
                            onNext: watchNextService.nextHeroItem,
                            totalItems: items.length,
                          ),
                          const Spacer(),
                          if (items.length > 1)
                            _HeroPaginationIndicator(currentIndex: activeIndex, totalItems: items.length),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Only while the hero has focus and there is somewhere to go.
          if (_hasFocus && items.length > 1) ...[
            const Positioned(left: _kChevronInset, top: _kChevronTop, child: _HeroChevron(pointsLeft: true)),
            const Positioned(right: _kChevronInset, top: _kChevronTop, child: _HeroChevron(pointsLeft: false)),
          ],
        ],
      ),
    );
  }
}

/// Chevrons sit 14 dp from the screen edges, with their top at y = 250 (24 dp below the hero's top).
const double _kChevronInset = 14;
const double _kChevronTop = 24;
const double _kChevronSize = 28;

class _HeroChevron extends StatelessWidget {
  final bool pointsLeft;

  const _HeroChevron({required this.pointsLeft});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      key: Key(pointsLeft ? 'hero_chevron_left' : 'hero_chevron_right'),
      size: const Size.square(_kChevronSize),
      painter: _ChevronPainter(pointsLeft: pointsLeft),
    ),
  );
}

/// A thin open chevron, drawn on a 24-unit grid like the mockup's glyph.
class _ChevronPainter extends CustomPainter {
  final bool pointsLeft;

  const _ChevronPainter({required this.pointsLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 24;
    final path = pointsLeft
        ? (Path()
            ..moveTo(15 * unit, 4 * unit)
            ..lineTo(7 * unit, 12 * unit)
            ..lineTo(15 * unit, 20 * unit))
        : (Path()
            ..moveTo(9 * unit, 4 * unit)
            ..lineTo(17 * unit, 12 * unit)
            ..lineTo(9 * unit, 20 * unit));
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x80FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * unit
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter oldDelegate) => oldDelegate.pointsLeft != pointsLeft;
}

const _kBadgeTextStyle = TextStyle(
  color: Color(0xD9FFFFFF), // 85% white
  fontSize: 11,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.25,
);

const _kTitleTextStyle = TextStyle(
  color: Colors.white,
  fontSize: 36,
  fontWeight: FontWeight.w700,
  height: 1.1,
  letterSpacing: -0.25,
  shadows: [Shadow(color: Color(0x66000000), offset: Offset(0, 1), blurRadius: 6)],
);

// Line height and letter spacing are set here, so the theme's body text style (1.43 line height)
// does not push the Watch button out of the hero's fixed box. 1.17 is Roboto's own line height.
const _kMeta1TextStyle = TextStyle(
  color: Color(0xEBFFFFFF), // 92% white
  fontSize: 15,
  fontWeight: FontWeight.w500,
  height: 1.17,
  letterSpacing: 0,
);
const _kMeta2TextStyle = TextStyle(color: Color(0xA6FFFFFF), fontSize: 12, height: 1.17, letterSpacing: 0); // 65%

/// Service, title, metadata rows and progress. Missing rows are removed, and the rows below move
/// up. There is no synopsis.
class _HeroInfo extends StatelessWidget {
  final String sourceBadge;
  final String? sourcePackageName;
  final String? sourceAppName;
  final WatchNextItem item;

  const _HeroInfo({
    super.key,
    required this.sourceBadge,
    this.sourcePackageName,
    this.sourceAppName,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final meta = heroMetadata(item, AppLocalizations.of(context)!);
    final metaRows = [
      if (meta.line1 case final line1?)
        Text(
          line1,
          key: const Key('hero_meta_1'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _kMeta1TextStyle,
        ),
      if (meta.line2 case final line2?)
        Text(
          line2,
          key: const Key('hero_meta_2'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _kMeta2TextStyle,
        ),
    ];
    final progressPercent = item.progressPercent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Service: plain text and logo; no border or fill, so it does not look focusable.
        // Fixed height, so items with a logo and items with only text line up the same.
        SizedBox(
          key: const Key('hero_service_row'),
          height: 18,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(sourceBadge, maxLines: 1, style: _kBadgeTextStyle),
              if (sourcePackageName != null)
                _SourceAppIcon(packageName: sourcePackageName!, appName: sourceAppName ?? ''),
            ],
          ),
        ),
        const SizedBox(height: 11),

        Text(
          item.title,
          key: const Key('hero_title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _kTitleTextStyle,
        ),

        // Text line heights round to whole dp (title 40, rows 18 and 14), so these gaps put the rows at
        // y = 306 and 328, the progress bar at 353 and the Watch button at 369.
        for (final (index, row) in metaRows.indexed) ...[SizedBox(height: index == 0 ? 11 : 4), row],

        const SizedBox(height: 11),
        // Only when the app reported a playback position.
        if (progressPercent != null) ...[
          Container(
            key: const Key('hero_progress'),
            width: 160,
            height: 2,
            decoration: BoxDecoration(color: const Color(0x4DFFFFFF), borderRadius: BorderRadius.circular(1)),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (progressPercent / 100).clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(1)),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _HeroWatchButton extends StatefulWidget {
  final WatchNextItem item;
  final bool autofocus;
  final bool handleUpNavigationToSettings;
  final VoidCallback? onItemFocused;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final int totalItems;

  const _HeroWatchButton({
    required this.item,
    required this.autofocus,
    required this.handleUpNavigationToSettings,
    this.onItemFocused,
    required this.onPrev,
    required this.onNext,
    required this.totalItems,
  });

  @override
  State<_HeroWatchButton> createState() => _HeroWatchButtonState();
}

class _HeroWatchButtonState extends State<_HeroWatchButton> {
  final FocusNode _focusNode = FocusNode();
  bool _isHovered = false;
  bool _clicked = false;
  Timer? _launchTimer;
  Timer? _resetTimer;

  @override
  void initState() {
    super.initState();
    _isHovered = widget.autofocus;
  }

  @override
  void dispose() {
    _launchTimer?.cancel();
    _resetTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _triggerLaunchWithFeedback() {
    if (_clicked) return;
    setState(() => _clicked = true);
    _playFocusSound(context);
    _launchTimer?.cancel();
    _launchTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      context.read<WatchNextService>().launchItem(widget.item);
      _resetTimer?.cancel();
      _resetTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() => _clicked = false);
        }
      });
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowLeft:
          if (widget.totalItems > 1) {
            widget.onPrev();
            _playFocusSound(context);
            return KeyEventResult.handled;
          }
          break;
        case LogicalKeyboardKey.arrowRight:
          if (widget.totalItems > 1) {
            widget.onNext();
            _playFocusSound(context);
            return KeyEventResult.handled;
          }
          break;
        case LogicalKeyboardKey.arrowUp:
          if (widget.handleUpNavigationToSettings) {
            Actions.invoke(context, const MoveFocusToSettingsIntent());
            return KeyEventResult.handled;
          }
          break;
        case LogicalKeyboardKey.select:
        case LogicalKeyboardKey.enter:
          _triggerLaunchWithFeedback();
          return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context)!.watchNextWatch;
    final foreground = _isHovered ? Colors.black : Colors.white;
    final double scale = _clicked ? 0.96 : 1.0;

    return RepaintBoundary(
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onKeyEvent: _handleKeyEvent,
        onFocusChange: (focused) {
          if (_isHovered == focused) return;
          setState(() => _isHovered = focused);
          if (focused) {
            _playFocusSound(context);
            widget.onItemFocused?.call();
          }
        },
        child: GestureDetector(
          onTap: _triggerLaunchWithFeedback,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: _kWatchButtonHeight,
              alignment: Alignment.center,
              padding: const EdgeInsets.only(left: 18, right: 22),
              decoration: ShapeDecoration(
                // Focused: solid white. Unfocused: 18% white with a 40% white border.
                shape: StadiumBorder(
                  side: BorderSide(color: _isHovered ? Colors.white : const Color(0x66FFFFFF), width: 1),
                ),
                color: _isHovered ? Colors.white : const Color(0x2EFFFFFF),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow_rounded, size: 15, color: foreground),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0, color: foreground),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroPaginationIndicator extends StatelessWidget {
  final int currentIndex;
  final int totalItems;

  const _HeroPaginationIndicator({required this.currentIndex, required this.totalItems});

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('hero_dots'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(totalItems, (i) {
        final isActive = i == currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          // 6 dp apart; the last dot ends on the keyline.
          margin: EdgeInsets.only(left: i == 0 ? 0 : 6),
          width: isActive ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive ? Colors.white : const Color(0x80FFFFFF),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

/// The source app's icon after "WATCH NEXT ON", or its name when the app has no icon to show.
class _SourceAppIcon extends StatefulWidget {
  final String packageName;
  final String appName;

  const _SourceAppIcon({required this.packageName, required this.appName});

  @override
  State<_SourceAppIcon> createState() => _SourceAppIconState();
}

/// White logos for apps whose own icon has its background baked in.
const Map<String, ({String asset, double height})> kSourceAppLogoAssets = {
  'com.netflix.ninja': (asset: 'assets/logo_netflix.png', height: 15),
  // The HBO and SkyShowtime wordmarks are wide and heavy, so they read larger than the others at
  // the same height.
  'com.wbd.stream': (asset: 'assets/logo_hbo.png', height: 13),
  'com.google.android.youtube.tv': (asset: 'assets/logo_youtube.png', height: 18),
  'com.apple.atve.androidtv.appletv': (asset: 'assets/logo_appletv.png', height: 18),
  'com.skyshowtime.skyshowtime.google': (asset: 'assets/logo_skyshowtime.png', height: 14),
};

class _SourceAppIconState extends State<_SourceAppIcon> {
  static const double _height = 18;
  static const double _maxWidth = 80;
  Future<Uint8List>? _icon;

  @override
  void initState() {
    super.initState();
    _loadIcon();
  }

  @override
  void didUpdateWidget(_SourceAppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageName != widget.packageName) {
      _loadIcon();
    }
  }

  void _loadIcon() {
    _icon = kSourceAppLogoAssets.containsKey(widget.packageName)
        ? null
        : context.read<AppsService>().getAppIconForeground(widget.packageName);
  }

  Widget _name() => Text(' ${widget.appName.toUpperCase()}', maxLines: 1, style: _kBadgeTextStyle);

  Widget _logo(Widget image) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(width: 7),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth, maxHeight: _height),
        child: image,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final logo = kSourceAppLogoAssets[widget.packageName];
    if (logo != null) {
      return _logo(
        Image.asset(
          logo.asset,
          key: ValueKey(logo.asset),
          height: logo.height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => _name(),
        ),
      );
    }
    return FutureBuilder<Uint8List>(
      future: _icon,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(width: _height + 7, height: _height);
        }
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _name();
        }
        return _logo(
          Image.memory(
            bytes,
            key: ValueKey(widget.packageName),
            height: _height,
            fit: BoxFit.contain,
            // Drawn in white like the bundled logos; the icon layer is transparent around the logo.
            color: Colors.white,
            colorBlendMode: BlendMode.srcIn,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _name(),
          ),
        );
      },
    );
  }
}
