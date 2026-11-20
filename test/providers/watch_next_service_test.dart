import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flauncher/models/watch_next_item.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// A service holding three items (ids 1, 2, 3) whose posters load from the mocked channel. Each
/// test disposes it before it ends: its timers must be gone before the tester checks for them.
Future<WatchNextService> _serviceWithItems(
  WidgetTester tester, {
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
  when(channel.loadContentUriImage(any)).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
  final service = WatchNextService(channel);
  await tester.pump();
  expect(service.items.map((item) => item.id), [1, 2, 3]);
  return service;
}

void main() {
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

  group('unreachable pictures', () {
    const uri = 'https://occ-0-3375-1489.1.nflxso.net/dnm/api/v6/a.jpg';

    /// Runs [body] with a network that fails until [online] is set, counting the requests.
    Future<void> withNetwork(
      WidgetTester tester,
      Future<void> Function(WatchNextService service, List<String> requested, void Function() goOnline) body,
    ) async {
      final requested = <String>[];
      var online = false;
      await http.runWithClient(
        () async {
          final service = await _serviceWithItems(tester, posterUri: (_) => uri);
          await tester.pump();
          await body(service, requested, () => online = true);
          service.dispose();
        },
        () => MockClient((request) async {
          requested.add(request.url.toString());
          if (!online) throw http.ClientException('Failed host lookup', request.url);
          return http.Response.bytes([4, 2], 200);
        }),
      );
    }

    testWidgets('keep the item on its picture, not a placeholder, while the network is down', (tester) async {
      await withNetwork(tester, (service, requested, _) async {
        final item = service.items.first;

        expect(requested, [uri]);
        expect(service.getPosterUriForItem(item), uri);
        expect(service.getCachedPoster(uri), isNull);
        expect(service.hasPosterLoadFailed(uri), isFalse);
        expect(service.itemHasImage(item), isTrue);
      });
    });

    testWidgets('are downloaded again until the network is back', (tester) async {
      await withNetwork(tester, (service, requested, goOnline) async {
        await tester.pump(WatchNextService.posterRetryDelays[0] - const Duration(milliseconds: 1));
        expect(requested, hasLength(1));

        await tester.pump(const Duration(milliseconds: 1));
        expect(requested, hasLength(2));

        goOnline();
        await tester.pump(WatchNextService.posterRetryDelays[1]);
        expect(requested, hasLength(3));
        expect(service.getCachedPoster(uri), [4, 2]);

        await tester.pump(const Duration(minutes: 1));
        expect(requested, hasLength(3));
      });
    });

    testWidgets('a picture the server refuses still gets the placeholder', (tester) async {
      final requested = <String>[];
      await http.runWithClient(
        () async {
          final service = await _serviceWithItems(tester, posterUri: (_) => uri);
          await tester.pump();

          expect(service.hasPosterLoadFailed(uri), isTrue);
          expect(service.getPosterUriForItem(service.items.first), 'placeholder://1');

          await tester.pump(const Duration(minutes: 1));
          expect(requested, [uri]);
          service.dispose();
        },
        () => MockClient((request) async {
          requested.add(request.url.toString());
          return http.Response('', 404);
        }),
      );
    });
  });

  group('placeholder poster', () {
    Future<Uint8List> pngOf(int size) async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawColor(const ui.Color(0xFF3366CC), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(size, size);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      return bytes!.buffer.asUint8List();
    }

    testWidgets('renders a PNG for items without artwork, with and without an app icon', (tester) async {
      const pngSignature = [0x89, 0x50, 0x4E, 0x47];
      late WatchNextService service;
      await tester.runAsync(() async {
        final icon = await pngOf(48);
        final channel = MockFLauncherChannel();
        when(channel.checkWatchNextPermission()).thenAnswer((_) async => true);
        when(channel.getWatchNextItems()).thenAnswer(
          (_) async => [
            {'id': 1, 'title': 'With icon', 'packageName': 'app.with.icon'},
            {'id': 2, 'title': 'Without icon', 'packageName': 'app.without.icon'},
          ],
        );
        when(channel.getApplicationIcon('app.with.icon')).thenAnswer((_) async => icon);
        when(channel.getApplicationIcon('app.without.icon')).thenAnswer((_) async => Uint8List(0));
        service = WatchNextService(channel);
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while ((service.getCachedPoster('placeholder://1') == null ||
                service.getCachedPoster('placeholder://2') == null) &&
            DateTime.now().isBefore(deadline)) {
          service.ensurePosterLoaded('placeholder://1');
          service.ensurePosterLoaded('placeholder://2');
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });

      expect(service.getCachedPoster('placeholder://1')?.take(4), pngSignature);
      expect(service.getCachedPoster('placeholder://2')?.take(4), pngSignature);
      expect(service.getCachedPoster('placeholder://1'), isNot(service.getCachedPoster('placeholder://2')));
      service.dispose();
    });
  });
}
