import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/watch_next_item.dart';
import 'package:flauncher/widgets/watch_next_hero_metadata.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  WatchNextItem item({
    int? programType,
    String? season,
    String? episode,
    int? durationMinutes,
    int? positionMinutes,
    List<String> genres = const [],
    String? releaseDate,
  }) =>
      WatchNextItem(
        id: 1,
        title: 'Title',
        programType: programType,
        seasonNumber: season,
        episodeNumber: episode,
        duration: durationMinutes != null ? durationMinutes * 60000 : null,
        playbackPositionMillis: positionMinutes != null ? positionMinutes * 60000 : null,
        genres: genres,
        releaseDate: releaseDate,
      );

  group('heroMetadata', () {
    test('series: season, episode and time left, then the genre', () {
      final meta = heroMetadata(
        item(
          programType: kWatchNextTypeTvEpisode,
          season: '5',
          episode: '12',
          durationMinutes: 22,
          positionMinutes: 13,
          genres: ['COMEDY'],
          releaseDate: '2008-12-04',
        ),
        l10n,
      );
      expect(meta.line1, 'Season 5 · Episode 12 · 9 min left');
      // Series years and season count are not in Watch Next, so only the genre is shown.
      expect(meta.line2, 'Comedy');
    });

    test('series without a playback position leaves out the time left', () {
      final meta = heroMetadata(
        item(programType: kWatchNextTypeTvEpisode, season: '5', episode: '12', durationMinutes: 22),
        l10n,
      );
      expect(meta.line1, 'Season 5 · Episode 12');
      expect(meta.line2, isNull);
    });

    test('movie: time left, then genre, year and runtime', () {
      final meta = heroMetadata(
        item(
          programType: kWatchNextTypeMovie,
          durationMinutes: 138,
          positionMinutes: 66,
          genres: ['MOVIES', 'DRAMA'],
          releaseDate: '2024-05-01',
        ),
        l10n,
      );
      expect(meta.line1, '1 h 12 min left');
      expect(meta.line2, 'Drama · 2024 · 2 h 18 min');
    });

    test('a row with no known field is null', () {
      final meta = heroMetadata(item(), l10n);
      expect(meta.line1, isNull);
      expect(meta.line2, isNull);
    });

    test('a movie with only a genre keeps just the second row', () {
      final meta = heroMetadata(item(programType: kWatchNextTypeMovie, genres: ['DRAMA']), l10n);
      expect(meta.line1, isNull);
      expect(meta.line2, 'Drama');
    });

    test('an item without a type but with an episode number reads as a series', () {
      final meta = heroMetadata(item(episode: '3', durationMinutes: 40, positionMinutes: 10), l10n);
      expect(meta.line1, 'Episode 3 · 30 min left');
    });

    test('watched to the end shows no time left', () {
      final meta = heroMetadata(item(programType: kWatchNextTypeMovie, durationMinutes: 90, positionMinutes: 90), l10n);
      expect(meta.line1, isNull);
    });
  });

  group('formatHeroDuration', () {
    test('minutes, hours, and both', () {
      expect(formatHeroDuration(const Duration(minutes: 9), l10n), '9 min');
      expect(formatHeroDuration(const Duration(hours: 2), l10n), '2 h');
      expect(formatHeroDuration(const Duration(hours: 1, minutes: 12), l10n), '1 h 12 min');
    });

    test('rounds partial minutes up, so a few seconds read as 1 min', () {
      expect(formatHeroDuration(const Duration(seconds: 5), l10n), '1 min');
      expect(formatHeroDuration(const Duration(minutes: 8, seconds: 1), l10n), '9 min');
    });
  });

  test('joinHeroMeta drops missing and blank fields', () {
    expect(joinHeroMeta(['A', null, ' ', 'B']), 'A · B');
    expect(joinHeroMeta([null, '']), isNull);
  });

  test('heroGenreLabel skips program kinds and unknown values', () {
    expect(heroGenreLabel(['MOVIES', 'PREMIER', 'COMEDY']), 'Comedy');
    expect(heroGenreLabel(['NOT_A_GENRE']), isNull);
    expect(heroGenreLabel([]), isNull);
  });

  test('releaseYear reads yyyy and yyyy-mm-dd only', () {
    expect(releaseYear('2024'), '2024');
    expect(releaseYear('2005-03-24'), '2005');
    expect(releaseYear('March 2005'), isNull);
    expect(releaseYear(null), isNull);
  });
}
