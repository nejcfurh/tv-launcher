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
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flauncher/build_flags.dart';
import 'package:flauncher/actions.dart';
import 'package:flauncher/custom_traversal_policy.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/app_card.dart';
import 'package:flauncher/widgets/cached_blur_backdrop.dart';
import 'package:flauncher/widgets/category_clean_row.dart';
import 'package:flauncher/widgets/category_row.dart';
import 'package:flauncher/widgets/launcher_alternative_view.dart';
import 'package:flauncher/widgets/focus_aware_app_bar.dart';
import 'package:flauncher/widgets/wallpaper_video_background.dart';
import 'package:flauncher/widgets/watch_next_hero.dart';
import 'package:flauncher/widgets/watch_next_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/l10n/app_localizations.dart';

import 'models/app.dart';
import 'models/category.dart';
import 'models/watch_next_item.dart';

/// The tray's edge sits 16 dp outside the content keyline (x = 48), so tiles line up with the
/// top bar and the hero. The 34 dp below the tray (it ends at y = 506 on a 540 dp tall screen)
/// belong to the dock, so the first grid section starts below the screen edge.
const _kDockOuterPadding = EdgeInsets.only(left: 32, right: 32, top: 10, bottom: 34);

/// Space between the dock's outer padding and the bottom edge of the screen.
const _kDockBottomMargin = 0.0;

const _kDockTrayPadding = 16.0;

class FLauncher extends StatefulWidget {
  const FLauncher({super.key});

  @override
  State<FLauncher> createState() => _FLauncherState();
}

class _FLauncherState extends State<FLauncher> with WidgetsBindingObserver {
  final GlobalKey<FocusAwareAppBarState> _appBarKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  int _homePressGeneration = 0;
  final GlobalKey _dockKey = GlobalKey();
  final FocusNode _allAppsFocusNode = FocusNode(debugLabel: "dock_all_apps");
  int _heroIndex = 0;
  int _heroDirection = 1;
  late final LauncherState _launcherState;
  late final WatchNextService _watchNextService;
  late final _HeroBackdropBaker _heroBackdropBaker = _HeroBackdropBaker();

