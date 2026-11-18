import 'package:flauncher/models/watch_next_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeProgressPercent', () {
    test('is the watched share when both position and duration are known', () {
      expect(computeProgressPercent(30 * 60000, 60 * 60000), 50);
      expect(computeProgressPercent(1, 3), 33);
    });

    test('is null when the position or the duration is missing or not positive', () {
      expect(computeProgressPercent(null, 60000), isNull);
      expect(computeProgressPercent(30000, null), isNull);
      expect(computeProgressPercent(0, 60000), isNull);
      expect(computeProgressPercent(30000, 0), isNull);
      expect(computeProgressPercent(-5, 60000), isNull);
    });

    test('stays within 0..100 when the position is past the end', () {
      expect(computeProgressPercent(90000, 60000), 100);
    });
  });

  group('WatchNextItem.fromMap', () {
    test('reads the episode, playback and genre fields', () {
      final item = WatchNextItem.fromMap({
        'id': 7,
        'title': 'The Office (U.S.)',
        'duration': 22 * 60000,
        'playbackPosition': 13 * 60000,
        'season': '5',
        'episode': '12',
        'genres': ['COMEDY'],
        'releaseDate': '2005-03-24',
        'programType': kWatchNextTypeTvEpisode,
      });

      expect(item.seasonNumber, '5');
      expect(item.episodeNumber, '12');
      expect(item.playbackPositionMillis, 13 * 60000);
      expect(item.progressPercent, 59);
      expect(item.remaining, const Duration(minutes: 9));
      expect(item.genres, ['COMEDY']);
      expect(item.releaseDate, '2005-03-24');
      expect(item.programType, kWatchNextTypeTvEpisode);
    });

    test('treats absent and empty values as missing', () {
      final item = WatchNextItem.fromMap({
        'id': 1,
        'title': 'Something',
        'duration': 0,
        'playbackPosition': null,
        'season': '  ',
        'episode': '',
        'genres': ['', ' '],
        'releaseDate': '',
        'programType': null,
      });

      expect(item.seasonNumber, isNull);
      expect(item.episodeNumber, isNull);
      expect(item.playbackPositionMillis, isNull);
      expect(item.duration, isNull);
      expect(item.progressPercent, isNull);
      expect(item.remaining, isNull);
      expect(item.genres, isEmpty);
      expect(item.releaseDate, isNull);
      expect(item.programType, isNull);
    });

    test('has no progress when only the duration is known', () {
      final item = WatchNextItem.fromMap({'id': 1, 'title': 'Movie', 'duration': 90 * 60000});
      expect(item.progressPercent, isNull);
      expect(item.remaining, isNull);
    });

    test('survives a round trip through toMap', () {
      final item = WatchNextItem.fromMap({
        'id': 2,
        'title': 'Show',
        'duration': 40 * 60000,
        'playbackPosition': 10 * 60000,
        'season': '2',
        'episode': '3',
        'genres': ['DRAMA'],
        'releaseDate': '2024',
        'programType': kWatchNextTypeTvEpisode,
      });
      final copy = WatchNextItem.fromMap(item.toMap());
      expect(copy.toMap(), item.toMap());
    });
  });
}
