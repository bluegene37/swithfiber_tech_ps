import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/network/network_connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<bool> controller;
  late NetworkConnectivityService service;

  setUp(() {
    controller = StreamController<bool>.broadcast();
    service = NetworkConnectivityService();
  });

  tearDown(() async {
    service.dispose();
    await controller.close();
    NetworkConnectivityService.resetInstance();
  });

  group('NetworkConnectivityService Reconnection Tests', () {
    test('emitting false then true triggers registered callbacks', () async {
      service.initialize(connectionStream: controller.stream);

      int callCount = 0;
      service.addOnlineListener(() async {
        callCount++;
      });

      // Emit offline state
      controller.add(false);
      await pumpEventQueue();
      expect(callCount, 0,
          reason: 'Offline event should not trigger listeners');
      expect(service.isConnected, isFalse);

      // Emit online state
      controller.add(true);
      await pumpEventQueue();
      expect(callCount, 1,
          reason: 'Transition from offline to online must trigger listeners');
      expect(service.isConnected, isTrue);
    });

    test('emitting true then true does NOT trigger duplicate executions',
        () async {
      service.initialize(connectionStream: controller.stream);

      int callCount = 0;
      service.addOnlineListener(() async {
        callCount++;
      });

      // First true: false -> true transition
      controller.add(true);
      await pumpEventQueue();
      expect(callCount, 1);

      // Second true: true -> true (no transition)
      controller.add(true);
      await pumpEventQueue();
      expect(callCount, 1,
          reason:
              'Consecutive true events must not trigger duplicate executions');
    });

    test('emitting false then false does NOT trigger callbacks', () async {
      service.initialize(connectionStream: controller.stream);

      int callCount = 0;
      service.addOnlineListener(() async {
        callCount++;
      });

      controller.add(false);
      await pumpEventQueue();
      expect(callCount, 0);

      controller.add(false);
      await pumpEventQueue();
      expect(callCount, 0,
          reason: 'Repeated offline events must not trigger callbacks');
      expect(service.isConnected, isFalse);
    });

    test('multiple listeners are all invoked on reconnect', () async {
      service.initialize(connectionStream: controller.stream);

      final executionOrder = <int>[];
      service.addOnlineListener(() async {
        executionOrder.add(1);
      });
      service.addOnlineListener(() async {
        executionOrder.add(2);
      });
      service.addOnlineListener(() async {
        executionOrder.add(3);
      });

      controller.add(false);
      await pumpEventQueue();
      expect(executionOrder, isEmpty);

      controller.add(true);
      await pumpEventQueue();
      expect(executionOrder, equals([1, 2, 3]),
          reason: 'All registered listeners must be executed on reconnect');
    });

    test('exceptions in a listener are caught and do not halt other listeners',
        () async {
      service.initialize(connectionStream: controller.stream);

      bool listener1Executed = false;
      bool listener2Executed = false;
      bool listener3Executed = false;

      // Listener 1 throws async exception
      service.addOnlineListener(() async {
        listener1Executed = true;
        throw Exception('Simulated network sync failure in listener 1');
      });

      // Listener 2 succeeds
      service.addOnlineListener(() async {
        listener2Executed = true;
      });

      // Listener 3 throws synchronous StateError
      service.addOnlineListener(() {
        listener3Executed = true;
        throw StateError('Simulated sync state error in listener 3');
      });

      controller.add(false);
      controller.add(true);
      await pumpEventQueue();

      expect(listener1Executed, isTrue);
      expect(listener2Executed, isTrue,
          reason: 'Listener 2 must still execute even if listener 1 threw');
      expect(listener3Executed, isTrue,
          reason: 'Listener 3 must still execute');
      expect(service.isConnected, isTrue);
    });

    test('removing a listener prevents it from being called on reconnect',
        () async {
      service.initialize(connectionStream: controller.stream);

      int count1 = 0;
      int count2 = 0;

      Future<void> callback1() async {
        count1++;
      }

      Future<void> callback2() async {
        count2++;
      }

      service.addOnlineListener(callback1);
      final remove2 = service.addOnlineListener(callback2);
      expect(service.listenerCount, 2);

      // Remove callback 1 explicitly
      service.removeOnlineListener(callback1);
      expect(service.listenerCount, 1);

      // Remove callback 2 using returned remover callback
      remove2();
      expect(service.listenerCount, 0);

      controller.add(false);
      controller.add(true);
      await pumpEventQueue();

      expect(count1, 0, reason: 'Removed listener 1 must not be called');
      expect(count2, 0, reason: 'Removed listener 2 must not be called');
    });

    test('disposing cancels the stream subscription and resets state',
        () async {
      // Use single-subscription controller to strictly test subscription cancellation
      final singleController = StreamController<bool>();
      final localService = NetworkConnectivityService();
      localService.initialize(connectionStream: singleController.stream);

      expect(singleController.hasListener, isTrue);
      expect(localService.hasActiveSubscription, isTrue);

      bool calledAfterDispose = false;
      localService.addOnlineListener(() async {
        calledAfterDispose = true;
      });

      localService.dispose();

      expect(singleController.hasListener, isFalse,
          reason: 'dispose() must cancel the underlying stream subscription');
      expect(localService.hasActiveSubscription, isFalse);
      expect(localService.listenerCount, 0);
      expect(localService.isInitialized, isFalse);

      // Stream events emitted after dispose must not trigger listeners
      singleController.add(true);
      await pumpEventQueue();
      expect(calledAfterDispose, isFalse);

      await singleController.close();
    });

    test('transition cycle: online -> offline -> online triggers on restore',
        () async {
      service.initialize(
        connectionStream: controller.stream,
        initialConnected: true,
      );

      int reconnectCount = 0;
      service.addOnlineListener(() async {
        reconnectCount++;
      });

      expect(service.isConnected, isTrue);

      // App drops offline
      controller.add(false);
      await pumpEventQueue();
      expect(service.isConnected, isFalse);
      expect(reconnectCount, 0);

      // App comes back online
      controller.add(true);
      await pumpEventQueue();
      expect(service.isConnected, isTrue);
      expect(reconnectCount, 1);

      // App drops offline again and reconnects
      controller.add(false);
      await pumpEventQueue();
      controller.add(true);
      await pumpEventQueue();
      expect(reconnectCount, 2);
    });

    test('constructor supports dependency injection with connectionStream',
        () async {
      final diService = NetworkConnectivityService(
        connectionStream: controller.stream,
        initialConnected: false,
      );

      bool triggered = false;
      diService.addOnlineListener(() async {
        triggered = true;
      });

      controller.add(false);
      controller.add(true);
      await pumpEventQueue();

      expect(triggered, isTrue);
      diService.dispose();
    });

    test('singleton instance is accessible and can be reset for testing', () {
      final first = NetworkConnectivityService.instance;
      expect(first, isNotNull);

      NetworkConnectivityService.resetInstance();
      final second = NetworkConnectivityService.instance;
      expect(identical(first, second), isFalse);

      NetworkConnectivityService.resetInstance();
    });
  });
}
