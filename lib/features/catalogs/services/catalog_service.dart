import '../../../core/database/daos/lookups_dao.dart';
import '../../../core/network/api_client.dart';
import '../models/catalog_model.dart';

/// Service managing official ISP subscription plans and approved ONT/router hardware models.
class CatalogService {
  static final CatalogService instance = CatalogService._internal();
  final ApiClient _api;
  // Gene - Nov, 28, 2026: Back CatalogService with local-only PowerSync v12 lookup tables for full offline availability.
  LookupsDao? _lookupsDao;

  CatalogService._internal([ApiClient? api]) : _api = api ?? ApiClient.instance;

  factory CatalogService({ApiClient? api, LookupsDao? lookupsDao}) {
    if (api == null && lookupsDao == null) return instance;
    return CatalogService._internal(api).._lookupsDao = lookupsDao;
  }

  void attachLookupsDao(LookupsDao? dao) {
    _lookupsDao = dao;
  }

  void invalidateCache() {
    _cachedPlans = null;
    _cachedRouters = null;
    _cachedLcps = null;
    _cachedNaps = null;
    _cachedPorts = null;
    _cachedInventoryItems = null;
    _cachedMaterials = null;
    _cachedTechnicians = null;
  }

  List<PlanDto>? _cachedPlans;
  List<RouterDto>? _cachedRouters;
  // Gene - Oct 12, 2026: Cached LCPs for LCP-first hierarchical selection.
  List<LcpOptionDto>? _cachedLcps;

  /// Bundled fallback plans matching the live Switch Fiber database
  static const List<PlanDto> fallbackPlans = [
    PlanDto(
      id: 1,
      name: 'SwitchLite - P699',
      description: 'SwitchLite - P699 Up to 50 Mbps',
      amount: 699.0,
      discountId: 1,
    ),
    PlanDto(
      id: 2,
      name: 'SwitchConnect - P799',
      description: 'SwitchConnect - P799 Up to 90 Mbps',
      amount: 799.0,
      discountId: 1,
    ),
    PlanDto(
      id: 3,
      name: 'SwitchNet - P999',
      description: 'SwitchNet - P999 Up to 120 Mbps',
      amount: 999.0,
      discountId: 1,
    ),
    PlanDto(
      id: 4,
      name: 'SwitchSpeed - P1299',
      description: 'SwitchSpeed - P1299 Up to 150 Mbps',
      amount: 1299.0,
      discountId: 1,
    ),
    PlanDto(
      id: 5,
      name: 'SwitchUltra - P1499',
      description: 'SwitchUltra - P1499 Up to 220 Mbps',
      amount: 1499.0,
      discountId: 1,
    ),
  ];

  /// Bundled fallback router models matching the live Switch Fiber database
  static const List<RouterDto> fallbackRouters = [
    RouterDto(
      id: 3,
      name: 'Huawei',
      description: '5v5',
      brand: 'DUAL BAND ONU MODEM',
      model: '1',
    ),
    RouterDto(
      id: 5,
      name: 'UT-KING',
      description: 'UT-XP6486-S',
      brand: 'DUAL BAND ONU MODEM',
      model: '1',
    ),
    RouterDto(
      id: 6,
      name: 'ZTE',
      description: 'F670L',
      brand: 'DUAL BAND MODEM',
      model: '1',
    ),
    RouterDto(
      id: 4,
      name: 'ZTE',
      description: 'SF70L',
      brand: 'DUAL BAND ONU MODEM',
      model: '1',
    ),
    RouterDto(
      id: 1,
      name: 'ZTE',
      description: 'HG260',
      brand: 'DUAL BAND ONU MODEM',
      model: '1',
    ),
    RouterDto(
      id: 2,
      name: 'ZTE',
      description: 'HG260P',
      brand: 'DUAL BAND ONU MODEM',
      model: '1',
    ),
  ];

