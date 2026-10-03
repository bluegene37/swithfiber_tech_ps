import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/services/badge_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BadgeService Tests', () {
    late BadgeService service;

    setUp(() {
      service = BadgeService();
    });

    test('initializes with default enabled state', () {
      expect(service.isEnabled, isTrue);
    });

    test('respects isEnabled = false without throwing', () async {
      service.isEnabled = false;
      await expectLater(service.updateBadgeCount(5), completes);
    });

    test('updateBadgeCount handles test environment safely', () async {
      await expectLater(service.updateBadgeCount(3), completes);
      await expectLater(service.updateBadgeCount(0), completes);
    });

    test('removeBadge completes safely', () async {
      await expectLater(service.removeBadge(), completes);
    });
  });
}
