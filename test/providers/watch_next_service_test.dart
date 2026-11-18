import 'dart:async';
import 'dart:typed_data';

import 'package:flauncher/models/watch_next_item.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

/// A service holding three items (ids 1, 2, 3) whose posters load from the mocked channel. Each
/// test disposes it before it ends: its timers must be gone before the tester checks for them.
Future<WatchNextService> _serviceWithItems(WidgetTester tester) async {
  final channel = MockFLauncherChannel();
  when(channel.checkWatchNextPermission()).thenAnswer((_) async => true);
  when(channel.getWatchNextItems()).thenAnswer(
    (_) async => [
      for (final id in [1, 2, 3]) {'id': id, 'title': 'Item $id', 'posterUri': 'content://poster/$id'},
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
}