  /// Fetch all active broadband plans from local cached lookups first, then `/api/Plans` fallback.
  Future<List<PlanDto>> getPlans({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedPlans != null) {
      return _cachedPlans!;
    }
    if (!forceRefresh && _lookupsDao != null) {
      try {
        final local = await _lookupsDao!.getPlans();
        if (local.isNotEmpty) {
          _cachedPlans = local;
          return local;
        }
      } catch (_) {}
    }
    try {
      final response = await _api.get('/Plans');
      final data = response.data;
      if (data is List) {
        _cachedPlans = [
          for (final item in data)
            if (item is Map<String, dynamic>) PlanDto.fromJson(item),
        ];
        return _cachedPlans!;
      }
    } catch (_) {}
    if (_cachedPlans == null && _lookupsDao != null) {
      try {
        final local = await _lookupsDao!.getPlans();
        if (local.isNotEmpty) return _cachedPlans = local;
      } catch (_) {}
    }
    return _cachedPlans ?? fallbackPlans;
  }

  /// Find a plan name by plan id synchronously from cached or fallback plans.
  String? findPlanName(int? id) {
    if (id == null) return null;
    final list = _cachedPlans ?? fallbackPlans;
    for (final p in list) {
      if (p.id == id) return p.name;
    }
    return null;
  }

  /// Fetch approved ONT/router models from local cached lookups first, then `/api/Routers` fallback.
  Future<List<RouterDto>> getRouters({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedRouters != null) {
      return _cachedRouters!;
    }
    if (!forceRefresh && _lookupsDao != null) {
      try {
        final local = await _lookupsDao!.getRouters();
        if (local.isNotEmpty) {
          _cachedRouters = local;
          return local;
        }
      } catch (_) {}
    }
    try {
      final response = await _api.get('/Routers');
      final data = response.data;
      if (data is List) {
        _cachedRouters = [
          for (final item in data)
            if (item is Map<String, dynamic>) RouterDto.fromJson(item),
        ];
        return _cachedRouters!;
      }
    } catch (_) {}
    if (_cachedRouters == null && _lookupsDao != null) {
      try {
        final local = await _lookupsDao!.getRouters();
        if (local.isNotEmpty) return _cachedRouters = local;
      } catch (_) {}
    }
    return _cachedRouters ?? fallbackRouters;
  }

  // Gene - Oct 12, 2026: Added fallback LCPs and getLcps method for hierarchical LCP-first selection flow.
  static const List<LcpOptionDto> fallbackLcps = [
    LcpOptionDto(
        id: 1, name: 'LCP 01', description: 'Binangonan Central Cabinet'),
    LcpOptionDto(
        id: 2, name: 'LCP 02', description: 'Batingan Distribution Cabinet'),
    LcpOptionDto(id: 3, name: 'LCP 03', description: 'Bangad Optical Hub'),
    LcpOptionDto(id: 4, name: 'LCP 04', description: 'Libis Feeder Hub'),
  ];

  /// Fetch active LCP cabinets from local cached lookups first, then `/api/LCPs` fallback.
  Future<List<LcpOptionDto>> getLcps({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedLcps != null) {
      return _cachedLcps!;
    }
    if (!forceRefresh && _lookupsDao != null) {
      try {
        final local = await _lookupsDao!.getLcps();
        if (local.isNotEmpty) {
          _cachedLcps = local;
          return local;
        }
      } catch (_) {}
    }
    try {
      final response = await _api.get('/LCPs');
      final data = response.data;
      if (data is List) {
        _cachedLcps = [
          for (final item in data)
            if (item is Map<String, dynamic>) LcpOptionDto.fromJson(item),
        ];
        return _cachedLcps!;
      }
    } catch (_) {}
    if (_cachedLcps == null && _lookupsDao != null) {
      try {
        final local = await _lookupsDao!.getLcps();
        if (local.isNotEmpty) return _cachedLcps = local;
      } catch (_) {}
    }
    return _cachedLcps ?? fallbackLcps;
  }

