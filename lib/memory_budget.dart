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
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Decoded images kept in Flutter's image cache. Images on screen stay alive whatever the limit;
/// this bounds the ones kept for later (the wallpaper behind the hero, tiles scrolled away). The
/// default is 100 MB, a large share of a 2 GB TV that also runs the streaming apps.
const int kImageCacheMaxBytes = 30 << 20;

/// GPU resource cache, in full screens of RGBA pixels. Flutter's default is 12 screens (about
/// 100 MB at 1920x1080), sized for phones; the home screen draws a handful of full-screen layers.
const int kGpuResourceCacheScreens = 4;

/// Smallest GPU resource cache, for a screen size that is not known yet.
const int kGpuResourceCacheMinBytes = 24 << 20;

int gpuResourceCacheBytes(ui.Size physicalScreen) =>
    max(kGpuResourceCacheMinBytes, (physicalScreen.width * physicalScreen.height * 4 * kGpuResourceCacheScreens).round());

/// Keeps the launcher's caches small: it stays in memory next to whatever the TV is playing.
Future<void> applyMemoryBudget(ui.Size physicalScreen) async {
  PaintingBinding.instance.imageCache.maximumSizeBytes = kImageCacheMaxBytes;
  try {
    await SystemChannels.skia.invokeMethod<void>('Skia.setResourceCacheMaxBytes', gpuResourceCacheBytes(physicalScreen));
  } on Exception {
    // Not every renderer takes the setting; the default stays.
  }
}
