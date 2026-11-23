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
import 'dart:math';

import 'package:flauncher/actions.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/app_image_type.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/app_card_contour_painter.dart';
import 'package:flauncher/widgets/application_info_panel.dart';
import 'package:flauncher/widgets/dock_band.dart';
import 'package:flauncher/widgets/dock_focus_ring.dart';
import 'package:flauncher/widgets/focus_aware_app_bar.dart';
import 'package:flauncher/widgets/focus_keyboard_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app.dart';
import '../models/category.dart';

const _validationKeys = [LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.gameButtonA];

const kAppCardAspectRatio = 16 / 9;
const kAppCardHorizontalPadding = 12.0;
const kAppCardVerticalPadding = 9.0;
const kLauncherSectionHorizontalPadding = 24.0;
const kAppNameLabelHeight = 24.0;

/// Grid tiles decode their picture at this width; they are drawn up to about this wide.
const kGridAppImageDecodeWidth = 480;

/// Width, in pixels, to decode a tile's picture at: what the tile shows at its largest. A dock
/// tile is at most [kDockTileMaxWidth] wide and grows by [kDockTileFocusedScale] when focused.
int appImageDecodeWidth(BuildContext context, {required bool dockTile}) {
  if (!dockTile) return kGridAppImageDecodeWidth;
  final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
  return min(kGridAppImageDecodeWidth, (kDockTileMaxWidth * kDockTileFocusedScale * dpr).ceil());
}

/// How long the loading placeholder takes to fade off a tile once its picture is ready.
const kAppImageFadeDuration = Duration(milliseconds: 150);

/// Row extent for a grid/dock line given the content width between section paddings.
double appCardRowExtentFromContentWidth(double contentWidth, {int columnCount = Category.ColumnsCount}) {
  final slotWidth = contentWidth / columnCount;
  return slotWidth / kAppCardAspectRatio;
}

/// Adjusted aspect ratio for grid cells that includes space for the app name label.
double appCardGridAspectRatio(double crossAxisExtent, int columnsCount) {
  final cellWidth = crossAxisExtent / columnsCount;
  return cellWidth / (cellWidth / kAppCardAspectRatio + kAppNameLabelHeight);
}

class AppCard extends StatefulWidget {
  final App application;
  final Category category;
  final bool autofocus;
  final void Function(AxisDirection) onMove;
  final VoidCallback onMoveEnd;
  final bool handleUpNavigationToSettings;
  final double scrollAlignment;
  final bool enforceAspectRatio;
  final VoidCallback? onFocused;
  final bool ensureVisibleOnFocus;
  final bool onlyScrollWhenNearBottom;

  /// Dock look: no app names, a white ring outside the focused tile instead of the accent contour,
  /// and no dimming of unfocused tiles.
  final bool dockTile;

  /// Set for a tile in the dock band ([DockBand]): a parallelogram leaning by this many dp, its
  /// name underneath, larger when focused and muted otherwise.
  final double? bandSlant;

