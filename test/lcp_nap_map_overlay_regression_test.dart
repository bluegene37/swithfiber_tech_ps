// Regression: ISSUE-001 — Plant map cluster badges hid under the top overlay
// (place search, GPS notice, legend row) after the initial fit and after
// zooming into a cluster, because every camera fit padded 48px from the map
// edge instead of from the bottom of the overlay.
// Found by /qa on 2026-09-20
// Report: .gstack/qa-reports/qa-report-switchfiber-tech-ios-simulator-2026-09-20.md
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/core/database/daos/lcp_nap_dao.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/repositories/lcp_nap_repository.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/signals/lcp_nap_signals.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/widgets/lcp_nap_map_view.dart';

/// A 1x1 transparent PNG, so tests never touch the network for tiles.
final _blankTile = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _OfflineTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(Uint8List.fromList(_blankTile));
}

void main() {
  late AppDatabase db;
  late LcpNapRepository repository;
  late LcpNapSignals signals;

  setUp(() {
    db = AppDatabase.forTesting();
    repository = LcpNapRepository(LcpNapLocationsDao(db));
    signals = LcpNapSignals(repository);
  });

  tearDown(() async {
    await signals.dispose();
    await db.close();
  });

  Future<void> pumpMap(WidgetTester tester) async {
    await tester.runAsync(() async {
      await repository.seedSampleLocations();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 700,
            child: LcpNapMapView(
              signals: signals,
              tileProvider: _OfflineTileProvider(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The first fit is deferred to onMapReady and a post-frame callback.
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Every marker on the map right now: cluster badges and single pins.
  Iterable<Rect> markerRects(WidgetTester tester) {
    final markers = find.byWidgetPredicate((w) =>
        w is GestureDetector &&
        w.key != null &&
        (w.key == const Key('lcpNapCluster') ||
            (w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith('lcpNapPin_'))));
    return markers
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)));
  }

  testWidgets('the first fit keeps every pin below the top overlay',
      (tester) async {
    await pumpMap(tester);

    final overlay = tester.getRect(find.byKey(const Key('lcpNapMapOverlay')));
    final rects = markerRects(tester).toList();
    expect(rects, isNotEmpty);

    for (final r in rects) {
      expect(r.top, greaterThanOrEqualTo(overlay.bottom),
          reason: 'a pin at $r sits under the overlay ending at '
              '${overlay.bottom}; the fit must pad for the overlay height');
    }
  });

  testWidgets('zooming into a cluster keeps its members below the overlay',
      (tester) async {
    await pumpMap(tester);

    final cluster = find.byKey(const Key('lcpNapCluster'));
    expect(cluster, findsWidgets);
    await tester.tap(cluster.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final overlay = tester.getRect(find.byKey(const Key('lcpNapMapOverlay')));
    final rects = markerRects(tester).toList();
    expect(rects, isNotEmpty);

    for (final r in rects) {
      expect(r.top, greaterThanOrEqualTo(overlay.bottom),
          reason: 'after a cluster zoom a pin at $r sits under the overlay '
              'ending at ${overlay.bottom}');
    }
  });
}
