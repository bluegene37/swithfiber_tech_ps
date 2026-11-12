import 'dart:async';
import 'dart:typed_data';
import 'package:signals_flutter/signals_flutter.dart';
import '../../../core/widgets/loading_states.dart';
import '../models/lcp_nap_model.dart';
import '../repositories/lcp_nap_repository.dart';

/// Grouping presentation modes for large scale LCP NAP plant records.
enum LcpGroupMode {
  byLcp('By LCP Cabinet'),
  byCity('By City / Area'),
  flatList('Flat List');

  final String label;
  const LcpGroupMode(this.label);
}

/// Signals state management for LCP NAP Network Locations.
class LcpNapSignals {
  final LcpNapRepository repository;
  StreamSubscription<List<LcpNapDto>>? _driftSubscription;

  LcpNapSignals(this.repository) {
    _init();
  }

  // --- Core State Signals ---
  final Signal<List<LcpNapDto>> allLocations = signal<List<LcpNapDto>>([]);
  final Signal<String> selectedLcpFilter = signal<String>('All');
  final Signal<String> selectedCityFilter = signal<String>('All');
  final Signal<LcpGroupMode> groupMode =
      signal<LcpGroupMode>(LcpGroupMode.byLcp);
  final Signal<String> searchQuery = signal<String>('');
  final Signal<LcpNapDto?> selectedLocation = signal<LcpNapDto?>(null);
  final Signal<bool> isLoading = signal<bool>(false);
  final Signal<String?> errorMessage = signal<String?>(null);
  // First-load presentation: downloading -> skeleton -> ready. Stays ready for
  // pull-to-refresh and manual syncs so existing data is never hidden.
  final Signal<DataLoadPhase> loadPhase =
      signal<DataLoadPhase>(DataLoadPhase.ready);
  // Gene - Nov, 11, 2026: Monotonic revision counter incremented whenever remote/pending sync or photo mutations complete so mounted detail screens auto-refresh photos without app restart.
  final Signal<int> photoSyncRevision = signal<int>(0);

  // --- Computed Signals (Reactive Derived State) ---

  /// Locations filtered by search query, LCP cabinet, and city
  late final Computed<List<LcpNapDto>> filteredLocations = computed(() {
    final list = allLocations.value;
    final lcp = selectedLcpFilter.value;
    final city = selectedCityFilter.value;
    final query = searchQuery.value.trim().toLowerCase();

    return list.where((loc) {
      // LCP cabinet filter
      if (lcp != 'All' && loc.lcp != lcp) return false;

      // City / Area filter
      if (city != 'All' && loc.city != city) return false;

      // Search match
      if (query.isNotEmpty) {
        final matchesLcpNap = loc.lcpNap.toLowerCase().contains(query);
        final matchesLcp = loc.lcp.toLowerCase().contains(query);
        final matchesNap = loc.nap.toLowerCase().contains(query);
        final matchesBarangay =
            loc.barangay?.toLowerCase().contains(query) ?? false;
        final matchesCity = loc.city?.toLowerCase().contains(query) ?? false;
        final matchesDesc =
            (loc.street?.toLowerCase().contains(query) ?? false) ||
                (loc.region?.toLowerCase().contains(query) ?? false);

        return matchesLcpNap ||
            matchesLcp ||
            matchesNap ||
            matchesBarangay ||
            matchesCity ||
            matchesDesc;
      }

      return true;
    }).toList();
  });

  /// Locations grouped by LCP Cabinet for expandable accordion views
  late final Computed<Map<String, List<LcpNapDto>>> groupedByLcp = computed(() {
    final map = <String, List<LcpNapDto>>{};
    for (final loc in filteredLocations.value) {
      final key = loc.lcp.trim().isNotEmpty ? loc.lcp.trim() : 'Unassigned LCP';
      map.putIfAbsent(key, () => []).add(loc);
    }
    return map;
  });

  /// Locations grouped by City / Area
  late final Computed<Map<String, List<LcpNapDto>>> groupedByCity =
      computed(() {
    final map = <String, List<LcpNapDto>>{};
    for (final loc in filteredLocations.value) {
      final key = (loc.city != null && loc.city!.trim().isNotEmpty)
          ? loc.city!.trim()
          : (loc.barangay != null && loc.barangay!.trim().isNotEmpty
              ? loc.barangay!.trim()
              : 'Other Areas');
      map.putIfAbsent(key, () => []).add(loc);
    }
    return map;
  });