  const AppCard({
    super.key,
    required this.application,
    required this.category,
    required this.autofocus,
    required this.onMove,
    required this.onMoveEnd,
    this.handleUpNavigationToSettings = false,
    this.scrollAlignment = 0.5,
    this.enforceAspectRatio = true,
    this.onFocused,
    this.ensureVisibleOnFocus = true,
    this.onlyScrollWhenNearBottom = false,
    this.dockTile = false,
    this.bandSlant,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> with SingleTickerProviderStateMixin {
  bool _moving = false;
  bool _clicked = false;
  bool _isFocused = false;
  bool _isTraditionalHighlightMode = false;
  bool _isHighlightAnimating = false;
  bool _animationEnabled = false;
  String? _accentColorHex;
  Color _accentColor = const Color(0xFF000000);
  DateTime? _lastMoveAt;
  DateTime? _lastEnsureVisibleAt;
  late FocusNode _focusNode;

  (AppImageType, ImageProvider)? _loadedImage;
  bool _imageLoadError = false;
  bool _darkDockArt = false;

  late final AnimationController _animation;

  late final CurvedAnimation _curvedAnimation;
  static const double _focusedScale = 1.07;
  static const Duration _focusAnimationDuration = Duration(milliseconds: 180);

  /// Odd, so the last run ends bright; 3 × 1.2 s.
  static const int _highlightPulseRuns = 3;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _curvedAnimation = CurvedAnimation(parent: _animation, curve: Curves.easeInOut);
    _focusNode = FocusNode();
    _isTraditionalHighlightMode = FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    FocusManager.instance.addHighlightModeListener(_focusHighlightModeChanged);
    _loadAppImage(Provider.of<AppsService>(context, listen: false));

    // Check if we need to restore focus/reorder mode after a move
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appsService = Provider.of<AppsService>(context, listen: false);
      if (appsService.pendingReorderFocusPackage == widget.application.packageName &&
          appsService.pendingReorderFocusCategoryId == widget.category.id) {
        appsService.clearPendingReorderFocusPackage();
        _focusNode.requestFocus();

        setState(() {
          _moving = true;
        });
      }
    });
  }

