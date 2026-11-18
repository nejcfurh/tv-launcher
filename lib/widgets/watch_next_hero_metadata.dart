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

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/watch_next_item.dart';

const kHeroMetaSeparator = ' · ';

/// Display names for `TvContract.Programs.Genres` constants. MOVIES and PREMIER say what the
/// program is rather than its genre, so they are not shown.
const Map<String, String> kCanonicalGenreLabels = {
  'ANIMAL_WILDLIFE': 'Animals & wildlife',
  'ARTS': 'Arts',
  'COMEDY': 'Comedy',
  'DRAMA': 'Drama',
  'EDUCATION': 'Education',
  'ENTERTAINMENT': 'Entertainment',
  'FAMILY_KIDS': 'Family & kids',
  'GAMING': 'Gaming',
  'LIFE_STYLE': 'Lifestyle',
  'MUSIC': 'Music',
  'NEWS': 'News',
  'SHOPPING': 'Shopping',
  'SPORTS': 'Sports',
  'TECH_SCIENCE': 'Tech & science',
  'TRAVEL': 'Travel',
};

/// The hero's two metadata rows. A row is null when none of its fields is known, so the hero
/// removes it and moves the rows below up.
typedef HeroMetadata = ({String? line1, String? line2});

/// Builds the hero metadata from what the Watch Next provider gave. Missing fields are left out,
/// never shown empty. Series years and season count are not in the provider, so a series' second
/// row only ever shows the genre.
///
/// Series: `Season s · Episode e · n min left` / `genre`.
/// Movie and anything else: `n min left` / `genre · year · runtime`.
HeroMetadata heroMetadata(WatchNextItem item, AppLocalizations l10n) {
  final isSeries = switch (item.programType) {
    kWatchNextTypeTvSeries || kWatchNextTypeTvSeason || kWatchNextTypeTvEpisode => true,
    kWatchNextTypeMovie => false,
    _ => item.seasonNumber != null || item.episodeNumber != null,
  };

  final remaining = item.remaining;
  final timeLeft = remaining != null && remaining > Duration.zero
      ? l10n.watchNextTimeLeft(formatHeroDuration(remaining, l10n))
      : null;
  final genre = heroGenreLabel(item.genres);

  final List<String?> line1;
  final List<String?> line2;
  if (isSeries) {
    line1 = [
      if (item.seasonNumber case final season?) l10n.watchNextSeason(season),
      if (item.episodeNumber case final episode?) l10n.watchNextEpisode(episode),
      timeLeft,
    ];
    line2 = [genre];
  } else {
    final runtime = item.duration;
    line1 = [timeLeft];
    line2 = [
      genre,
      releaseYear(item.releaseDate),
      if (runtime != null && runtime > 0) formatHeroDuration(Duration(milliseconds: runtime), l10n),
    ];
  }
  return (line1: joinHeroMeta(line1), line2: joinHeroMeta(line2));
}

/// Joins the present fields with " · ", or null when none is present.
String? joinHeroMeta(Iterable<String?> fields) {
  final present = fields.whereType<String>().where((field) => field.trim().isNotEmpty).toList();
  return present.isEmpty ? null : present.join(kHeroMetaSeparator);
}

/// "9 min", "1 h 12 min" or "2 h". Partial minutes round up, so a few seconds left read "1 min".
String formatHeroDuration(Duration duration, AppLocalizations l10n) {
  final totalMinutes = (duration.inSeconds / 60).ceil().clamp(1, 1 << 31);
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) {
    return l10n.durationMinutes(minutes);
  }
  if (minutes == 0) {
    return l10n.durationHours(hours);
  }
  return '${l10n.durationHours(hours)} ${l10n.durationMinutes(minutes)}';
}

/// First genre that has a display name, or null.
String? heroGenreLabel(List<String> canonicalGenres) {
  for (final genre in canonicalGenres) {
    final label = kCanonicalGenreLabels[genre.trim().toUpperCase()];
    if (label != null) {
      return label;
    }
  }
  return null;
}

/// The year of a release date written as "yyyy" or "yyyy-mm-dd", or null.
String? releaseYear(String? releaseDate) {
  final match = RegExp(r'^\s*(\d{4})(?:\D|$)').firstMatch(releaseDate ?? '');
  return match?.group(1);
}
