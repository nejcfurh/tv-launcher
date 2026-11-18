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

/// `TvContract.WatchNextPrograms.COLUMN_TYPE` values.
const kWatchNextTypeMovie = 0;
const kWatchNextTypeTvSeries = 1;
const kWatchNextTypeTvSeason = 2;
const kWatchNextTypeTvEpisode = 3;

/// Watched share in percent, or null unless both the position and the duration are known (> 0).
int? computeProgressPercent(int? positionMillis, int? durationMillis) {
  if (positionMillis == null || durationMillis == null || positionMillis <= 0 || durationMillis <= 0) {
    return null;
  }
  return (positionMillis * 100 / durationMillis).round().clamp(0, 100);
}

class WatchNextItem {
  final int id;
  final String title;
  final String? description;
  final String? posterUri;
  final String? backdropUri;
  final String? packageName;
  final String? contentId;
  final int? progressPercent;
  final int? duration;
  final DateTime? lastEngagementDate;
  final String? intentUri;
  final int? watchNextType;
  final String? aspectRatio;

  /// Season and episode as the app displays them (they can be "1A", "Special"...).
  final String? seasonNumber;
  final String? episodeNumber;
  final int? playbackPositionMillis;

  /// Canonical genre constants (`TvContract.Programs.Genres`), such as COMEDY.
  final List<String> genres;
  final String? releaseDate;

  /// One of the kWatchNextType* values, or null when the app did not say.
  final int? programType;

  WatchNextItem({
    required this.id,
    required this.title,
    this.description,
    this.posterUri,
    this.backdropUri,
    this.packageName,
    this.contentId,
    this.progressPercent,
    this.duration,
    this.lastEngagementDate,
    this.intentUri,
    this.watchNextType,
    this.aspectRatio,
    this.seasonNumber,
    this.episodeNumber,
    this.playbackPositionMillis,
    this.genres = const [],
    this.releaseDate,
    this.programType,
  });

  bool get hasImage {
    final poster = posterUri?.trim();
    final backdrop = backdropUri?.trim();
    return (poster != null && poster.isNotEmpty) || (backdrop != null && backdrop.isNotEmpty);
  }

  /// Time left to watch, or null unless both the position and the duration are known.
  Duration? get remaining {
    final position = playbackPositionMillis;
    final total = duration;
    if (position == null || total == null || position <= 0 || total <= 0) {
      return null;
    }
    return Duration(milliseconds: (total - position).clamp(0, total));
  }

  factory WatchNextItem.fromMap(Map<dynamic, dynamic> map) {
    final duration = _positiveInt(map['duration']);
    final position = _positiveInt(map['playbackPosition']);
    return WatchNextItem(
      id: map['id'] ?? 0,
      title: map['title'] ?? '',
      description: map['description'],
      posterUri: map['posterUri'],
      backdropUri: map['backdropUri'],
      packageName: map['packageName'],
      contentId: map['contentId'],
      progressPercent: computeProgressPercent(position, duration) ?? _positiveInt(map['progressPercent']),
      duration: duration,
      lastEngagementDate: map['lastEngagementDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastEngagementDate'])
          : null,
      intentUri: map['intentUri'],
      watchNextType: map['watchNextType'],
      aspectRatio: map['aspectRatio'],
      seasonNumber: _nonBlank(map['season']),
      episodeNumber: _nonBlank(map['episode']),
      playbackPositionMillis: position,
      genres: [
        for (final genre in (map['genres'] as List?) ?? const [])
          if (_nonBlank(genre) case final value?) value,
      ],
      releaseDate: _nonBlank(map['releaseDate']),
      programType: map['programType'] is int ? map['programType'] : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'posterUri': posterUri,
      'backdropUri': backdropUri,
      'packageName': packageName,
      'contentId': contentId,
      'progressPercent': progressPercent,
      'duration': duration,
      'lastEngagementDate': lastEngagementDate?.millisecondsSinceEpoch,
      'intentUri': intentUri,
      'watchNextType': watchNextType,
      'aspectRatio': aspectRatio,
      'season': seasonNumber,
      'episode': episodeNumber,
      'playbackPosition': playbackPositionMillis,
      'genres': genres,
      'releaseDate': releaseDate,
      'programType': programType,
    };
  }
}

String? _nonBlank(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _positiveInt(Object? value) => value is int && value > 0 ? value : null;