  @override
  void didUpdateWidget(AppCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final appsService = Provider.of<AppsService>(context, listen: false);

    if (oldWidget.application.packageName != widget.application.packageName) {
      _loadedImage = null;
      _imageLoadError = false;
      _loadAppImage(appsService);
    } else if (appsService.consumeDirtyImage(widget.application.packageName)) {
      _loadAppImage(appsService);
    }

    // Check for pending focus on update as well
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appsService = Provider.of<AppsService>(context, listen: false);
      if (appsService.pendingReorderFocusPackage == widget.application.packageName &&
          appsService.pendingReorderFocusCategoryId == widget.category.id) {
        appsService.clearPendingReorderFocusPackage();
        _focusNode.requestFocus();

        if (!_moving) {
          setState(() {
            _moving = true;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_focusHighlightModeChanged);
    _curvedAnimation.dispose();
    _animation.dispose();
    _focusNode.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (bool showAppNames, bool appNamesOnFocusOnly, double cornerRadius, String displayName) =
        context.select<SettingsService, (bool, bool, double, String)>(
      (s) => (
        s.showAppNamesBelowIcons,
        s.appNamesOnFocusOnly,
        s.cardCornerRadius,
        s.customAppLabel(widget.application.packageName) ?? widget.application.name,
      ),
    );
    final (bool animationEnabled, String accentColorHex, bool showFocusBorders, double borderThickness) = context.select<SettingsService, (bool, String, bool, double)>(
      (s) => (s.appHighlightAnimationEnabled, s.accentColorHex, s.showFocusBorders, s.focusBorderThickness),
    );
    if (accentColorHex != _accentColorHex) {
      _accentColorHex = accentColorHex;
      _accentColor = Color(int.parse('FF$accentColorHex', radix: 16));
    }
    if (animationEnabled != _animationEnabled) {
      _animationEnabled = animationEnabled;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateHighlightAnimation();
      });
    }
    if (widget.bandSlant case final slant?) {
      return _bandTile(displayName, slant);
    }
    final appImageWidget = _appImage(displayName);
    final bool shouldHighlight = _shouldHighlight();
    final bool dock = widget.dockTile;

    return FocusKeyboardListener(
      onPressed: _onPressed,
      onLongPress: _onLongPress,
      child: AnimatedScale(
        scale: _clicked ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _clicked ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: _wrapAspectRatio(
                  RepaintBoundary(
                    child: AnimatedScale(
                      scale: !_moving && shouldHighlight ? (dock ? kDockTileFocusedScale : _focusedScale) : 1.0,
                      duration: dock ? kDockFocusDuration : _focusAnimationDuration,
                      alignment: Alignment.center,
                      curve: dock ? Curves.easeOut : Curves.easeOutCubic,
                      child: Stack(
                        fit: StackFit.expand,
                        clipBehavior: Clip.none,
                        children: [
                          if (dock) DockTileShadow(tileRadius: cornerRadius, visible: shouldHighlight && !_moving),
                          Material(
                            borderRadius: BorderRadius.circular(cornerRadius),
                            clipBehavior: Clip.antiAlias,
                            elevation: dock ? 0 : (shouldHighlight ? 7 : 4),
                            shadowColor: Colors.black,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                InkWell(
                                  focusNode: _focusNode,
                                  autofocus: widget.autofocus,
                                  focusColor: Colors.transparent,
                                  child: appImageWidget,
                                  onTap: () => _onPressed(LogicalKeyboardKey.enter),
                                  onLongPress: () => _onLongPress(LogicalKeyboardKey.enter),
                                  onFocusChange: (focused) {
                                    _handleFocusChange(context, focused);
                                  },
                                ),
                                _loadingCover(),
                                if (_moving) ..._arrows(),
                                if (dock)
                                  DockTileInnerBorder(tileRadius: cornerRadius, dark: _darkDockArt)
                                else
                                  IgnorePointer(
                                    child: AnimatedOpacity(
                                      duration: _focusAnimationDuration,
                                      curve: Curves.easeInOut,
                                      opacity: shouldHighlight ? 0.0 : 1.0,
                                      child: const ColoredBox(color: Color(0x1A000000)),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (dock && showFocusBorders)
                            DockFocusRing(tileRadius: cornerRadius, visible: shouldHighlight && !_moving),
                          if ((!dock && shouldHighlight && showFocusBorders) || _moving)
                            if (animationEnabled && !_moving)
                              IgnorePointer(
                                child: RepaintBoundary(
                                  child: AnimatedBuilder(
                                    animation: _curvedAnimation,
                                    builder: (context, _) {
                                      final alpha = 0.65 + (_animation.value * 0.35);
                                      return _HighlightOutline(
                                        accentColor: _accentColor,
                                        radius: cornerRadius,
                                        alpha: alpha,
                                        strokeWidth: borderThickness,
                                      );
                                    },
                                  ),
                                ),
                              )
                            else
                              IgnorePointer(
                                child: RepaintBoundary(
                                  child: _HighlightOutline(
                                    accentColor: _accentColor,
                                    radius: cornerRadius,
                                    isMoving: _moving,
                                    strokeWidth: borderThickness,
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                ),
                ),
              ),
              // Hidden labels keep their space so rows don't jump when focus moves.
              if (showAppNames && !dock)
                AnimatedOpacity(
                  opacity: !appNamesOnFocusOnly || shouldHighlight ? 1.0 : 0.0,
                  duration: _focusAnimationDuration,
                  curve: Curves.easeInOut,
                  child: Padding(padding: const EdgeInsets.only(top: 8.0), child: _AppNameLabel(name: displayName)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadAppImage(AppsService service) async {
    try {
      Uint8List bytes = Uint8List(0);

      bytes = await service.getAppBanner(widget.application.packageName);
      AppImageType type = AppImageType.Banner;
      if (bytes.isEmpty) {
        type = AppImageType.Icon;
        bytes = await service.getAppIcon(widget.application.packageName);
      }
      if (!mounted) return;
      final image = ResizeImage(MemoryImage(bytes), width: appImageDecodeWidth(context, dockTile: widget.dockTile));
      // Decoded before it is shown, so the tile never sits empty between the placeholder and it. A
      // decode that hangs only delays the picture; the placeholder still goes.
      if (mounted) {
        await precacheImage(image, context).timeout(const Duration(seconds: 2), onTimeout: () {});
      }
      final dark = widget.dockTile && widget.bandSlant == null && mounted
          ? await isDarkTileImage(image, createLocalImageConfiguration(context)) ?? false
          : false;
      if (mounted) {
        setState(() {
          _loadedImage = (type, image);
          _darkDockArt = dark;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _imageLoadError = true);
      }
    }
  }

  Widget _wrapAspectRatio(Widget child) {
    if (widget.enforceAspectRatio) {
      return AspectRatio(aspectRatio: kAppCardAspectRatio, child: child);
    }
    return child;
  }

  Widget _bandTile(String displayName, double slant) {
    final focused = _shouldHighlight() && !_moving;
    return FocusKeyboardListener(
      onPressed: _onPressed,
      onLongPress: _onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: kBandTileHeight,
            child: AnimatedScale(
              scale: _clicked ? 0.95 : (focused ? kBandFocusedScale : 1.0),
              duration: kBandFocusDuration,
              curve: Curves.easeOut,
              child: BandTileFace(
                image: _loadedImage?.$2,
                focused: focused || _moving,
                slant: slant,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    focusNode: _focusNode,
                    autofocus: widget.autofocus,
                    focusColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    onTap: () => _onPressed(LogicalKeyboardKey.enter),
                    onLongPress: () => _onLongPress(LogicalKeyboardKey.enter),
                    onFocusChange: (focused) => _handleFocusChange(context, focused),
                    child: Stack(fit: StackFit.expand, children: [if (_moving) ..._arrows()]),
                  ),
                ),
              ),
            ),
          ),
          // Under the parallelogram's bottom edge, which ends [slant] short of the box's right.
          AnimatedPadding(
            padding: EdgeInsets.only(top: focused ? kBandLabelGap + 4 : kBandLabelGap, right: slant),
            duration: kBandFocusDuration,
            curve: Curves.easeOut,
            child: Text(
              displayName,
              key: Key('band_label_${widget.application.packageName}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.2,
                fontWeight: focused ? FontWeight.w500 : FontWeight.w400,
                color: focused ? Colors.white : const Color(0xBFFFFFFF),
                shadows: const [Shadow(color: Color(0x99000000), offset: Offset(0, 1), blurRadius: 3)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _appImage(String displayName) {

    if (_loadedImage != null) {
      final (type, image) = _loadedImage!;
      if (type == AppImageType.Banner) {
        return Ink.image(image: image, fit: BoxFit.cover);
      } else {
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(flex: 2, child: Ink.image(image: image, height: double.maxFinite)),
              Flexible(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    displayName,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 3,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    } else if (_imageLoadError) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Text(
            displayName,
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
            maxLines: 3,
          ),
        ),
      );
    } else {
      return const SizedBox.expand();
    }
  }

  /// Covers the tile while its picture loads, then fades out over it and leaves the tree.
  Widget _loadingCover() {
    final loading = _loadedImage == null && !_imageLoadError;
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: kAppImageFadeDuration,
        switchOutCurve: Curves.easeOut,
        child: !loading
            ? const SizedBox.shrink()
            : ColoredBox(
                key: const Key('app_card_loading_cover'),
                color: Theme.of(context).canvasColor,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 8),
                          Text(AppLocalizations.of(context)!.loading),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  void _focusHighlightModeChanged(FocusHighlightMode mode) {
    final nextMode = mode == FocusHighlightMode.traditional;
    if (nextMode == _isTraditionalHighlightMode) {
      return;
    }
    setState(() {
      _isTraditionalHighlightMode = nextMode;
    });
    _updateHighlightAnimation();
  }

  bool _shouldHighlight() {
    return _isTraditionalHighlightMode && _isFocused;
  }

  void _handleFocusChange(BuildContext context, bool focused) {
    if (_isFocused != focused) {
      setState(() {
        _isFocused = focused;
      });
    }
    _updateHighlightAnimation();

    if (!focused) {
      return;
    }

    final now = DateTime.now();
    if (_lastEnsureVisibleAt != null && now.difference(_lastEnsureVisibleAt!).inMilliseconds < 120) {
      return;
    }
    _lastEnsureVisibleAt = now;
    if (widget.ensureVisibleOnFocus) {
      _ensureVisibleIfNeeded(
        context,
        // This specific alignment value is not only
        // to center the focused card in the row while
        // scrolling, but to prevent the topmost category
        // title to be hidden by the content above it when
        // scrolling from the app bar. How it relates to this,
        // I don't know
        alignment: widget.scrollAlignment,
        onlyWhenNearBottom: widget.onlyScrollWhenNearBottom,
      );
    }
    widget.onFocused?.call();
  }

  void _updateHighlightAnimation() {
    // The dock ring does not pulse, so a dock tile would only tick the controller for nothing.
    _setHighlightAnimation(_shouldHighlight() && _animationEnabled && !widget.dockTile);
  }

  void _setHighlightAnimation(bool shouldAnimate) {
    if (_isHighlightAnimating == shouldAnimate) {
      return;
    }
    _isHighlightAnimating = shouldAnimate;
    if (shouldAnimate) {
      // A few pulses, then a steady outline: a pulse left running keeps the renderer busy for as
      // long as the tile has focus (upstream arclauncher #98 measured 45% of a core).
      _animation.repeat(reverse: true, count: _highlightPulseRuns).then((_) {
        if (mounted && _isHighlightAnimating) _animation.value = 1.0;
      }, onError: (_) {});
    } else {
      _animation.stop();
    }
  }

  void _ensureVisibleIfNeeded(BuildContext context, {required double alignment, bool onlyWhenNearBottom = false}) {
    final renderObject = context.findRenderObject();
    final scrollable = Scrollable.maybeOf(context);
    if (renderObject == null || scrollable == null) {
      return;
    }

    final viewport = RenderAbstractViewport.of(renderObject);

    final position = scrollable.position;
    const minDeltaToScroll = 24.0;
    if (onlyWhenNearBottom &&
        (position.axisDirection == AxisDirection.down || position.axisDirection == AxisDirection.up)) {
      const topEdgePadding = kTopBarHeight + 24.0;
      const bottomEdgePadding = 96.0;
      final topTargetOffset = (viewport.getOffsetToReveal(renderObject, 0).offset - topEdgePadding).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (position.pixels - topTargetOffset >= minDeltaToScroll) {
        position.animateTo(
          topTargetOffset,
          curve: Curves.easeInOut,
          duration: const Duration(milliseconds: 220),
        );
        return;
      }

      final bottomTargetOffset = (viewport.getOffsetToReveal(renderObject, 1).offset + bottomEdgePadding).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (bottomTargetOffset - position.pixels < minDeltaToScroll) {
        return;
      }

      position.animateTo(
        bottomTargetOffset,
        curve: Curves.easeInOut,
        duration: const Duration(milliseconds: 220),
      );
      return;
    }

    final targetOffset = viewport.getOffsetToReveal(renderObject, alignment).offset;
    if ((targetOffset - position.pixels).abs() < minDeltaToScroll) {
      return;
    }

    Scrollable.ensureVisible(
      context,
      alignment: alignment,
      curve: Curves.easeInOut,
      duration: const Duration(milliseconds: 220),
    );
  }

  List<Widget> _arrows() {
    final arrows = <Widget>[
      _arrow(Alignment.centerLeft, Icons.keyboard_arrow_left, () {
        widget.onMove(AxisDirection.left);
      }),
      _arrow(Alignment.centerRight, Icons.keyboard_arrow_right, () {
        widget.onMove(AxisDirection.right);
      }),
    ];

    // Only show Up/Down arrows for grid layouts
    if (widget.category.type == CategoryType.grid) {
      arrows.add(
        _arrow(Alignment.topCenter, Icons.keyboard_arrow_up, () {
          widget.onMove(AxisDirection.up);
        }),
      );
      arrows.add(
        _arrow(Alignment.bottomCenter, Icons.keyboard_arrow_down, () {
          widget.onMove(AxisDirection.down);
        }),
      );
    }

    return arrows;
  }

  Widget _arrow(Alignment alignment, IconData icon, VoidCallback onTap) => Align(
    alignment: alignment,
    child: Ink(
      decoration: ShapeDecoration(color: Theme.of(context).primaryColor.withValues(alpha: 0.8), shape: CircleBorder()),
      child: SizedBox(
        height: 36,
        width: 36,
        child: IconButton(icon: Icon(icon, size: 24), onPressed: onTap, padding: EdgeInsets.all(0)),
      ),
    ),
  );

  KeyEventResult _onPressed(LogicalKeyboardKey? key) {
    if (_moving) {
      if (_validationKeys.contains(key) || key == LogicalKeyboardKey.escape) {
        _lastMoveAt = null;
        setState(() => _moving = false);
        widget.onMoveEnd();
      } else {
        final now = DateTime.now();
        if (_lastMoveAt != null && now.difference(_lastMoveAt!).inMilliseconds < 60) {
          return KeyEventResult.handled;
        }

        if (key == LogicalKeyboardKey.arrowLeft) {
          widget.onMove(AxisDirection.left);
        } else if (key == LogicalKeyboardKey.arrowUp) {
          widget.onMove(AxisDirection.up);
        } else if (key == LogicalKeyboardKey.arrowRight) {
          widget.onMove(AxisDirection.right);
        } else if (key == LogicalKeyboardKey.arrowDown) {
          widget.onMove(AxisDirection.down);
        } else {
          return KeyEventResult.ignored;
        }

        _lastMoveAt = now;
        final nowForScroll = DateTime.now();
        if (_lastEnsureVisibleAt == null || nowForScroll.difference(_lastEnsureVisibleAt!).inMilliseconds >= 120) {
          _lastEnsureVisibleAt = nowForScroll;
          WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisibleIfNeeded(context, alignment: 0.1));
        }
      }

      return KeyEventResult.handled;
    } else if (_validationKeys.contains(key)) {
      if (!_clicked) {
        setState(() => _clicked = true);
        // Launch right away; the press animation plays while the app opens.
        context.read<AppsService>().launchApp(widget.application);
        // Reset after a short delay so it looks normal when user returns
        Future.delayed(const Duration(milliseconds: 650), () {
          if (mounted) {
            setState(() => _clicked = false);
          }
        });
      }
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowUp && widget.handleUpNavigationToSettings) {
      Actions.invoke(context, const MoveFocusToSettingsIntent());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onLongPress(LogicalKeyboardKey? key) {
    if (!_moving && (key == null || longPressableKeys.contains(key))) {
      _showPanel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _showPanel() async {
    final result = await showDialog<ApplicationInfoPanelResult>(
      context: context,
      builder: (context) => ApplicationInfoPanel(category: widget.category, application: widget.application),
    );
    if (result == ApplicationInfoPanelResult.reorderApp) {
      setState(() => _moving = true);
    }
  }
}

class _AppNameLabel extends StatelessWidget {
  final String name;

  const _AppNameLabel({required this.name});

  @override
  Widget build(BuildContext context) {
    return Text(
      name,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      textAlign: TextAlign.center,
    );
  }
}

class _HighlightOutline extends StatelessWidget {
  final Color accentColor;
  final double radius;
  final double alpha;
  final bool isMoving;
  final double strokeWidth;

  const _HighlightOutline({
    required this.accentColor,
    required this.radius,
    this.alpha = 1.0,
    this.isMoving = false,
    this.strokeWidth = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: AppCardContourPainter(
        radius: radius,
        strokeWidth: isMoving ? max(2.0, strokeWidth + 0.5) : strokeWidth,
        accentColor: accentColor,
        alpha: alpha,
        isMoving: isMoving,
      ),
      child: const SizedBox.expand(),
    );
  }
}