  /// Distinct list of LCP Cabinets with site counts
  late final Computed<List<String>> lcpCabinetList = computed(() {
    final list = allLocations.value;
    final cabinets = <String>{'All'};
    for (final loc in list) {
      if (loc.lcp.isNotEmpty) {
        cabinets.add(loc.lcp);
      }
    }
    final sorted = cabinets.toList()..sort();
    sorted.remove('All');
    return ['All', ...sorted];
  });

  /// Total count of mapped sites
  late final Computed<int> totalSitesCount =
      computed(() => allLocations.value.length);

  /// Total plant ports count
  late final Computed<int> totalPortsCount = computed(() {
    return allLocations.value.fold(0, (sum, loc) => sum + loc.portTotal);
  });

  /// Mappable GPS sites
  late final Computed<List<LcpNapDto>> mappableLocations = computed(
    () => filteredLocations.value.where((l) => l.isMappable).toList(),
  );

  /// Sites without GPS fix
  late final Computed<List<LcpNapDto>> unmappedLocations = computed(
    () => filteredLocations.value.where((l) => !l.isMappable).toList(),
  );

  late final Computed<int> unmappedCount =
      computed(() => unmappedLocations.value.length);

  // Gene - Nov, 11, 2026: Reactive count of LCP NAP sites with pending offline photo or GPS edits (`isSynced == false`).
  late final Computed<int> unsyncedCount = computed(
    () => allLocations.value.where((l) => !l.isSynced).length,
  );

  // --- Initialization & Methods ---

  void _init() {
    _driftSubscription = repository.watchLocations().listen((locations) {
      allLocations.value = locations;

      /*
      final currentSelected = selectedLocation.value;
      if (currentSelected != null) {
        final match =
            locations.where((l) => l.id == currentSelected.id).firstOrNull;
        if (match != null) {
          selectedLocation.value = match;
        }
      }
      */
      // Gene - Nov, 13, 2026: Clear selectedLocation if the previously selected LCP NAP site was deleted from live/local storage.
      final currentSelected = selectedLocation.value;
      if (currentSelected != null) {
        final match =
            locations.where((l) => l.id == currentSelected.id).firstOrNull;
        selectedLocation.value = match;
      }
    });
  }

  /// Trigger remote API synchronization.
  ///
  /// With [initial] set, and only when the local database holds nothing yet, the screen is
  /// walked through the download indicator and a brief skeleton pass before
  /// the hydrated local rows are revealed.
  /*
  Future<void> fetchRemote({bool initial = false}) async {
    final showPhases = initial && allLocations.value.isEmpty;
    if (showPhases) loadPhase.value = DataLoadPhase.downloading;
    try {
      isLoading.value = true;
      errorMessage.value = null;
      await repository.fetchRemoteLocations();
    } catch (e) {
      errorMessage.value = e.toString();
    } finally {
      isLoading.value = false;
      if (showPhases) {
        loadPhase.value = DataLoadPhase.skeleton;
        await Future<void>.delayed(const Duration(milliseconds: 900));
        loadPhase.value = DataLoadPhase.ready;
      }
    }
  }
  */
  // Gene - Nov, 11, 2026: Bump photoSyncRevision after remote sync and expose syncPending() so reconnect/background cycles flush queued NAP photo & GPS edits and notify open screens.
  Future<void> fetchRemote({bool initial = false}) async {
    final showPhases = initial && allLocations.value.isEmpty;
    if (showPhases) loadPhase.value = DataLoadPhase.downloading;
    try {
      isLoading.value = true;
      errorMessage.value = null;
      await repository.fetchRemoteLocations();
      photoSyncRevision.value++;
    } catch (e) {
      errorMessage.value = e.toString();
    } finally {
      isLoading.value = false;
      if (showPhases) {
        loadPhase.value = DataLoadPhase.skeleton;
        await Future<void>.delayed(const Duration(milliseconds: 900));
        loadPhase.value = DataLoadPhase.ready;
      }
    }
  }

  /// Flush any queued offline LCP NAP photo uploads, deletions, or GPS updates.
  Future<int> syncPending() async {
    final count = await repository.syncPendingLocations();
    if (count > 0) {
      photoSyncRevision.value++;
    }
    return count;
  }

  /// Update LCP Cabinet filter
  void setLcpFilter(String lcp) {
    selectedLcpFilter.value = lcp;
  }

