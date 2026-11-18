import 'dart:async';

import 'package:flauncher/models/watch_next_item.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// A service holding three items (ids 1, 2, 3) whose posters load from the mocked channel. Each
/// test disposes it before it ends: its timers must be gone before the tester checks for them.
Future<WatchNextService> _serviceWithItems(
  WidgetTester tester, {
  Uint8List? poster,
  String Function(int id)? posterUri,
}) async {
  final channel = MockFLauncherChannel();
  when(channel.checkWatchNextPermission()).thenAnswer((_) async => true);
  when(channel.getWatchNextItems()).thenAnswer(
    (_) async => [
      for (final id in [1, 2, 3])
        {'id': id, 'title': 'Item $id', 'posterUri': posterUri?.call(id) ?? 'content://poster/$id'},
    ],
  );
  when(channel.loadContentUriImage(any)).thenAnswer((_) async => poster ?? Uint8List.fromList([1, 2, 3]));
  final service = WatchNextService(channel);
  await tester.pump();
  expect(service.items.map((item) => item.id), [1, 2, 3]);
  return service;
}

/// A valid 1×1 PNG.
final _onePixelPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82, //
]);

void main() {
  testWidgets('each loaded poster logs its pixel size, byte count and address', (tester) async {
    final logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');

    final service = await _serviceWithItems(tester, poster: _onePixelPng);
    // The header is read by the engine, outside the test's fake clock.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    service.dispose();
    debugPrint = originalDebugPrint;

    expect(logs, contains('Watch Next poster 1x1, ${_onePixelPng.length} bytes: content://poster/1'));
  });

  group('hero switch gate', () {
    testWidgets('without a gate the hero changes at once', (tester) async {
      final service = await _serviceWithItems(tester);

      service.nextHeroItem();

      expect(service.activeHeroIndex, 1);

      service.dispose();
    });

    testWidgets('the hero keeps the shown item until the gate for the next one completes', (tester) async {
      final service = await _serviceWithItems(tester);
      final gates = <int, Completer<void>>{};
      service.heroSwitchGate = (item) => (gates[item.id] = Completer<void>()).future;
      // Poster loads notify too, so record which item each notification carries.
      final notifiedIndexes = <int>[];
      service.addListener(() => notifiedIndexes.add(service.activeHeroIndex));

      service.nextHeroItem();
      await tester.pump(const Duration(milliseconds: 100));
      expect(gates.keys, [2]);
      expect(service.activeHeroIndex, 0);
      expect(service.activeHeroItem?.id, 1);
      expect(notifiedIndexes, everyElement(0));

      gates[2]!.complete();
      await tester.pump();
      expect(service.activeHeroIndex, 1);
      expect(notifiedIndexes.last, 1);

      service.dispose();
    });

    testWidgets('a second press while waiting moves on from the pending item and drops it', (tester) async {
      final service = await _serviceWithItems(tester);
      final gates = <int, Completer<void>>{};
      service.heroSwitchGate = (item) => (gates[item.id] = Completer<void>()).future;

      service.nextHeroItem();
      service.nextHeroItem();
      expect(gates.keys, [2, 3]);

      gates[2]!.complete();
      await tester.pump();
      expect(service.activeHeroIndex, 0, reason: 'item 2 was passed over');

      gates[3]!.complete();
      await tester.pump();
      expect(service.activeHeroIndex, 2);

      service.dispose();
    });

    testWidgets('going back to the shown item cancels the pending change', (tester) async {
      final service = await _serviceWithItems(tester);
      final gates = <int, Completer<void>>{};
      service.heroSwitchGate = (item) => (gates[item.id] = Completer<void>()).future;

      service.nextHeroItem();
      service.prevHeroItem();
      expect(service.activeHeroIndex, 0);

      gates[2]!.complete();
      await tester.pump();
      expect(service.activeHeroIndex, 0);

      service.dispose();
    });

    testWidgets('a gate that never finishes delays the change by at most heroSwitchMaxWait', (tester) async {
      final service = await _serviceWithItems(tester);
      service.heroSwitchGate = (_) => Completer<void>().future;

      service.nextHeroItem();
      await tester.pump(WatchNextService.heroSwitchMaxWait - const Duration(milliseconds: 1));
      expect(service.activeHeroIndex, 0);

      await tester.pump(const Duration(milliseconds: 1));
      expect(service.activeHeroIndex, 1);

      service.dispose();
    });

    testWidgets('a failing gate still changes the hero', (tester) async {
      final service = await _serviceWithItems(tester);
      service.heroSwitchGate = (WatchNextItem _) async => throw StateError('decode failed');

      service.nextHeroItem();
      await tester.pump();

      expect(service.activeHeroIndex, 1);

      service.dispose();
    });
  });

  group('largerArtworkUri', () {
    // Links as Disney+ and HBO Max published them on the TV.
    const disney =
        'https://disney.images.edge.bamgrid.com/ripcut-delivery/v2/variant/disney/'
        '01d201de-d9c0-4d5d-bec1-e52c9019800f/scale?format=webp&height=306&width=544';
    const hbo = 'https://images.cdn.prd.api.discomax.com/0s0V-/3xZZUK6cQqsytW4sA.jpeg?w=600&q=85&p=true&f=jpg';

    test('asks Disney+ for 1920 px, keeping the shape', () {
      expect(
        largerArtworkUri(Uri.parse(disney)).toString(),
        'https://disney.images.edge.bamgrid.com/ripcut-delivery/v2/variant/disney/'
        '01d201de-d9c0-4d5d-bec1-e52c9019800f/scale?format=webp&height=1080&width=1920',
      );
    });

    test('asks HBO Max for 1920 px', () {
      expect(
        largerArtworkUri(Uri.parse(hbo)).toString(),
        'https://images.cdn.prd.api.discomax.com/0s0V-/3xZZUK6cQqsytW4sA.jpeg?w=1920&q=85&p=true&f=jpg',
      );
    });

    test('leaves other links alone', () {
      for (final link in [
        // Netflix: no size in the link. SkyShowtime: already 3840 px.
        'https://occ-0-3375-1489.1.nflxso.net/dnm/api/v6/abc/AAAAB.jpg?client=det&deviceTypeId=5677&platform=sbn',
        'https://pixel.disco.skyshowtime.com/uuid/960f4cf2/LAND_16_9?language=en-US&proposition=SKYSHOWTIME',
        // Already large enough, or no usable size.
        'https://disney.images.edge.bamgrid.com/ripcut-delivery/v2/variant/disney/x/scale?width=3840&height=2160',
        'https://disney.images.edge.bamgrid.com/ripcut-delivery/v2/variant/disney/x/scale?format=webp',
        'https://images.cdn.prd.api.discomax.com/a/b.jpeg?w=2560',
        'https://images.cdn.prd.api.discomax.com/a/b.jpeg?q=85',
      ]) {
        expect(largerArtworkUri(Uri.parse(link)).toString(), link);
      }
    });
  });

  group('poster download', () {
    const published = 'https://images.cdn.prd.api.discomax.com/a/b.jpeg?w=600';
    const larger = 'https://images.cdn.prd.api.discomax.com/a/b.jpeg?w=1920';

    Future<(WatchNextService, List<String>)> load(WidgetTester tester, {required bool largerAvailable}) async {
      final requested = <String>[];
      late WatchNextService service;
      await http.runWithClient(
        () async {
          service = await _serviceWithItems(tester, posterUri: (_) => published);
          await tester.pump();
        },
        () => MockClient((request) async {
          requested.add(request.url.toString());
          final url = request.url.toString();
          if (url == larger && largerAvailable) return http.Response.bytes([1, 9, 2, 0], 200);
          if (url == published) return http.Response.bytes([6, 0, 0], 200);
          return http.Response('', 404);
        }),
      );
      return (service, requested);
    }

    testWidgets('downloads the 1920 px image and keeps it under the published link', (tester) async {
      final (service, requested) = await load(tester, largerAvailable: true);

      expect(requested, [larger]);
      expect(service.getCachedPoster(published), [1, 9, 2, 0]);
      service.dispose();
    });

    testWidgets('falls back to the published image when the larger one is refused', (tester) async {
      final (service, requested) = await load(tester, largerAvailable: false);

      expect(requested, [larger, published]);
      expect(service.getCachedPoster(published), [6, 0, 0]);
      service.dispose();
    });
  });
}
