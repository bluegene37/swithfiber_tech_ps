import 'dart:async';

import 'package:swithfiber_tech_ps/core/network/api_client.dart';

/// Runs before every test file in this directory.
///
/// Screens reach for the Switch Fiber API on build (the RADIUS card looks
/// its subscriber up), and an unstubbed request from a widget test would go
/// to the real server and leave Dio's timers pending in the fake-async zone.
/// The network is switched off here once; a test that mocks the HTTP adapter
/// turns it back on for itself.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ApiClient.blockNetworkForTesting = true;
  await testMain();
}