  /// Update City / Area filter
  void setCityFilter(String city) {
    selectedCityFilter.value = city;
  }

  /// Update Grouping Mode
  void setGroupMode(LcpGroupMode mode) {
    groupMode.value = mode;
  }

  /// Update search text query
  void setSearch(String query) {
    searchQuery.value = query;
  }

  /// Select a site for detail inspection
  void selectLocation(LcpNapDto location) {
    selectedLocation.value = location;
  }

  // Gene - Oct 29, 2026: Coordinate photo upload for an LCP NAP location.
  // Gene - Oct 31, 2026: Added clear flags (clearImage, clearImage2, clearReadingImage) to support photo deletion.
  Future<bool> uploadLocationPhotos({
    required int locationId,
    required LcpNapDto location,
    Uint8List? imageBytes,
    Uint8List? image2Bytes,
    Uint8List? readingImageBytes,
    bool clearImage = false,
    bool clearImage2 = false,
    bool clearReadingImage = false,
  }) async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final success = await repository.uploadLcpNapPhotos(
        locationId: locationId,
        location: location,
        imageBytes: imageBytes,
        image2Bytes: image2Bytes,
        readingImageBytes: readingImageBytes,
        clearImage: clearImage,
        clearImage2: clearImage2,
        clearReadingImage: clearReadingImage,
      );
      // Gene - Nov, 11, 2026: Notify active photo observers immediately on upload/delete completion.
      if (success) {
        photoSyncRevision.value++;
      }
      return success;
    } catch (e) {
      errorMessage.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /*
  // Gene - Oct 31, 2026: Coordinate LCP NAP location coordinates and address update.
  Future<bool> updateLocationCoordinates({
    required int locationId,
    required LcpNapDto location,
    required String coordinates,
    String? street,
    String? barangay,
    String? city,
    String? region,
  }) async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final success = await repository.updateLocationCoordinates(
        locationId: locationId,
        location: location,
        coordinates: coordinates,
        street: street,
        barangay: barangay,
        city: city,
        region: region,
      );
      // Gene - Nov, 11, 2026: Notify active observers after GPS coordinate sync.
      if (success) {
        photoSyncRevision.value++;
      }
      return success;
    } catch (e) {
      errorMessage.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }
  */
  // Gene - Nov, 11, 2026: Support editing LCP, NAP, LCPNAP, PortTotal, address, and GPS coordinates, plus creating new LCP NAP locations.
  Future<bool> updateLocationCoordinates({
    required int locationId,
    required LcpNapDto location,
    required String coordinates,
    String? lcp,
    String? nap,
    String? lcpNap,
    int? portTotal,
    String? street,
    String? barangay,
    String? city,
    String? region,
    String? modifiedBy,
    String? userEmail,
  }) async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final success = await repository.updateLocationCoordinates(
        locationId: locationId,
        location: location,
        coordinates: coordinates,
        lcp: lcp,
        nap: nap,
        lcpNap: lcpNap,
        portTotal: portTotal,
        street: street,
        barangay: barangay,
        city: city,
        region: region,
        modifiedBy: modifiedBy,
        userEmail: userEmail,
      );
      if (success) {
        photoSyncRevision.value++;
      }
      return success;
    } catch (e) {
      errorMessage.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  /// Create a new LCP NAP location record in the plant database and API.
  Future<LcpNapDto?> createLocation({
    required String lcp,
    required String nap,
    String? lcpNap,
    int portTotal = 16,
    String? coordinates,
    String? street,
    String? barangay,
    String? city,
    String? region,
    String? modifiedBy,
    String? userEmail,
    Uint8List? imageBytes,
    Uint8List? image2Bytes,
    Uint8List? readingImageBytes,
  }) async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final created = await repository.createLocation(
        lcp: lcp,
        nap: nap,
        lcpNap: lcpNap,
        portTotal: portTotal,
        coordinates: coordinates,
        street: street,
        barangay: barangay,
        city: city,
        region: region,
        modifiedBy: modifiedBy,
        userEmail: userEmail,
        imageBytes: imageBytes,
        image2Bytes: image2Bytes,
        readingImageBytes: readingImageBytes,
      );
      if (created != null) {
        selectedLocation.value = created;
        photoSyncRevision.value++;
      }
      return created;
    } catch (e) {
      errorMessage.value = e.toString();
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> dispose() async {
    await _driftSubscription?.cancel();
    _driftSubscription = null;
  }
}
