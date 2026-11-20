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

import 'dart:math';

import 'package:flauncher/actions.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/app_card.dart';
import 'package:flauncher/widgets/category_container_common.dart';
import 'package:flauncher/widgets/dock_focus_ring.dart';
import 'package:flauncher/widgets/focus_keyboard_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app.dart';
import '../models/category.dart';

/// Smallest space between two dock tiles, so the focus ring of a scaled tile stays clear of its
/// neighbours.
const kDockMinTileGap = 12.0;

/// Size of each of [tileCount] app tiles in [contentWidth]: [kDockTileMaxWidth] wide while they
/// fit, otherwise all shrink evenly, keeping their shape. With [withSquareTile], a square tile as
/// tall as the app tiles shares the width (the "All apps" tile).
Size dockTileSize(double contentWidth, int tileCount, {bool withSquareTile = false}) {
  if (tileCount <= 0) {
    return const Size(kDockTileMaxWidth, kDockTileHeight);
  }
  const squareShare = kDockTileHeight / kDockTileMaxWidth;
  final gaps = withSquareTile ? tileCount : tileCount - 1;
  final fitWidth = (contentWidth - gaps * kDockMinTileGap) / (tileCount + (withSquareTile ? squareShare : 0));
  final width = max(0.0, min(kDockTileMaxWidth, fitWidth));
  return Size(width, width * squareShare);
}

class CategoryCleanRow extends StatelessWidget
{
  final Category category;
  final List<App> applications;

  final bool isFirstSection;
  final double scrollAlignment;
  final VoidCallback? onAppFocused;

  /// Called with the app whose tile got focus (after [onAppFocused]); not for the "All apps" tile.
  final void Function(App app)? onDockAppFocused;

  /// Shows the "All apps" tile at the end of the row when set.
  final VoidCallback? onAllAppsPressed;
  final FocusNode? allAppsFocusNode;

  CategoryCleanRow({
    Key? key,
    required this.category,
    required this.applications,
    this.isFirstSection = false,
    this.scrollAlignment = 0.5,
    this.onAppFocused,
    this.onDockAppFocused,
    this.onAllAppsPressed,
    this.allAppsFocusNode,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget categoryContent;
    if (applications.isEmpty) {
      categoryContent = categoryContainerEmptyState(context);
    }
    else {
      categoryContent = LayoutBuilder(
        builder: (context, constraints) {
          final tileSize = dockTileSize(
            constraints.maxWidth,
            applications.length,
            withSquareTile: onAllAppsPressed != null,
          );
          return SizedBox(
            height: tileSize.height,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final (index, application) in applications.indexed)
                  SizedBox(
                    key: ValueKey(application.packageName),
                    width: tileSize.width,
                    height: tileSize.height,
                    child: AppCard(
                      category: category,
                      application: application,
                      autofocus: index == 0,
                      handleUpNavigationToSettings: isFirstSection,
                      scrollAlignment: scrollAlignment,
                      enforceAspectRatio: false,
                      dockTile: true,
                      onFocused: onAppFocused == null && onDockAppFocused == null
                          ? null
                          : () {
                              onAppFocused?.call();
                              onDockAppFocused?.call(application);
                            },
                      onMove: (direction) => _onMove(context, direction, index),
                      onMoveEnd: () => _onMoveEnd(context),
                    ),
                  ),
                if (onAllAppsPressed != null)
                  SizedBox.square(
                    dimension: tileSize.height,
                    child: DockAllAppsTile(
                      focusNode: allAppsFocusNode,
                      onPressed: onAllAppsPressed!,
                      onFocused: onAppFocused,
                      handleUpNavigationToSettings: isFirstSection,
                    ),
                  ),
              ],
            ),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        categoryContent
      ],
    );
  }

  // TO DO : refractor duplicate _onMove code
  void _onMove(BuildContext context, AxisDirection direction, int index) {
    int newIndex = 0;

    if (direction == AxisDirection.right && index < applications.length - 1) {
      newIndex = index + 1;
    } else if (direction == AxisDirection.left && index > 0) {
      newIndex = index - 1;
    } else {
      // Ignore UP/DOWN or at boundaries
      return;
    }

    final appsService = context.read<AppsService>();
    final movingApp = applications[index];
    final realOldIndex = category.applications.indexOf(movingApp);
    final realNewIndex = category.applications.indexOf(applications[newIndex]);
    if (realOldIndex >= 0 && realNewIndex >= 0) {
      appsService.reorderApplication(category, realOldIndex, realNewIndex);
      // Set pending focus so the app at the new position will request focus
      appsService.setPendingReorderFocus(movingApp.packageName, category.id);
    }
  }

  void _onMoveEnd(BuildContext context) {
    final appsService = context.read<AppsService>();
    appsService.saveApplicationOrderInCategory(category);
  }
}

/// Last tile of the dock: takes focus to the full app list below the dock.
class DockAllAppsTile extends StatefulWidget {
  final FocusNode? focusNode;
  final VoidCallback onPressed;
  final VoidCallback? onFocused;
  final bool handleUpNavigationToSettings;

  const DockAllAppsTile({
    super.key,
    this.focusNode,
    required this.onPressed,
    this.onFocused,
    this.handleUpNavigationToSettings = false,
  });

  @override
  State<DockAllAppsTile> createState() => _DockAllAppsTileState();
}

class _DockAllAppsTileState extends State<DockAllAppsTile> {
  bool _focused = false;
  bool _selectDown = false;

  // Fires on key up, like the app tiles, so the release does not land on the app focused next.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (longPressableKeys.contains(key)) {
      if (event is KeyDownEvent) {
        _selectDown = true;
      } else if (event is KeyUpEvent && _selectDown) {
        _selectDown = false;
        widget.onPressed();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && key == LogicalKeyboardKey.arrowUp && widget.handleUpNavigationToSettings) {
      Actions.invoke(context, const MoveFocusToSettingsIntent());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final (radius, showFocusBorders) = context.select<SettingsService, (double, bool)>(
      (s) => (s.cardCornerRadius, s.showFocusBorders),
    );
    final highlighted = _focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Semantics(
      button: true,
      label: AppLocalizations.of(context)!.dockAllApps,
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: _onKey,
        onFocusChange: (focused) {
          setState(() {
            _focused = focused;
            _selectDown = false;
          });
          if (focused) {
            widget.onFocused?.call();
          }
        },
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedScale(
            scale: highlighted ? kDockTileFocusedScale : 1.0,
            duration: kDockFocusDuration,
            curve: Curves.easeOut,
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                DockTileShadow(tileRadius: radius, visible: highlighted),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0x1FFFFFFF),
                    borderRadius: BorderRadius.circular(radius),
                  ),
                  child: LayoutBuilder(
                    // The 3x3 glyph is 34 of the tile's 84 px.
                    builder: (context, constraints) =>
                        Icon(Icons.apps, size: constraints.maxHeight * 34 / 84, color: Colors.white),
                  ),
                ),
                DockTileInnerBorder(tileRadius: radius),
                if (showFocusBorders) DockFocusRing(tileRadius: radius, visible: highlighted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
