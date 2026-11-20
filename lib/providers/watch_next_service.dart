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
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/models/watch_next_item.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:http/http.dart' as http;

/// The width the hero backdrop fills: the screen at 1080p.
const int kArtworkTargetWidth = 1920;

/// [uri] asking its image server for a backdrop [kArtworkTargetWidth] wide, when the link carries
/// a smaller size the server lets us change; otherwise [uri] itself.
///
/// Disney+ and HBO Max publish 544 and 600 px wide images in Watch Next, which look soft
/// stretched across the screen; both servers return 1920 px when the link asks for it.
Uri largerArtworkUri(Uri uri) {
  final host = uri.host;
  final query = uri.queryParameters;
  // Disney+: ripcut-delivery …/scale?format=webp&height=306&width=544
  if (host.endsWith('bamgrid.com') && uri.path.contains('/ripcut-delivery/') && uri.path.endsWith('/scale')) {
    final width = int.tryParse(query['width'] ?? '');
    final height = int.tryParse(query['height'] ?? '');
    if (width == null || height == null || width <= 0 || width >= kArtworkTargetWidth) return uri;
    return uri.replace(queryParameters: {
      ...query,
      'width': '$kArtworkTargetWidth',
      'height': '${(height * kArtworkTargetWidth / width).round()}',
    });
  }
  // HBO Max: images.cdn.prd.api.discomax.com/…?w=600&q=85&p=true&f=jpg
  if (host.endsWith('discomax.com')) {
    final width = int.tryParse(query['w'] ?? '');
    if (width == null || width <= 0 || width >= kArtworkTargetWidth) return uri;
    return uri.replace(queryParameters: {...query, 'w': '$kArtworkTargetWidth'});
  }
  return uri;
}

class WatchNextService extends ChangeNotifier {
  final FLauncherChannel _fLauncherChannel;
  final SettingsService? _settingsService;

  List<WatchNextItem> _allRawItems = [];
  List<WatchNextItem> _items = [];
  bool _isLoading = false;
  bool _hasPermission = false;
  int _activeHeroIndex = 0;
  final Map<String, Uint8List> _posterCache = {};
  final Set<String> _loadingPosters = {};
  final Set<String> _failedPosters = {};
  /// Pictures that could not be reached, typically right after a cold boot before Wi-Fi is up.
  /// They are not marked failed, so the hero keeps the wallpaper instead of a placeholder poster,
  /// and they are downloaded again after [posterRetryDelays].
  final Set<String> _unreachablePosters = {};
  int _posterRetryAttempt = 0;
  Timer? _refreshTimer;
  Timer? _posterNotifyDebounce;
  Timer? _posterRetryTimer;
  static const int _maxParallelPosterLoads = 2;

  /// Waits before downloading unreachable pictures again; the last one repeats.
  static const posterRetryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  List<WatchNextItem> get items => _items;
  bool get isLoading => _isLoading;
  bool get hasPermission => _hasPermission;
  bool get hasItems => _items.isNotEmpty;
  bool get hasVisibleSection => (!_hasPermission || _items.isNotEmpty);
  int get activeHeroIndex => _activeHeroIndex;
  WatchNextItem? get activeHeroItem =>
      _items.isNotEmpty && _activeHeroIndex < _items.length ? _items[_activeHeroIndex] : null;

  Set<String> get availablePackageNames {
    return _allRawItems
        .map((item) => item.packageName)
        .whereType<String>()
        .where((pkg) => pkg.trim().isNotEmpty)
        .toSet();
  }

  String? getPosterUriForItem(WatchNextItem? item) {
    if (item == null) return null;
    final uri = item.backdropUri ?? item.posterUri;
    if (uri != null && uri.trim().isNotEmpty && !_failedPosters.contains(uri)) {
      return uri;
    }
    return 'placeholder://${item.id}';
  }