  /// Added to the spacer above the dock so the dock ends at the bottom of the screen.
  /// The spacer's base height assumes a fixed dock height, which changes with the
  /// number of favorites and with app names on or off.
  double _dockSpacerCorrection = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FLauncherChannel.setHomePressedHandler(_onHomePressed);
    _launcherState = context.read<LauncherState>();
    _launcherState.returnToDockHandler = _returnToDock;
    _watchNextService = context.read<WatchNextService>();
    _watchNextService.heroSwitchGate = _prepareHeroBackdrop;
  }

  @override
  void dispose() {
    FLauncherChannel.setHomePressedHandler(null);
    if (_launcherState.returnToDockHandler == _returnToDock) {
      _launcherState.returnToDockHandler = null;
    }
    if (_watchNextService.heroSwitchGate == _prepareHeroBackdrop) {
      _watchNextService.heroSwitchGate = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _allAppsFocusNode.dispose();
    _scrollController.dispose();
    _heroBackdropBaker.dispose();
    super.dispose();
  }

  /// Bakes the next hero item's backdrop before the hero shows it, so its text and picture change
  /// together. A poster that is not loaded yet follows on its own once it arrives.
  Future<void> _prepareHeroBackdrop(WatchNextItem item) async {
    if (!mounted) return;
    final settings = context.read<SettingsService>();
    if (!settings.showWatchNextSection || !settings.watchNextBigPictureMode) return;
    final bytes = _watchNextService.getCachedPoster(_watchNextService.getPosterUriForItem(item));
    if (bytes == null) return;
    await _heroBackdropBaker.prepare(bytes);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<WatchNextService>().refreshPermissionAndItems();
    }
  }

  @override
  Widget build(BuildContext context) => Actions(
    actions: <Type, Action<Intent>>{
      MoveFocusToSettingsIntent: CallbackAction<MoveFocusToSettingsIntent>(
        onInvoke: (_) => _appBarKey.currentState?.focusSettings(),
      ),
    },
    child: FocusTraversalGroup(
      policy: RowByRowTraversalPolicy(),
      child: Stack(
        children: [
          RepaintBoundary(
            child: Consumer3<WallpaperService, SettingsService, WatchNextService>(
              builder: (_, wallpaperService, settingsService, watchNextService, __) {
                final author = wallpaperService.slideshowAuthor;
                final redditCredit = wallpaperService.redditWallpaperCredit;
                final isBigPicture = settingsService.showWatchNextSection && settingsService.watchNextBigPictureMode;
                final activeItem = isBigPicture ? watchNextService.activeHeroItem : null;
                final heroUri = isBigPicture ? watchNextService.getPosterUriForItem(activeItem) : null;
                final heroBytes = isBigPicture ? watchNextService.getCachedPoster(heroUri) : null;
                final hasHeroBackdrop = isBigPicture && heroBytes != null;
                final heroIndex = watchNextService.activeHeroIndex;
                if (heroIndex != _heroIndex) {
                  _heroDirection = carouselDirection(_heroIndex, heroIndex, watchNextService.items.length);
                  _heroIndex = heroIndex;
                }
                final screenSize = MediaQuery.sizeOf(context);
                final dpr = MediaQuery.devicePixelRatioOf(context);
                _heroBackdropBaker.update(
                  bytes: hasHeroBackdrop ? heroBytes : null,
                  size: screenSize,
                  dpr: dpr,
                );
                return Stack(
                  children: [
                    // Crossfade between wallpapers (each one has a revision-based key).
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 1500),
                      child: hasHeroBackdrop
                          ? const SizedBox.shrink(key: ValueKey('occluded_wallpaper'))
                          : _scrimmedWallpaper(_wallpaper(context, wallpaperService)),
                    ),
                    // Hero items crossfade once baked simultaneously with dock blur.
                    AnimatedSwitcher(
                      duration: _kHeroFadeDuration,
                      child: hasHeroBackdrop
                          ? RepaintBoundary(
                              key: const ValueKey('hero_bg'),
                              child: ListenableBuilder(
                                listenable: _heroBackdropBaker,
                                builder: (context, _) {
                                  final heroImage = _heroBackdropBaker.textures?.hero;
                                  final Key heroKey = heroImage == null ? const ValueKey('empty_hero') : ObjectKey(heroImage);
                                  // Slides with the hero text, in the direction the carousel moved.
                                  return AnimatedSwitcher(
                                    duration: _kHeroFadeDuration,
                                    transitionBuilder: (child, animation) => carouselTransition(
                                      child: child,
                                      animation: animation,
                                      incoming: child.key == heroKey,
                                      direction: _heroDirection,
                                      distance: 0.03,
                                      coverEdges: true,
                                    ),
                                    child: heroImage == null
                                        ? SizedBox.expand(key: heroKey)
                                        : RawImage(
                                            key: heroKey,
                                            image: heroImage,
                                            width: screenSize.width,
                                            height: screenSize.height,
                                            fit: BoxFit.fill,
                                          ),
                                  );
                                },
                              ),
                            )
                          : const SizedBox.shrink(key: ValueKey('no_hero_bg')),
                    ),
                    if (redditCredit != null && !hasHeroBackdrop)
                      Positioned(
                        right: 24,
                        top: 64,
                        child: Material(
                          type: MaterialType.transparency,
                          child: Text(
                            redditCredit,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white70,
                              shadows: const [Shadow(blurRadius: 4)],
                            ),
                          ),
                        ),
                      )
                    else if (author != null && !hasHeroBackdrop && !kHideUnsplashCredit)
                      Positioned(
                        right: 24,
                        top: 64,
                        // Material gives the text the app font instead of the debug fallback style.
                        child: Material(
                          type: MaterialType.transparency,
                          child: Text(
                            AppLocalizations.of(context)!.unsplashPhotoCredit(author),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white70,
                              shadows: const [Shadow(blurRadius: 4)],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Selector3<LauncherState, SettingsService, WallpaperService, (bool, bool, bool)>(
            selector: (_, launcherState, settings, wallpaperService) => (
              launcherState.appGridFocused,
              settings.backgroundBlurDisabled,
              wallpaperService.wallpaperVideoFile != null,
            ),
            builder: (_, data, __) {
              final (appGridFocused, blurDisabled, hasVideoWallpaper) = data;
              return ListenableBuilder(
                listenable: _heroBackdropBaker,
                builder: (context, _) {
                  final gridBlur = _heroBackdropBaker.textures?.gridBlur;
                  if (blurDisabled || (hasVideoWallpaper && gridBlur == null)) {
                    return const SizedBox.shrink();
                  }
                  return Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: appGridFocused && !blurDisabled ? 1 : 0,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        child: CachedBlurLayer(
                          sigma: 10,
                          prebakedBlur: gridBlur,
                          hidden: !appGridFocused || blurDisabled,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
          Consumer<LauncherState>(
            builder:
                (_, state, child) => Visibility(
                  replacement: const Center(child: AlternativeLauncherView()),
                  visible: state.launcherVisible,
                  child: child!,
                ),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: FocusAwareAppBar(key: _appBarKey),
              // (initialized (data.$1), layoutVersion (data.$2), showAppNamesBelowIcons (data.$3))
              body: Selector2<AppsService, SettingsService, (bool, int, bool)>(
                selector: (_, appsService, settingsService) =>
                    (appsService.initialized, appsService.layoutVersion, settingsService.showAppNamesBelowIcons),
                builder: (context, data, _) {
                  if (data.$1) {
                    return _tvOSLayout(context, context.read<AppsService>(), showAppNames: data.$3);
                  } else {
                    return _emptyState(context);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );

  void _setAppGridFocused(bool focused) {
    context.read<LauncherState>().setAppGridFocused(focused);
  }

  void _onAppGridFocused({VoidCallback? onFirstSectionFocused}) {
    _setAppGridFocused(true);
    onFirstSectionFocused?.call();
  }

  void _onHomeSectionFocused() {
    _setAppGridFocused(false);
  }

  Widget _tvOSLayout(BuildContext context, AppsService appsService, {required bool showAppNames}) {
    final favoritesCategory = appsService.categories.firstWhereOrNull((c) => c.name == 'Favorites');
    final favoriteApps = favoritesCategory?.applications ?? const [];

    final otherSections =
        appsService.launcherSections.where((section) {
          if (section is Category && section.name == 'Favorites') return false;
          return true;
        }).toList();

    final hasAppsBelowDock = otherSections.any((section) => section is Category && section.applications.isNotEmpty);

    final showWatchNextSection = context.select<SettingsService, bool>((s) => s.showWatchNextSection);
    final watchNextBigPicture = context.select<SettingsService, bool>((s) => s.watchNextBigPictureMode);
    final watchNextVisible = context.select<WatchNextService, bool>((s) => s.hasVisibleSection);
    final reserveWatchNextSpace = showWatchNextSection && watchNextVisible;

    if (favoriteApps.isEmpty && otherSections.isEmpty) return _emptyState(context);

    // Big picture: puts the hero's top at y = 226 on a 540 dp tall screen; the dock anchoring below
    // corrects any difference.
    final watchNextSpace = watchNextBigPicture ? 314 : 410;

    if (favoriteApps.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _anchorDockToBottom());
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        if (favoriteApps.isNotEmpty || showWatchNextSection) ...[
          SliverToBoxAdapter(
            child: SizedBox(
              height: max(
                0.0,
                MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    kToolbarHeight -
                    (reserveWatchNextSpace ? watchNextSpace : 150) +
                    (favoriteApps.isNotEmpty ? _dockSpacerCorrection : 0),
              ),
            ),
          ),
          if (showWatchNextSection)
            SliverToBoxAdapter(
              child: RepaintBoundary(
                child: WatchNextRow(
                  isFirstSection: favoriteApps.isEmpty,
                  isAboveDock: true,
                  onItemFocused: _onHomeSectionFocused,
                ),
              ),
            ),
          if (favoriteApps.isNotEmpty)
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: _dockKey,
                child: Padding(
                  padding: _kDockOuterPadding,
                  child: _dock(
                    context,
                    favoritesCategory!,
                    favoriteApps,
                    appsService,
                    handleUpNavigationToSettings: !reserveWatchNextSpace,
                    showAllAppsTile: hasAppsBelowDock,
                  ),
                ),
              ),
            ),
        ],
        ..._buildSectionSlivers(
          otherSections,
          firstCategoryAlreadyFound: favoriteApps.isNotEmpty || reserveWatchNextSpace,
          showAppNames: showAppNames,
          onFirstSectionFocused: favoriteApps.isNotEmpty ? _scrollDockToTop : null,
        ),
        SliverToBoxAdapter(child: SizedBox(height: _bottomScrollPadding(context, hasDock: favoriteApps.isNotEmpty))),
      ],
    );
  }

  double _bottomScrollPadding(BuildContext context, {required bool hasDock}) {
    if (!hasDock) {
      return 64;
    }
    return MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - kToolbarHeight;
  }

  List<Widget> _buildSectionSlivers(
    List<LauncherSection> sections, {
    bool firstCategoryAlreadyFound = false,
    required bool showAppNames,
    VoidCallback? onFirstSectionFocused,
  }) {
    final List<Widget> slivers = [];
    bool firstCategoryFound = firstCategoryAlreadyFound;
    bool firstBuiltSectionFound = false;

    for (final section in sections) {
      final Key sectionKey = Key(section.id.toString());

      if (section is LauncherSpacer) {
        slivers.add(SliverToBoxAdapter(key: sectionKey, child: SizedBox(height: section.height.toDouble())));
        continue;
      }

      final category = section as Category;
      final filteredApps = category.applications;
      if (filteredApps.isEmpty) continue;

      final bool isFirstSection = !firstCategoryFound;
      if (isFirstSection) firstCategoryFound = true;
      final bool isFirstBuiltSection = !firstBuiltSectionFound;
      final onAppFocused = isFirstBuiltSection
          ? () => _onAppGridFocused(onFirstSectionFocused: onFirstSectionFocused)
          : () => _onAppGridFocused();
      firstBuiltSectionFound = true;

      slivers.add(
        SliverToBoxAdapter(
          child: Selector<SettingsService, bool>(
            selector: (context, service) => service.showCategoryTitles,
            builder: (context, showTitle, _) {
              if (showTitle) {
                return Padding(
                  padding: const EdgeInsets.only(left: 40, bottom: 8, top: 8),
                  child: Text(
                    category.name,
                    style: Theme.of(context).textTheme.titleLarge!.copyWith(
                      shadows: const [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 8)],
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      switch (category.type) {
        case CategoryType.row:
          slivers.add(
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: kLauncherSectionHorizontalPadding,
                  right: kLauncherSectionHorizontalPadding,
                  bottom: 8,
                ),
                child: CategoryRow(
                  key: sectionKey,
                  category: category,
                  applications: filteredApps,
                  isFirstSection: isFirstSection,
                  showTitle: false,
                  onAppFocused: onAppFocused,
                ),
              ),
            ),
          );
          break;
        case CategoryType.grid:
          final gridContentWidth = MediaQuery.sizeOf(context).width - 2 * kLauncherSectionHorizontalPadding;
          final gridAspectRatio = showAppNames
              ? appCardGridAspectRatio(gridContentWidth, category.columnsCount)
              : kAppCardAspectRatio;
          slivers.add(
            SliverPadding(
              padding: const EdgeInsets.only(
                left: kLauncherSectionHorizontalPadding,
                right: kLauncherSectionHorizontalPadding,
                bottom: 8,
              ),
              sliver: SliverGrid(
                key: sectionKey,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: category.columnsCount,
                  childAspectRatio: gridAspectRatio,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 0,
                ),
                delegate: SliverChildBuilderDelegate(
                  childCount: filteredApps.length,
                  findChildIndexCallback: (Key key) {
                    final valueKey = key as ValueKey<String>;
                    final index = filteredApps.indexWhere((app) => app.packageName == valueKey.value);
                    return index >= 0 ? index : null;
                  },
                  (context, index) => Padding(
                    key: Key(filteredApps[index].packageName),
                    padding: const EdgeInsets.symmetric(
                      horizontal: kAppCardHorizontalPadding,
                      vertical: kAppCardVerticalPadding,
                    ),
                    child: AppCard(
                      category: category,
                      application: filteredApps[index],
                      autofocus: index == 0,
                      handleUpNavigationToSettings: isFirstSection && index < category.columnsCount,
                      enforceAspectRatio: false,
                      onFocused: index < category.columnsCount ? onAppFocused : null,
                      ensureVisibleOnFocus: !isFirstBuiltSection || index >= category.columnsCount,
                      onlyScrollWhenNearBottom: true,
                      onMove: (direction) => _onGridMove(context, category, index, direction, filteredApps),
                      onMoveEnd: () => context.read<AppsService>().saveApplicationOrderInCategory(category),
                    ),
                  ),
                ),
              ),
            ),
          );
          break;
      }
    }

    return slivers;
  }

  Future<void> _onHomePressed() async {
    if (!mounted) return;
    // HOME closes everything opened above the home page (SettingsPanel, nested
    // dialogs). They sit in the root navigator; SettingsPanel's own Navigator
    // goes away with its dialog route.
    Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
    if (!_scrollController.hasClients) return;
    final generation = ++_homePressGeneration;
    await _scrollController.animateTo(
      _scrollController.position.minScrollExtent,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
    );
    if (!mounted || generation != _homePressGeneration) return;
    final scrollPosition = _scrollController.position;
    FocusNode? firstWatchNext;
    FocusNode? firstApp;
    Offset? watchNextOrigin;
    Offset? appOrigin;
    for (final node in FocusScope.of(context).traversalDescendants) {
      final nodeContext = node.context;
      if (nodeContext == null || !node.canRequestFocus) continue;
      if (Scrollable.maybeOf(nodeContext, axis: Axis.vertical)?.position !=
          scrollPosition) continue;
      final renderObject = nodeContext.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final origin = renderObject.localToGlobal(Offset.zero);
      if (nodeContext.findAncestorWidgetOfExactType<WatchNextRow>() != null) {
        if (watchNextOrigin == null ||
            origin.dy < watchNextOrigin.dy ||
            (origin.dy == watchNextOrigin.dy && origin.dx < watchNextOrigin.dx)) {
          firstWatchNext = node;
          watchNextOrigin = origin;
        }
      }
      if (nodeContext.findAncestorWidgetOfExactType<AppCard>() != null) {
        if (appOrigin == null ||
            origin.dy < appOrigin.dy ||
            (origin.dy == appOrigin.dy && origin.dx < appOrigin.dx)) {
          firstApp = node;
          appOrigin = origin;
        }
      }
    }
    (firstWatchNext ?? firstApp)?.requestFocus();
  }

  Future<void> _scrollDockToTop() async {
    final targetOffset = _dockTopScrollOffset();
    if (targetOffset == null) {
      return;
    }

    final position = _scrollController.position;
    if ((targetOffset - position.pixels).abs() < 16) {
      return;
    }

    await _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
    );
  }

  /// Measures where the dock ends and moves it so it sits [_kDockBottomMargin] above
  /// the bottom edge. Only runs while the page is unscrolled, so the measurement is
  /// the resting position.
  void _anchorDockToBottom() {
    if (!mounted || !_scrollController.hasClients || _scrollController.offset != 0) {
      return;
    }
    final dockBox = _dockKey.currentContext?.findRenderObject() as RenderBox?;
    if (dockBox == null || !dockBox.hasSize) {
      return;
    }
    final dockBottom = dockBox.localToGlobal(Offset(0, dockBox.size.height)).dy;
    final gap = MediaQuery.sizeOf(context).height - _kDockBottomMargin - dockBottom;
    if (gap.abs() < 1) {
      return;
    }
    setState(() => _dockSpacerCorrection += gap);
  }

  double? _dockTopScrollOffset() {
    final dockContext = _dockKey.currentContext;
    final renderObject = dockContext?.findRenderObject();
    if (!_scrollController.hasClients || renderObject == null) {
      return null;
    }

    final viewport = RenderAbstractViewport.of(renderObject);
    final position = _scrollController.position;
    return viewport.getOffsetToReveal(renderObject, 0).offset.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  // TO DO : refractor duplicate _onMove code
  void _onGridMove(
    BuildContext context,
    Category category,
    int index,
    AxisDirection direction,
    List<App> filteredApps,
  ) {
    final currentRow = (index / category.columnsCount).floor();
    final totalRows = ((filteredApps.length - 1) / category.columnsCount).floor();

    int? newIndex;
    switch (direction) {
      case AxisDirection.up:
        if (currentRow > 0) newIndex = index - category.columnsCount;
        break;
      case AxisDirection.right:
        if (index < filteredApps.length - 1) newIndex = index + 1;
        break;
      case AxisDirection.down:
        if (currentRow < totalRows) newIndex = min(index + category.columnsCount, filteredApps.length - 1);
        break;
      case AxisDirection.left:
        if (index > 0) newIndex = index - 1;
        break;
    }

    if (newIndex != null) {
      final appsService = context.read<AppsService>();
      final movingApp = filteredApps[index];
      final realOldIndex = category.applications.indexOf(movingApp);
      final realNewIndex = category.applications.indexOf(filteredApps[newIndex]);
      if (realOldIndex >= 0 && realNewIndex >= 0) {
        appsService.reorderApplication(category, realOldIndex, realNewIndex);
        appsService.setPendingReorderFocus(movingApp.packageName, category.id);
      }
    }
  }

  Widget _dock(
    BuildContext context,
    Category category,
    List<App> apps,
    AppsService appsService, {
    required bool handleUpNavigationToSettings,
    required bool showAllAppsTile,
  }) {
    final tileRadius = context.select<SettingsService, double>((s) => s.cardCornerRadius);
    // Concentric with the tiles: tray radius = tile radius + tray padding.
    final trayRadius = BorderRadius.circular(tileRadius + _kDockTrayPadding);

    // Flat, translucent tray: the picture shows through as it is, without a blurred copy.
    return Container(
      key: const Key("dock_tray"),
      padding: const EdgeInsets.all(_kDockTrayPadding),
      decoration: BoxDecoration(color: const Color.fromRGBO(30, 30, 30, 0.55), borderRadius: trayRadius),
      // A foreground border adds no padding, so the tiles start exactly on the content keyline.
      foregroundDecoration: BoxDecoration(
        borderRadius: trayRadius,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1 / MediaQuery.devicePixelRatioOf(context),
        ),
      ),
      child: CategoryCleanRow(
        category: category,
        applications: apps,
        isFirstSection: handleUpNavigationToSettings,
        scrollAlignment: 1.0,
        onAppFocused: _onHomeSectionFocused,
        onAllAppsPressed: showAllAppsTile ? _focusFirstGridApp : null,
        allAppsFocusNode: _allAppsFocusNode,
      ),
    );
  }

  /// "All apps" in the dock: focus the top-left app below the dock, which scrolls the grid up.
  Future<void> _focusFirstGridApp() async {
    var target = _firstGridAppNode();
    if (target == null) {
      // The grid is built lazily; reveal it first.
      await _scrollDockToTop();
      if (!mounted) return;
      target = _firstGridAppNode();
    }
    target?.requestFocus();
  }

  FocusNode? _firstGridAppNode() {
    FocusNode? first;
    Offset? firstOrigin;
    for (final node in FocusScope.of(context).traversalDescendants) {
      final nodeContext = node.context;
      if (nodeContext == null || !node.canRequestFocus) continue;
      if (nodeContext.findAncestorWidgetOfExactType<AppCard>() == null) continue;
      if (nodeContext.findAncestorWidgetOfExactType<CategoryCleanRow>() != null) continue;
      final renderObject = nodeContext.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final origin = renderObject.localToGlobal(Offset.zero);
      if (firstOrigin == null || origin.dy < firstOrigin.dy || (origin.dy == firstOrigin.dy && origin.dx < firstOrigin.dx)) {
        first = node;
        firstOrigin = origin;
      }
    }
    return first;
  }

  /// Back while the app grid has focus: return to the "All apps" tile and the top of the page.
  bool _returnToDock() {
    if (!mounted || _allAppsFocusNode.context == null) {
      return false;
    }
    _allAppsFocusNode.requestFocus();
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOutCubic,
      );
    }
    return true;
  }

  /// The wallpaper with the same top and bottom scrims as the hero backdrop, crossfading as one.
  Widget _scrimmedWallpaper(Widget wallpaper) => Stack(
    key: ValueKey(('scrimmed_wallpaper', wallpaper.key)),
    children: [
      wallpaper,
      const Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            key: Key("wallpaper_scrim"),
            painter: _CinematicScrimPainter(leftScrim: false),
          ),
        ),
      ),
    ],
  );

  Widget _wallpaper(BuildContext context, WallpaperService wallpaperService) {
    final screenSize = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final videoFile = wallpaperService.wallpaperVideoFile;
    if (videoFile != null) {
      return SizedBox(
        width: screenSize.width,
        height: screenSize.height,
        child: WallpaperVideoBackground(
          key: ValueKey("background_video_${wallpaperService.wallpaperRevision}"),
          file: videoFile,
        ),
      );
    }
    if (wallpaperService.wallpaper != null) {
      return Image(
        image: ResizeImage(wallpaperService.wallpaper!, height: (screenSize.height * dpr).round()),
        key: ValueKey("background_${wallpaperService.wallpaperRevision}"),
        fit: BoxFit.cover,
        height: screenSize.height,
        width: screenSize.width,
      );
    } else {
      return _CachedGradientBackground(key: const Key("background"), gradient: wallpaperService.gradient.gradient);
    }
  }

  Widget _emptyState(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(localizations.loading, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

/// Renders a [Gradient] once into a rasterized [ui.Image] and blits it as a
/// texture instead of evaluating the gradient shader every frame.
///
/// On low-end GPUs (e.g. Android TV sticks) a full-screen live gradient is
/// noticeably more expensive to raster than a cached texture, so this keeps the
/// background as cheap as a static image wallpaper.
class _CachedGradientBackground extends StatefulWidget {
  final Gradient gradient;

  const _CachedGradientBackground({super.key, required this.gradient});

  @override
  State<_CachedGradientBackground> createState() => _CachedGradientBackgroundState();
}

class _CachedGradientBackgroundState extends State<_CachedGradientBackground> {
  ui.Image? _image;
  Size _renderedSize = Size.zero;
  Gradient? _renderedGradient;
  bool _rendering = false;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _render(Size size) async {
    if (_rendering) {
      return;
    }
    _rendering = true;
    final recorder = ui.PictureRecorder();
    final rect = Offset.zero & size;
    Canvas(recorder).drawRect(rect, Paint()..shader = widget.gradient.createShader(rect));
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size.width.round(), size.height.round());
    picture.dispose();
    _rendering = false;
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _renderedSize = size;
      _renderedGradient = widget.gradient;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final needsRender = size != _renderedSize || widget.gradient != _renderedGradient;
        if (needsRender && size.width > 0 && size.height > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && (size != _renderedSize || widget.gradient != _renderedGradient)) {
              _render(size);
            }
          });
        }
        final image = _image;
        if (image != null && !needsRender) {
          return RawImage(image: image, width: size.width, height: size.height, fit: BoxFit.fill);
        }
        // First frame (and while re-rendering): paint the gradient live once to avoid a flash.
        return DecoratedBox(decoration: BoxDecoration(gradient: widget.gradient));
      },
    );
  }
}

/// Same 400 ms as the hero text, so text and backdrop change together.
const _kHeroFadeDuration = kHeroCarouselDuration;

class _HeroBackdropTextures {
  final ui.Image hero;
  final ui.Image gridBlur;
  final Uint8List bytes;
  final Size size;
  final double dpr;
  bool _disposed = false;

  _HeroBackdropTextures({
    required this.hero,
    required this.gridBlur,
    required this.bytes,
    required this.size,
    required this.dpr,
  });

  bool matches(Uint8List bytes, Size size, double dpr) =>
      identical(bytes, this.bytes) && size == this.size && dpr == this.dpr;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    hero.dispose();
    gridBlur.dispose();
  }
}

class _HeroBackdropBaker extends ChangeNotifier {
  _HeroBackdropTextures? _current;
  /// Baked ahead by [prepare] for the hero item about to be shown; [update] shows it at once.
  _HeroBackdropTextures? _prepared;
  ({Uint8List bytes, Future<void> done})? _preparing;
  final List<_HeroBackdropTextures> _disposedTextures = [];
  Uint8List? _requestedBytes;
  Size _requestedSize = Size.zero;
  double _requestedDpr = 1.0;
  bool _baking = false;
  bool _isDisposed = false;

  _HeroBackdropTextures? get textures => _current;

  void update({required Uint8List? bytes, required Size size, required double dpr}) {
    if (identical(bytes, _requestedBytes) && size == _requestedSize && dpr == _requestedDpr) {
      return;
    }
    _requestedBytes = bytes;
    _requestedSize = size;
    _requestedDpr = dpr;

    if (bytes == null || size.width <= 0 || size.height <= 0) {
      if (_current != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_requestedBytes == null && _current != null) {
            _scheduleDispose(_current!);
            _current = null;
            notifyListeners();
          }
        });
      }
      return;
    }

    final prepared = _prepared;
    if (prepared != null && prepared.matches(bytes, size, dpr)) {
      _prepared = null;
      _setCurrent(prepared);
      // Runs during build: the hero backdrop is rebuilt in this frame anyway, so its transition
      // starts with the hero text. The grid blur follows on the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed) notifyListeners();
      });
      return;
    }

    if (!_baking) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_baking && _requestedBytes != null) {
          _bake();
        }
      });
    }
  }

  /// Bakes [bytes] at the current screen size without showing them, so the next [update] with the
  /// same bytes can swap them in within the same frame.
  Future<void> prepare(Uint8List bytes) {
    final size = _requestedSize;
    final dpr = _requestedDpr;
    if (_isDisposed || size.width <= 0 || size.height <= 0) return Future.value();
    if ((_current?.matches(bytes, size, dpr) ?? false) || (_prepared?.matches(bytes, size, dpr) ?? false)) {
      return Future.value();
    }
    final pending = _preparing;
    if (pending != null && identical(pending.bytes, bytes)) return pending.done;

    bool isStale() => _isDisposed || !identical(_preparing?.bytes, bytes);
    Future<void> run() async {
      final textures = await _bakeTextures(bytes, size, dpr, isStale: isStale);
      if (textures == null) return;
      if (isStale()) {
        textures.dispose();
        return;
      }
      _preparing = null;
      final old = _prepared;
      _prepared = textures;
      if (old != null) _scheduleDispose(old);
    }

    final done = run();
    _preparing = (bytes: bytes, done: done);
    return done;
  }

  void _setCurrent(_HeroBackdropTextures textures) {
    final old = _current;
    _current = textures;
    if (old != null) {
      _scheduleDispose(old);
    }
  }

  void _scheduleDispose(_HeroBackdropTextures textures) {
    _disposedTextures.add(textures);
    Timer(const Duration(milliseconds: 1000), () {
      _disposedTextures.remove(textures);
      textures.dispose();
    });
  }

  Future<void> _bake() async {
    if (_baking) return;
    _baking = true;
    try {
      while (_requestedBytes != null && !(_current?.matches(_requestedBytes!, _requestedSize, _requestedDpr) ?? false)) {
        final bytes = _requestedBytes!;
        final textures = await _bakeTextures(
          bytes,
          _requestedSize,
          _requestedDpr,
          isStale: () => !identical(bytes, _requestedBytes),
        );
        if (textures == null) continue;
        _setCurrent(textures);
        notifyListeners();
      }
    } finally {
      _baking = false;
    }
  }

  /// The full-screen hero picture and the grid blur for [bytes], or null when [isStale] turns true
  /// on the way.
  Future<_HeroBackdropTextures?> _bakeTextures(
    Uint8List bytes,
    Size size,
    double dpr, {
    required bool Function() isStale,
  }) async {
    final pxSize = Size((size.width * dpr).roundToDouble(), (size.height * dpr).roundToDouble());
    final codec = await ui.instantiateImageCodecWithSize(
      await ui.ImmutableBuffer.fromUint8List(bytes),
      getTargetSize: (w, h) {
        final scale = min(1.0, max(pxSize.width / w, pxSize.height / h));
        return ui.TargetImageSize(width: (w * scale).round(), height: (h * scale).round());
      },
    );
    final source = (await codec.getNextFrame()).image;
    codec.dispose();

    if (isStale()) {
      source.dispose();
      return null;
    }

    // 1. Full-screen hero background with cinematic scrim
    final heroRecorder = ui.PictureRecorder();
    final heroCanvas = Canvas(heroRecorder);
    paintImage(
      canvas: heroCanvas,
      rect: Offset.zero & pxSize,
      image: source,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
    );
    const _CinematicScrimPainter().paint(heroCanvas, pxSize);
    final heroPicture = heroRecorder.endRecording();
    final heroImage = heroPicture.toImageSync(pxSize.width.toInt(), pxSize.height.toInt());
    heroPicture.dispose();

    // 2. App grid blur snapshot (960x540, sigma 10)
    final double targetWidth = min(size.width * dpr, 960.0);
    final double targetHeight = min(size.height * dpr, 540.0);
    final pxWidth = targetWidth.round();
    final pxHeight = targetHeight.round();
    final blurRect = Rect.fromLTWH(0, 0, pxWidth.toDouble(), pxHeight.toDouble());
    final double scaleFactor = pxWidth / size.width;

    final gridRecorder = ui.PictureRecorder();
    final gridCanvas = Canvas(gridRecorder);
    final gridPaint = Paint()
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: 10.0 * scaleFactor,
        sigmaY: 10.0 * scaleFactor,
        tileMode: TileMode.clamp,
      );
    gridCanvas.saveLayer(blurRect, gridPaint);
    paintImage(
      canvas: gridCanvas,
      rect: blurRect,
      image: source,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.low,
    );
    // Blur the scrimmed hero (what is actually on screen), otherwise the blur looks much brighter.
    const _CinematicScrimPainter().paint(gridCanvas, blurRect.size);
    gridCanvas.restore();
    final gridPicture = gridRecorder.endRecording();
    final gridImage = gridPicture.toImageSync(pxWidth, pxHeight);
    gridPicture.dispose();

    source.dispose();

    if (isStale()) {
      heroImage.dispose();
      gridImage.dispose();
      return null;
    }
    return _HeroBackdropTextures(hero: heroImage, gridBlur: gridImage, bytes: bytes, size: size, dpr: dpr);
  }

  @override
  void dispose() {
    _isDisposed = true;
    for (final t in _disposedTextures) {
      t.dispose();
    }
    _disposedTextures.clear();
    _current?.dispose();
    _current = null;
    _prepared?.dispose();
    _prepared = null;
    super.dispose();
  }
}

/// Scrims over the home background. The left one only goes behind the hero text; top and bottom
/// keep the top bar and the dock readable on any picture.
class _CinematicScrimPainter extends CustomPainter {
  final bool leftScrim;

  const _CinematicScrimPainter({this.leftScrim = true});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (leftScrim) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, size.height / 2),
            Offset(size.width, size.height / 2),
            const [Color(0xD9000000), Color(0xD9000000), Colors.transparent], // 0.85, 0.85, 0
            const [0.0, 0.25, 0.6],
          ),
      );
    }
    // Bottom: 50% black at the bottom edge, gone at 35% of the height measured from the bottom.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, size.height),
          Offset.zero,
          const [Color(0x80000000), Colors.transparent],
          const [0.0, 0.35],
        ),
    );
    // Top: 45% black at the top edge, gone at 15% of the height.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          const [Color(0x73000000), Colors.transparent],
          const [0.0, 0.15],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _CinematicScrimPainter oldDelegate) => oldDelegate.leftScrim != leftScrim;
}

