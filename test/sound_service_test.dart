import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/services/sound_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SoundService Tests', () {
    late SoundService service;

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global'),
        (MethodCall methodCall) async => 1,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'),
        (MethodCall methodCall) async => 1,
      );
      service = SoundService();
    });

    tearDown(() async {
      await service.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers.global'),
        null,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'),
        null,
      );
    });

    test('initializes with default enabled state', () {
      expect(service.isEnabled, isTrue);
    });

    test('respects isEnabled = false without throwing', () async {
      service.isEnabled = false;
      await expectLater(service.playAlertSound(), completes);
    });

    test('playAlertSound handles headless test environment without throwing',
        () async {
      await expectLater(service.playAlertSound(), completes);
    });

    test('dispose safely closes player reference', () async {
      // Trigger lazy getter
      expect(service.player, isNotNull);
      await service.dispose();
      // Next call creates fresh player
      expect(service.player, isNotNull);
    });
  });
}