  bool itemHasImage(WatchNextItem item) {
    final uri = item.backdropUri ?? item.posterUri;
    if (uri == null || uri.trim().isEmpty) return false;
    if (_failedPosters.contains(uri)) return false;
    return true;
  }

  /// Runs before the hero shows another item, and the change waits for it (at most
  /// [heroSwitchMaxWait]). The home screen bakes the item's backdrop here, so the text and the
  /// picture start their transition in the same frame.
  Future<void> Function(WatchNextItem item)? heroSwitchGate;

  static const heroSwitchMaxWait = Duration(milliseconds: 600);

  /// The index the user moved to while [heroSwitchGate] is still running; null when none is pending.
  int? _requestedHeroIndex;
  int _heroRequest = 0;

  void setActiveHeroIndex(int index) {
    if (_items.isEmpty) return;
    final clamped = index.clamp(0, _items.length - 1);
    if (clamped == (_requestedHeroIndex ?? _activeHeroIndex)) return;
    final request = ++_heroRequest;
    final gate = heroSwitchGate;
    // Back to the item on screen: its backdrop is already there.
    if (gate == null || clamped == _activeHeroIndex) {
      _commitHeroIndex(clamped);
      return;
    }
    _requestedHeroIndex = clamped;
    final item = _items[clamped];
    ensurePosterLoaded(getPosterUriForItem(item));
    // A slow or failing gate only delays the change; it never blocks the carousel.
    unawaited(Future.sync(() => gate(item))
        .timeout(heroSwitchMaxWait)
        .catchError((Object _) {})
        .whenComplete(() {
      if (request == _heroRequest) _commitHeroIndex(clamped);
    }));
  }

  void _commitHeroIndex(int index) {
    _requestedHeroIndex = null;
    if (index >= _items.length || index == _activeHeroIndex) return;
    _activeHeroIndex = index;
    _ensureActiveHeroImageLoaded();
    notifyListeners();
  }

  /// Shows the first item from [packageName] in the hero (its dock tile has focus). The hero is
  /// left as it is when it already shows (or is switching to) an item from that app, or when the
  /// app has none.
  void showFirstItemFor(String packageName) {
    final shownIndex = _requestedHeroIndex ?? _activeHeroIndex;
    if (shownIndex < _items.length && _items[shownIndex].packageName == packageName) return;
    final index = _items.indexWhere((item) => item.packageName == packageName);
    if (index >= 0) setActiveHeroIndex(index);
  }

  void nextHeroItem() {
    if (_items.isEmpty) return;
    final next = ((_requestedHeroIndex ?? _activeHeroIndex) + 1) % _items.length;
    setActiveHeroIndex(next);
  }

  void prevHeroItem() {
    if (_items.isEmpty) return;
    final prev = ((_requestedHeroIndex ?? _activeHeroIndex) - 1 + _items.length) % _items.length;
    setActiveHeroIndex(prev);
  }

  void _ensureActiveHeroImageLoaded() {
    final item = activeHeroItem;
    if (item != null) {
      final uri = getPosterUriForItem(item);
      ensurePosterLoaded(uri);
    }
  }

  WatchNextService(this._fLauncherChannel, {SettingsService? settingsService})
      : _settingsService = settingsService {
    _settingsService?.addListener(_onSettingsChanged);
    _init();
  }

  void _onSettingsChanged() {
    _applyFilterAndNotify();
  }