  List<NapDto>? _cachedNaps;

/*
  static const List<NapDto> fallbackNaps = [
    NapDto(id: 2, name: 'NAP 001', description: 'NAP 001 Description'),
    NapDto(id: 3, name: 'NAP 002', description: 'NAP 002 Description'),
    NapDto(id: 4, name: 'NAP 003', description: 'NAP 003 Description'),
    NapDto(id: 5, name: 'NAP 004', description: 'NAP 004 Description'),
    NapDto(id: 6, name: 'NAP 005', description: 'NAP 005 Description'),
    NapDto(id: 7, name: 'NAP 006', description: 'NAP 006 Description'),
    NapDto(id: 8, name: 'NAP 007', description: 'NAP 007 Description'),
    NapDto(id: 9, name: 'NAP 008', description: 'NAP 008 Description'),
    NapDto(id: 1, name: 'NONE', description: 'NONE Description'),
    NapDto(id: 10, name: 'test nap 1', description: 'test nap 1 Description'),
  ];
*/
  // Gene - Oct 12, 2026: Expanded fallback NAPs to 16 distribution boxes per LCP cabinet matching live fiber layout.
  static const List<NapDto> fallbackNaps = [
    NapDto(id: 2, name: 'NAP 001', description: 'NAP 001 Description'),
    NapDto(id: 3, name: 'NAP 002', description: 'NAP 002 Description'),
    NapDto(id: 4, name: 'NAP 003', description: 'NAP 003 Description'),
    NapDto(id: 5, name: 'NAP 004', description: 'NAP 004 Description'),
    NapDto(id: 6, name: 'NAP 005', description: 'NAP 005 Description'),
    NapDto(id: 7, name: 'NAP 006', description: 'NAP 006 Description'),
    NapDto(id: 8, name: 'NAP 007', description: 'NAP 007 Description'),
    NapDto(id: 9, name: 'NAP 008', description: 'NAP 008 Description'),
    NapDto(id: 11, name: 'NAP 009', description: 'NAP 009 Description'),
    NapDto(id: 12, name: 'NAP 010', description: 'NAP 010 Description'),
    NapDto(id: 13, name: 'NAP 011', description: 'NAP 011 Description'),
    NapDto(id: 14, name: 'NAP 012', description: 'NAP 012 Description'),
    NapDto(id: 15, name: 'NAP 013', description: 'NAP 013 Description'),
    NapDto(id: 16, name: 'NAP 014', description: 'NAP 014 Description'),
    NapDto(id: 17, name: 'NAP 015', description: 'NAP 015 Description'),
    NapDto(id: 18, name: 'NAP 016', description: 'NAP 016 Description'),
    NapDto(id: 1, name: 'NONE', description: 'NONE Description'),
    NapDto(id: 10, name: 'test nap 1', description: 'test nap 1 Description'),
  ];

  /// Fetch active NAPs from local cached lookups first, then `/api/Naps` fallback.
  Future<List<NapDto>> getNaps({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedNaps != null) {
      return _cachedNaps!;
    }
    if (!forceRefresh && _lookupsDao != null) {
      try {
        final local = await _lookupsDao!.getNaps();
        if (local.isNotEmpty) {
          _cachedNaps = local;
          return local;
        }
      } catch (_) {}
    }
    try {
      final response = await _api.get('/Naps');
      final data = response.data;
      if (data is List) {
        _cachedNaps = [
          for (final item in data)
            if (item is Map<String, dynamic>) NapDto.fromJson(item),
        ];
        return _cachedNaps!;
      }
    } catch (_) {}
    if (_cachedNaps == null && _lookupsDao != null) {
      try {
        final local = await _lookupsDao!.getNaps();
        if (local.isNotEmpty) return _cachedNaps = local;
      } catch (_) {}
    }
    return _cachedNaps ?? fallbackNaps;
  }

  List<PortDto>? _cachedPorts;

  /// Bundled fallback Ports matching the live Switch Fiber database (PORT 001..PORT 016)
  static const List<PortDto> fallbackPorts = [
    PortDto(id: 1, name: 'PORT 001', description: 'PORT 001 Description'),
    PortDto(id: 2, name: 'PORT 002', description: 'PORT 002 Description'),
    PortDto(id: 3, name: 'PORT 003', description: 'PORT 003 Description'),
    PortDto(id: 4, name: 'PORT 004', description: 'PORT 004 Description'),
    PortDto(id: 5, name: 'PORT 005', description: 'PORT 005 Description'),
    PortDto(id: 6, name: 'PORT 006', description: 'PORT 006 Description'),
    PortDto(id: 7, name: 'PORT 007', description: 'PORT 007 Description'),
    PortDto(id: 8, name: 'PORT 008', description: 'PORT 008 Description'),
    PortDto(id: 9, name: 'PORT 009', description: 'PORT 009 Description'),
    PortDto(id: 10, name: 'PORT 010', description: 'PORT 010 Description'),
    PortDto(id: 11, name: 'PORT 011', description: 'PORT 011 Description'),
    PortDto(id: 12, name: 'PORT 012', description: 'PORT 012 Description'),
    PortDto(id: 13, name: 'PORT 013', description: 'PORT 013 Description'),
    PortDto(id: 14, name: 'PORT 014', description: 'PORT 014 Description'),
    PortDto(id: 15, name: 'PORT 015', description: 'PORT 015 Description'),
    PortDto(id: 16, name: 'PORT 016', description: 'PORT 016 Description'),
  ];

