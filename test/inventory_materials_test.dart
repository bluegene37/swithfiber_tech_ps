// Gene - Oct 24, 2026: Comprehensive test suite for InventoryItemDto and CatalogService materials integration.
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/features/catalogs/models/catalog_model.dart';
import 'package:swithfiber_tech_ps/features/catalogs/services/catalog_service.dart';

void main() {
  group('InventoryItemDto Model Tests', () {
    test('parses InventoryItem from live API JSON correctly', () {
      final json = {
        'id': 64,
        'itemId': 'ITEM_FC6S',
        'name': 'Fiber Optic Cleaver FC-6S',
        'description':
            'Precision high-durability fiber cleaver for FTTH drop cable and fast connector splicing.',
        'supplier': 'Sumitomo Electric',
        'quantity': 15,
        'image': 'https://picsum.photos/id/237/200/300',
        'category': 'Tools',
        'userEmail': 'admin@switchfiber.com',
        'modifiedDate': '2026-10-20T22:38:12.590',
      };

      final item = InventoryItemDto.fromJson(json);
      expect(item.id, 64);
      expect(item.itemId, 'ITEM_FC6S');
      expect(item.name, 'Fiber Optic Cleaver FC-6S');
      expect(item.description, contains('Precision high-durability'));
      expect(item.supplier, 'Sumitomo Electric');
      expect(item.quantity, 15);
      expect(item.image, 'https://picsum.photos/id/237/200/300');
      expect(item.category, 'Tools');
      expect(item.userEmail, 'admin@switchfiber.com');
      expect(item.modifiedDate, isNotNull);

      final outJson = item.toJson();
      expect(outJson['id'], 64);
      expect(outJson['itemId'], 'ITEM_FC6S');
      expect(outJson['name'], 'Fiber Optic Cleaver FC-6S');
      expect(outJson['quantity'], 15);
    });

    test('handles missing or string quantity and null fields gracefully', () {
      final json = {
        'id': '76',
        'itemId': 'ITEM-01',
        'name': 'Test Item',
        'quantity': '12',
        'image': null,
        'category': null,
      };

      final item = InventoryItemDto.fromJson(json);
      expect(item.id, 76);
      expect(item.itemId, 'ITEM-01');
      expect(item.name, 'Test Item');
      expect(item.quantity, 12);
      expect(item.image, isNull);
      expect(item.category, isNull);
    });
  });

  group('CatalogService Inventory & Materials Tests', () {
    test('fallbackMaterials and fallbackInventoryItems are populated', () {
      expect(CatalogService.fallbackMaterials, isNotEmpty);
      expect(CatalogService.fallbackInventoryItems, isNotEmpty);
      expect(CatalogService.fallbackInventoryItems.length,
          CatalogService.fallbackMaterials.length);
      expect(CatalogService.fallbackMaterials, contains('Drop Cable (m)'));
      expect(
          CatalogService.fallbackMaterials, contains('SC/APC Fast Connector'));
    });

    test(
        'getMaterials returns all materials without filtering by category/type',
        () async {
      final catalog = CatalogService();
      final materials = await catalog.getMaterials();
      expect(materials, isNotEmpty);
      expect(materials, contains('Drop Cable (m)'));
      expect(materials, contains('SC/APC Fast Connector'));
      expect(materials, contains('S-Clamp'));
      // Verify no duplicates
      expect(materials.toSet().length, materials.length);
    });

    test('getInventoryItems provides fallback items when offline', () async {
      final catalog = CatalogService();
      final items = await catalog.getInventoryItems();
      expect(items, isNotEmpty);
      expect(items.any((i) => i.name.contains('Drop Cable')), isTrue);
    });
  });
}