  void _init() async {
    await refreshPermissionAndItems();
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      refreshPermissionAndItems();
    });
  }

  @override
  void dispose() {
    _settingsService?.removeListener(_onSettingsChanged);
    _refreshTimer?.cancel();
    _posterNotifyDebounce?.cancel();
    _posterRetryTimer?.cancel();
    super.dispose();
  }

  Future<void> checkPermission() async {
    try {
      _hasPermission = await _fLauncherChannel.checkWatchNextPermission();
    } catch (e) {
      debugPrint('WatchNext: Error checking permission: $e');
      _hasPermission = false;
    }
    notifyListeners();
  }

  Future<void> requestPermission() async {
    try {
      await _fLauncherChannel.requestWatchNextPermission();
    } catch (e) {
      debugPrint('WatchNext: Error requesting permission: $e');
    }
  }

  Future<void> forceRefresh() async {
    _posterCache.clear();
    _failedPosters.clear();
    await refreshPermissionAndItems();
  }

  Future<void> refreshPermissionAndItems() async {
    await checkPermission();
    if (_hasPermission) {
      await refreshItems();
    } else {
      _allRawItems = [];
      _items = [];
      notifyListeners();
    }
  }

  Future<void> refreshItems() async {
    if (_isLoading) return;

    if (!_hasPermission) {
      await checkPermission();
      if (!_hasPermission) {
        _allRawItems = [];
        _items = [];
        notifyListeners();
        return;
      }
    }

    _isLoading = true;
    notifyListeners();

    try {
      final results = await _fLauncherChannel.getWatchNextItems();
      _allRawItems = results.map((map) => WatchNextItem.fromMap(map)).toList();
      _applyFilterAndNotify();
      unawaited(_preloadInitialPosters());
    } catch (e) {
      debugPrint('WatchNext: Error loading items: $e');
      _allRawItems = [];
      _items = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _applyFilterAndNotify() {
    final excluded = _settingsService?.watchNextExcludedPackages ?? const [];
    final hideWithoutImages = _settingsService?.watchNextHideProgramsWithoutImages ?? false;
    final maxItems = _settingsService?.watchNextMaxItems ?? 0;
    Iterable<WatchNextItem> filtered = _allRawItems.where((item) {
      final pkg = item.packageName;
      if (pkg != null && excluded.contains(pkg)) {
        return false;
      }
      if (hideWithoutImages && !itemHasImage(item)) {
        return false;
      }
      return true;
    });

    if (maxItems > 0) {
      filtered = filtered.take(maxItems);
    }
    _items = filtered.toList();
    // A pending hero change pointed into the old list.
    _heroRequest++;
    _requestedHeroIndex = null;

    if (_activeHeroIndex >= _items.length) {
      _activeHeroIndex = 0;
    }
    _ensureActiveHeroImageLoaded();
    notifyListeners();
  }

  Future<void> _preloadInitialPosters() async {
    final pendingUris = _items
        .map((item) => getPosterUriForItem(item))
        .whereType<String>()
        .where((uri) => !_posterCache.containsKey(uri))
        .toSet()
        .toList(growable: false);

    if (pendingUris.isEmpty) {
      return;
    }

    int nextIndex = 0;
    Future<void> worker() async {
      while (nextIndex < pendingUris.length) {
        final uri = pendingUris[nextIndex++];
        if (uri.startsWith('placeholder://')) {
          final id = int.tryParse(uri.replaceFirst('placeholder://', ''));
          WatchNextItem? found;
          for (final it in _items) {
            if (it.id == id) {
              found = it;
              break;
            }
          }
          if (found != null) {
            _loadPlaceholderForItem(found);
          }
        } else {
          await _loadPosterImage(uri);
        }
      }
    }

    final workers = List.generate(
      _maxParallelPosterLoads,
      (_) => worker(),
    );
    await Future.wait(workers);
  }

  void ensurePosterLoaded(String? uri) {
    if (uri == null || _posterCache.containsKey(uri) || _failedPosters.contains(uri) || _loadingPosters.contains(uri)) {
      return;
    }
    if (uri.startsWith('placeholder://')) {
      final id = int.tryParse(uri.replaceFirst('placeholder://', ''));
      WatchNextItem? found;
      for (final it in _items) {
        if (it.id == id) {
          found = it;
          break;
        }
      }
      if (found != null) {
        _loadPlaceholderForItem(found);
      }
      return;
    }
    unawaited(_loadPosterImage(uri));
  }

  Future<void> _loadPosterImage(String uri) async {
    if (_posterCache.containsKey(uri) || _loadingPosters.contains(uri)) {
      return;
    }
    _loadingPosters.add(uri);
    try {
      Uint8List? imageBytes;

      if (uri.startsWith('content://')) {
        imageBytes = await _fLauncherChannel.loadContentUriImage(uri);
      } else {
        final published = Uri.parse(uri);
        final larger = largerArtworkUri(published);
        imageBytes = await _download(larger);
        // The image server may refuse the size we asked for; the published link still works.
        if ((imageBytes == null || imageBytes.isEmpty) && larger != published) {
          imageBytes = await _download(published);
        }
      }

      if (imageBytes != null && imageBytes.isNotEmpty) {
        _posterCache[uri] = imageBytes;
        _failedPosters.remove(uri);
        _posterRetryAttempt = 0;
        _schedulePosterCacheNotification();
      } else {
        _failedPosters.add(uri);
        if (_settingsService?.watchNextHideProgramsWithoutImages ?? false) {
          _applyFilterAndNotify();
        } else {
          _triggerPlaceholderForUri(uri);
          _schedulePosterCacheNotification();
        }
      }
    } on _PosterUnreachable {
      _schedulePosterRetry(uri);
    } catch (_) {
      _failedPosters.add(uri);
      if (_settingsService?.watchNextHideProgramsWithoutImages ?? false) {
        _applyFilterAndNotify();
      } else {
        _triggerPlaceholderForUri(uri);
        _schedulePosterCacheNotification();
      }
    } finally {
      _loadingPosters.remove(uri);
    }
  }

  /// The picture at [uri], or null when the server answers without it. Throws [_PosterUnreachable]
  /// when no answer comes: no network, a failed name lookup, a timeout.
  Future<Uint8List?> _download(Uri uri) async {
    final http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 10));
    } on Exception {
      throw const _PosterUnreachable();
    }
    return response.statusCode == 200 ? response.bodyBytes : null;
  }

  void _schedulePosterRetry(String uri) {
    _unreachablePosters.add(uri);
    if (_posterRetryTimer?.isActive ?? false) return;
    final delay = posterRetryDelays[_posterRetryAttempt.clamp(0, posterRetryDelays.length - 1)];
    _posterRetryAttempt++;
    _posterRetryTimer = Timer(delay, _retryUnreachablePosters);
  }

  void _retryUnreachablePosters() {
    final shown = _items.map(getPosterUriForItem).toSet();
    final uris = _unreachablePosters.where(shown.contains).toList(growable: false);
    _unreachablePosters.clear();
    for (final uri in uris) {
      unawaited(_loadPosterImage(uri));
    }
  }

  void _triggerPlaceholderForUri(String uri) {
    for (final item in _items) {
      if ((item.backdropUri ?? item.posterUri) == uri) {
        _loadPlaceholderForItem(item);
      }
    }
  }

  void _loadPlaceholderForItem(WatchNextItem item) {
    final key = 'placeholder://${item.id}';
    if (_posterCache.containsKey(key) || _loadingPosters.contains(key)) return;
    _loadingPosters.add(key);
    unawaited(() async {
      try {
        final bytes = await _generatePlaceholder(item);
        if (bytes != null && bytes.isNotEmpty) {
          _posterCache[key] = bytes;
          _schedulePosterCacheNotification();
        }
      } catch (e) {
        debugPrint('WatchNext: Error generating placeholder: $e');
      } finally {
        _loadingPosters.remove(key);
      }
    }());
  }

  Future<Uint8List?> _generatePlaceholder(WatchNextItem item) async {
    const width = 640.0;
    const height = 360.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));
    ui.Image? iconImage;

    // Background gradient (rich cinematic dark palette)
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(width, height),
        const [
          Color(0xFF1E2433),
          Color(0xFF0F121A),
        ],
      );
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), bgPaint);

    // Subtle radial glow in upper center
    final glowPaint = Paint()
      ..shader = ui.Gradient.radial(
        const Offset(width / 2, height * 0.38),
        width * 0.45,
        const [
          Color(0x24FFFFFF),
          Color(0x00000000),
        ],
      );
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), glowPaint);

    // Fetch and draw app icon if available
    bool drewIcon = false;
    if (item.packageName != null && item.packageName!.isNotEmpty) {
      try {
        final iconBytes = await _fLauncherChannel.getApplicationIcon(item.packageName!);
        if (iconBytes.isNotEmpty) {
          final codec = await ui.instantiateImageCodec(iconBytes);
          final frame = await codec.getNextFrame();
          codec.dispose();
          iconImage = frame.image;

          const iconSize = 76.0;
          const iconLeft = (width - iconSize) / 2;
          const iconTop = 72.0;
          final iconRect = Rect.fromLTWH(iconLeft, iconTop, iconSize, iconSize);

          final shadowPaint = Paint()
            ..color = const Color(0x66000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
          canvas.drawRRect(
            RRect.fromRectAndRadius(iconRect.shift(const Offset(0, 4)), const Radius.circular(18)),
            shadowPaint,
          );

          canvas.save();
          canvas.clipRRect(RRect.fromRectAndRadius(iconRect, const Radius.circular(16)));
          canvas.drawImageRect(
            iconImage,
            Rect.fromLTWH(0, 0, iconImage.width.toDouble(), iconImage.height.toDouble()),
            iconRect,
            Paint()..filterQuality = FilterQuality.medium,
          );
          canvas.restore();
          drewIcon = true;
        }
      } catch (_) {}
    }

    if (!drewIcon) {
      final iconPaint = Paint()
        ..color = const Color(0x55FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(const Offset(width / 2, 110), 34, iconPaint);

      final path = Path()
        ..moveTo(width / 2 - 9, 97)
        ..lineTo(width / 2 + 15, 110)
        ..lineTo(width / 2 - 9, 123)
        ..close();
      canvas.drawPath(path, Paint()..color = const Color(0x55FFFFFF));
    }

    // Program title
    final titleSpan = TextSpan(
      text: item.title,
      style: const TextStyle(
        color: Color(0xEEFFFFFF),
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    );
    final titlePainter = TextPainter(
      text: titleSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '...',
    )..layout(maxWidth: width - 80);

    final titleX = (width - titlePainter.width) / 2;
    const titleY = 175.0;
    titlePainter.paint(canvas, Offset(titleX, titleY));

    // Subtle edge border
    final borderPaint = Paint()
      ..color = const Color(0x18FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(const Rect.fromLTWH(0.5, 0.5, width - 1, height - 1), borderPaint);

    titlePainter.dispose();

    // Native image memory is freed here rather than whenever the garbage collector runs.
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(width.toInt(), height.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image?.dispose();
      picture.dispose();
      iconImage?.dispose();
    }
  }

  void _schedulePosterCacheNotification() {
    if (_posterNotifyDebounce?.isActive ?? false) {
      return;
    }
    _posterNotifyDebounce = Timer(const Duration(milliseconds: 80), notifyListeners);
  }

  Uint8List? getCachedPoster(String? uri) {
    if (uri == null) return null;
    return _posterCache[uri];
  }

  bool hasPosterLoadFailed(String? uri) {
    if (uri == null) return false;
    return _failedPosters.contains(uri);
  }

  Future<void> launchItem(WatchNextItem item) async {
    debugPrint('WatchNext: Launching item: ${item.title}');
    debugPrint('WatchNext: packageName=${item.packageName}, contentId=${item.contentId}, intentUri=${item.intentUri}');

    if (item.packageName == null && item.intentUri == null) {
      debugPrint('WatchNext: Cannot launch - no package name or intent URI');
      return;
    }

    await _fLauncherChannel.launchWatchNextItem(
      item.packageName,
      item.contentId,
      item.intentUri,
    );
  }
}

/// A picture download that got no answer from the server.
class _PosterUnreachable implements Exception {
  const _PosterUnreachable();
}