  /// Fetch active Ports from local cached lookups first, then `/api/Ports` fallback.
  Future<List<PortDto>> getPorts({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedPorts != null) {
      return _cachedPorts!;
    }
    if (!forceRefresh && _lookupsDao != null) {
      try {
        final local = await _lookupsDao!.getPorts();
        if (local.isNotEmpty) {
          _cachedPorts = local;
          return local;
        }
      } catch (_) {}
    }
    try {
      final response = await _api.get('/Ports');
      final data = response.data;
      if (data is List) {
        _cachedPorts = [
          for (final item in data)
            if (item is Map<String, dynamic>) PortDto.fromJson(item),
        ];
        return _cachedPorts!;
      }
    } catch (_) {}
    if (_cachedPorts == null && _lookupsDao != null) {
      try {
        final local = await _lookupsDao!.getPorts();
        if (local.isNotEmpty) return _cachedPorts = local;
      } catch (_) {}
    }
    return _cachedPorts ?? fallbackPorts;
  }

  List<String>? _cachedTechnicians;

  // Gene - Oct 13, 2026: Bundled fallback technicians matching Field Installation Team (FIT1) and active field personnel.
  static const List<String> fallbackTechnicians = [
    'Dave Dimacali',
    'Technician Trial Cruz',
    'Aldrin Ian Albao',
    'Melchor Ynopia',
    'Leonardo Bayos',
    'Jerry John Jao',
    'Liwanag II Capistrano',
    'Antonio Urata',
    'Elmer Tuyor',
    'Wilbert Calle',
    'Rolando Calle',
    'Bernard Aquino',
    'Peter Dominic Ojeda',
    'Reynaldo Boctoy Jr',
    'John Carlo Belarga',
    'Manuel Monteverde',
    'Wesley Aragones',
  ];

  // Gene - Oct 13, 2026: Fetch active technicians filtered by AccessLevel = Tech / Field Installation Team or accesslevel_id 8/9.
  Future<List<String>> getTechnicians({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedTechnicians != null) {
      return _cachedTechnicians!;
    }
    try {
      final matchingAccessIds = <int>{8, 9};
      try {
        final accessResponse = await _api.get('/AccessLevel');
        final accessData = accessResponse.data;
        if (accessData is List) {
          for (final item in accessData) {
            if (item is Map<String, dynamic>) {
              final id = item['id'] is int
                  ? item['id'] as int
                  : int.tryParse(item['id']?.toString() ?? '');
              final name = item['name']?.toString().toLowerCase() ?? '';
              if (id != null) {
                if (name.contains('field installation') ||
                    name.contains('tech') ||
                    id == 8 ||
                    id == 9) {
                  matchingAccessIds.add(id);
                }
              }
            }
          }
        }
      } catch (_) {}

      final response = await _api.get('/Users');
      final data = response.data;
      if (data is List) {
        final names = <String>{};
        for (final item in data) {
          if (item is Map<String, dynamic>) {
            final active = item['active'] == null ||
                item['active'] == true ||
                item['active'].toString() == 'true';
            if (!active) continue;

            final accessId = item['accesslevel_id'] is int
                ? item['accesslevel_id'] as int
                : int.tryParse(item['accesslevel_id']?.toString() ?? '') ??
                    (item['accessLevelId'] is int
                        ? item['accessLevelId'] as int
                        : int.tryParse(
                                item['accessLevelId']?.toString() ?? '') ??
                            0);

            final username = item['username']?.toString() ?? '';
            final fname = item['fname']?.toString() ??
                item['firstName']?.toString() ??
                '';
            final lname =
                item['lname']?.toString() ?? item['lastName']?.toString() ?? '';
            final fullName =
                '$fname $lname'.trim().replaceAll(RegExp(r'\s+'), ' ');

            final isTech = matchingAccessIds.contains(accessId) ||
                accessId == 8 ||
                accessId == 9 ||
                username.toLowerCase().contains('tech');

            if (isTech && fullName.isNotEmpty) {
              names.add(fullName);
            }
          }
        }
        if (names.isNotEmpty) {
          final combined = <String>{...names, ...fallbackTechnicians}.toList()
            ..sort();
          _cachedTechnicians = combined;
          return combined;
        }
      }
    } catch (_) {}
    return _cachedTechnicians ?? fallbackTechnicians;
  }

  // Gene - Oct 24, 2026: Cached inventory items and material names.
  List<InventoryItemDto>? _cachedInventoryItems;
  List<String>? _cachedMaterials;

  // Gene - Oct 24, 2026: Bundled fallback materials matching AppSheet / technician catalog.
  static const List<String> fallbackMaterials = [
    'APC-SC TO APC-SC (GREEN)',
    'APC-SC TO UPC-SC (GREEN TO BLUE)',
    'BROTHER CASSETTE TAPE',
    'BROTHER LABEL PRINTER',
    'Drop Cable (m)',
    'F-CLAMP',
    'FIBER OPTIC TROLLY',
    'FLAT CABLE CLIP',
    'HOUSE BRACKET',
    'IOO BOX',
    'MID SPAN',
    'OPTI-S',
    'OPTICAL POWER METER',
    'S-Clamp',
    'SC CONNECTOR',
    'SC/APC Fast Connector',
    'SCREW AND TOX',
    'SENKO SC CONNECTOR',
    'ZTE HG260',
  ];

  // Gene - Oct 24, 2026: Bundled fallback inventory items.
  static final List<InventoryItemDto> fallbackInventoryItems = [
    for (int i = 0; i < fallbackMaterials.length; i++)
      InventoryItemDto(
        id: i + 1,
        itemId: 'MAT-${(i + 1).toString().padLeft(3, '0')}',
        name: fallbackMaterials[i],
        description: fallbackMaterials[i],
        supplier: 'Switch Fiber',
        quantity: 100,
        category: 'Material',
      ),
  ];

  /// Fetch inventory items from local cached lookups first, then `/api/InventoryItem` fallback.
  Future<List<InventoryItemDto>> getInventoryItems(
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedInventoryItems != null) {
      return _cachedInventoryItems!;
    }
    if (!forceRefresh && _lookupsDao != null) {
      try {
        final local = await _lookupsDao!.getInventoryItems();
        if (local.isNotEmpty) {
          _cachedInventoryItems = local;
          return local;
        }
      } catch (_) {}
    }
    try {
      final response = await _api.get('/InventoryItem');
      final data = response.data;
      if (data is List) {
        final items = <InventoryItemDto>[];
        for (final item in data) {
          if (item is Map<String, dynamic>) {
            items.add(InventoryItemDto.fromJson(item));
          }
        }
        if (items.isNotEmpty) {
          _cachedInventoryItems = items;
          return items;
        }
      }
    } catch (_) {}
    if (_cachedInventoryItems == null && _lookupsDao != null) {
      try {
        final local = await _lookupsDao!.getInventoryItems();
        if (local.isNotEmpty) return _cachedInventoryItems = local;
      } catch (_) {}
    }
    return _cachedInventoryItems ?? fallbackInventoryItems;
  }

  Future<List<Map<String, Object?>>> getVlans() async =>
      _lookupsDao?.getVlans() ?? const [];

  Future<List<Map<String, Object?>>> getLcpNaps() async =>
      _lookupsDao?.getLcpNaps() ?? const [];

  Future<List<Map<String, Object?>>> getLcpNapPorts() async =>
      _lookupsDao?.getLcpNapPorts() ?? const [];

  Future<List<Map<String, Object?>>> getInventoryCategories() async =>
      _lookupsDao?.getInventoryCategories() ?? const [];

  Future<List<Map<String, Object?>>> getInventoryLogs() async =>
      _lookupsDao?.getInventoryLogs() ?? const [];

  /// Fetch distinct material names from the Inventory API.
  /// No types filter for now.
  Future<List<String>> getMaterials({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedMaterials != null) {
      return _cachedMaterials!;
    }
    try {
      final items = await getInventoryItems(forceRefresh: forceRefresh);
      final names = items
          .map((i) => i.name.trim())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList();
      if (names.isNotEmpty) {
        final combined = <String>{...names, ...fallbackMaterials}.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        _cachedMaterials = combined;
        return combined;
      }
    } catch (_) {}
    return _cachedMaterials ?? fallbackMaterials;
  }
}
