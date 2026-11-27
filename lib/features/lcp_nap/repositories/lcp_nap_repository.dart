import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/database/daos/lcp_nap_dao.dart';
import '../../../core/network/api_client.dart';
// Gene - Nov, 11, 2026: Imported ApiException to distinguish offline/transient network failures (queued for auto-sync) from hard 4xx validation errors.
import '../../../core/network/network_exceptions.dart';
// Gene - Nov, 8, 2026: Imported PhotoStorageService and DataUrl to sync uploaded/deleted LCP NAP photos with local SQLite rows.
import '../../../core/services/photo_storage_service.dart';
// Gene - Nov, 27, 2026: Added PowerSyncService import to route plant mutations via PowerSync ps_crud when replicated mode is active.
import '../../../core/sync/powersync_service.dart';
import '../../../core/utils/data_url.dart';
import '../models/lcp_nap_images_model.dart';
import '../models/lcp_nap_model.dart';

/// Repository coordinating LCP NAP locations between the API and the local database.
class LcpNapRepository {
  final LcpNapLocationsDao _dao;
  /*
  final ApiClient _api = ApiClient.instance;

  LcpNapRepository(this._dao);
  */
  // Gene - Oct 29, 2026: Allow optional ApiClient injection for unit testing upload and image endpoints.
  final ApiClient _api;
  final bool Function() _isReplicatedMode;

  LcpNapRepository(
    this._dao, [
    ApiClient? api,
    bool Function()? isReplicatedMode,
  ])  : _api = api ?? ApiClient.instance,
        _isReplicatedMode = isReplicatedMode ??
            (() => PowerSyncService.instance.isReplicatedMode);

  /// Watch reactive stream of all locations from the local database
  Stream<List<LcpNapDto>> watchLocations() => _dao.watchAllLocations();

  /// Watch a specific location by ID
  Stream<LcpNapDto?> watchLocationById(int id) => _dao.watchLocationById(id);

  /*
  /// Fetch remote records from API and cache them locally
  Future<void> fetchRemoteLocations() async {
    // Purge test/sample demo locations permanently
    await _dao.deleteSampleLocations();

    try {
      final response = await _api.get('/LCPNapLocations');
      final data = response.data;

      if (data is List) {
        final sites = <LcpNapDto>[
          for (final item in data)
            if (item is Map<String, dynamic>) LcpNapDto.fromJson(item),
        ];
        if (sites.isNotEmpty) {
          await _dao.insertAllLocations(sites, synced: true);
        }
      }
    } catch (_) {
      // Offline fallback: do not re-seed test data
    }
  }
  */
  /*
  // Gene - Nov, 11, 2026: Flush queued offline photo/GPS edits before pulling, protect still-unsynced local rows from overwrite, and invalidate stale _imagesCache entries so remote uploads sync without restarting the app.
  Future<void> fetchRemoteLocations() async {
    // Purge test/sample demo locations permanently
    await _dao.deleteSampleLocations();

    // Push any pending offline photo uploads, deletions, or GPS updates first
    await syncPendingLocations();

    try {
      final response = await _api.get('/LCPNapLocations');
      final data = response.data;

      if (data is List) {
        final sites = <LcpNapDto>[
          for (final item in data)
            if (item is Map<String, dynamic>) LcpNapDto.fromJson(item),
        ];
        if (sites.isNotEmpty) {
          final existingRows = await _dao.getAllLocations();
          final existingById = <int, LcpNapDto>{
            for (final row in existingRows) row.id: row,
          };

          final mergedSites = <LcpNapDto>[];
          for (final remote in sites) {
            final existing = existingById[remote.id];

            // Never clobber local unsynced GPS or photo edits that have not pushed yet
            if (existing != null && !existing.isSynced) {
              continue;
            }

            // Evict in-memory photo cache on remote refresh so images uploaded or deleted
            // on another device sync immediately without closing & reopening the app.
            _imagesCache.remove(remote.id);

            final unchangedTimestamp = existing != null &&
                existing.modifiedDate != null &&
                existing.modifiedDate == remote.modifiedDate;

            mergedSites.add(
              unchangedTimestamp
                  ? remote.copyWith(
                      image: remote.image ?? existing.image,
                      image2: remote.image2 ?? existing.image2,
                      readingImage:
                          remote.readingImage ?? existing.readingImage,
                      isSynced: true,
                    )
                  : remote.copyWith(isSynced: true),
            );
          }

          if (mergedSites.isNotEmpty) {
            await _dao.insertAllLocations(mergedSites, synced: true);
          }
        }
      }
    } catch (_) {
      // Offline fallback: retain cached & pending local SQLite rows
    }
  }
  */
  // Gene - Nov, 13, 2026: Reconcile deleted live LCP NAP records via deleteSyncedLocationsNotIn and evict stale _imagesCache entries even when the server returns an empty list.
  Future<void> fetchRemoteLocations() async {
    // Gene - Nov, 27, 2026: Downstream plant rows arrive via PowerSync streaming when replicated mode is active.
    if (_isReplicatedMode()) {
      _imagesCache.clear();
      return;
    }

    // Purge test/sample demo locations permanently
    await _dao.deleteSampleLocations();

    // Push any pending offline photo uploads, deletions, or GPS updates first
    await syncPendingLocations();

    try {
      final response = await _api.get('/LCPNapLocations');
      final data = response.data;

      if (data is List) {
        final sites = <LcpNapDto>[
          for (final item in data)
            if (item is Map<String, dynamic>) LcpNapDto.fromJson(item),
        ];
        final existingRows = await _dao.getAllLocations();
        final existingById = <int, LcpNapDto>{
          for (final row in existingRows) row.id: row,
        };
        final keepIds = <int>{};
        final mergedSites = <LcpNapDto>[];

        for (final remote in sites) {
          keepIds.add(remote.id);
          final existing = existingById[remote.id];

          // Never clobber local unsynced GPS or photo edits that have not pushed yet
          if (existing != null && !existing.isSynced) {
            continue;
          }

          // Evict in-memory photo cache on remote refresh so images uploaded or deleted
          // on another device sync immediately without closing & reopening the app.
          _imagesCache.remove(remote.id);

          final unchangedTimestamp = existing != null &&
              existing.modifiedDate != null &&
              existing.modifiedDate == remote.modifiedDate;

          mergedSites.add(
            unchangedTimestamp
                ? remote.copyWith(
                    image: remote.image ?? existing.image,
                    image2: remote.image2 ?? existing.image2,
                    readingImage: remote.readingImage ?? existing.readingImage,
                    isSynced: true,
                  )
                : remote.copyWith(isSynced: true),
          );
        }

        if (mergedSites.isNotEmpty) {
          await _dao.insertAllLocations(mergedSites, synced: true);
        }

        // Drop synced locations that were deleted on the live server
        await _dao.deleteSyncedLocationsNotIn(keepIds);
        _imagesCache.removeWhere(
          (id, _) =>
              !keepIds.contains(id) && (existingById[id]?.isSynced ?? true),
        );
      }
    } catch (_) {
      // Offline fallback: retain cached & pending local SQLite rows
    }
  }

  /// Seed realistic fiber plant infrastructure data
  Future<void> seedSampleLocations() async {
    final now = DateTime.now();
    final sampleSites = [
      LcpNapDto(
        id: 1,
        lcp: 'LCP 01',
        nap: 'NAP 01',
        lcpNap: 'LCP 01 - NAP 01',
        portTotal: 8,
        coordinates: '14.5862, 121.0618',
        street: 'Sample Street',
        region: 'Rizal',
        barangay: 'San Antonio',
        city: 'Pasig',
        isSynced: true,
        updatedAt: now,
      ),
      LcpNapDto(
        id: 2,
        lcp: 'LCP 01',
        nap: 'NAP 02',
        lcpNap: 'LCP 01 - NAP 02',
        portTotal: 8,
        coordinates: '14.5875, 121.0632',
        street: 'Sample Street',
        region: 'Rizal',
        barangay: 'San Antonio',
        city: 'Pasig',
        isSynced: true,
        updatedAt: now,
      ),
      LcpNapDto(
        id: 3,
        lcp: 'LCP 02',
        nap: 'NAP 01',
        lcpNap: 'LCP 02 - NAP 01',
        portTotal: 16,
        coordinates: '14.6288, 121.1274',
        street: 'Sample Street',
        region: 'Rizal',
        barangay: 'San Roque',
        city: 'Antipolo',
        isSynced: true,
        updatedAt: now,
      ),
      LcpNapDto(
        id: 4,
        lcp: 'LCP 02',
        nap: 'NAP 02',
        lcpNap: 'LCP 02 - NAP 02',
        portTotal: 8,
        coordinates: '14.6295, 121.1290',
        street: 'Sample Street',
        region: 'Rizal',
        barangay: 'San Roque',
        city: 'Antipolo',
        isSynced: true,
        updatedAt: now,
      ),
      LcpNapDto(
        id: 5,
        lcp: 'LCP 03',
        nap: 'NAP 01',
        lcpNap: 'LCP 03 - NAP 01',
        portTotal: 8,
        coordinates: '14.6433, 121.0712',
        street: 'Sample Street',
        region: 'Rizal',
        barangay: 'Loyola Heights',
        city: 'Quezon City',
        isSynced: true,
        updatedAt: now,
      ),
    ];

    await _dao.insertAllLocations(sampleSites, synced: true);
  }

  // Gene - Oct 24, 2026: Cached LCP NAP location photos by site ID.
  final Map<int, LcpNapImagesDto> _imagesCache = {};

  /// Clear in-memory photos cache (useful for tests or refresh).
  void clearImagesCache() {
    _imagesCache.clear();
  }

  // Gene - Nov, 8, 2026: Allow seeding in-memory photos cache so single-slot deletions preserve sibling photos.
  void seedImagesCache(int locationId, LcpNapImagesDto images) {
    _imagesCache[locationId] = images;
  }

  // Gene - Nov, 11, 2026: Expose non-destructive cache peek and single-flight pending sync state for auto-sync coordination.
  LcpNapImagesDto? peekCachedImages(int locationId) => _imagesCache[locationId];

  void invalidateImagesCache([int? locationId]) {
    if (locationId != null) {
      _imagesCache.remove(locationId);
    } else {
      _imagesCache.clear();
    }
  }

  Future<int>? _activeSyncPendingFuture;

  Uint8List? _resolvePhotoBytes(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final clean = raw.trim();
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return null;
    }
    return PhotoStorageService.instance.resolveBytes(clean) ??
        DataUrl.decode(clean);
  }

  // Gene - Nov, 11, 2026: Persist photo bytes as compact local file path (via PhotoStorageService) to avoid 2MB Android SQLite CursorWindow limits, falling back to DataUrl only if file storage is unavailable.
  Future<String> _persistPhotoSlotLocally(
    int locationId,
    String slotName,
    Uint8List bytes,
  ) async {
    final encoded = DataUrl.encode(bytes, mimeType: 'image/jpeg');
    try {
      return await PhotoStorageService.instance.savePhotoLocally(
            encoded,
            tag: 'lcp_nap_$slotName',
            entityId: locationId,
          ) ??
          encoded;
    } catch (_) {
      return encoded;
    }
  }

  LcpNapImagesDto _buildImagesDtoFromBytes({
    Uint8List? enc1Bytes,
    Uint8List? enc2Bytes,
    Uint8List? readingBytes,
  }) {
    return LcpNapImagesDto(
      image: (enc1Bytes != null && enc1Bytes.isNotEmpty)
          ? LcpNapImageFileDto(
              fileContents: base64Encode(enc1Bytes),
              contentType: 'image/jpeg',
              fileDownloadName: 'image.jpg',
            )
          : null,
      image2: (enc2Bytes != null && enc2Bytes.isNotEmpty)
          ? LcpNapImageFileDto(
              fileContents: base64Encode(enc2Bytes),
              contentType: 'image/jpeg',
              fileDownloadName: 'image2.jpg',
            )
          : null,
      readingImage: (readingBytes != null && readingBytes.isNotEmpty)
          ? LcpNapImageFileDto(
              fileContents: base64Encode(readingBytes),
              contentType: 'image/jpeg',
              fileDownloadName: 'readingImage.jpg',
            )
          : null,
    );
  }

  bool _isHardClientError(Object error) {
    if (error is ApiException) {
      final code = error.statusCode;
      if (code != null && code >= 400 && code < 500 && code != 408) {
        return true;
      }
    }
    return false;
  }

  /// Fetches site enclosure photos and optical power reading image for an LCP NAP location.
  /// Calls GET /api/LCPNapLocations/{id}/GetLCPNAPLocationImages
  /// and fallback GET /api/LCPNapLocations/{id}/GetReadingImage.
  Future<LcpNapImagesDto?> getLcpNapLocationImages(
    int locationId, {
    bool forceRefresh = false,
  }) async {
    /*
    if (!forceRefresh && _imagesCache.containsKey(locationId)) {
      return _imagesCache[locationId];
    }
    */
    /*
    // Gene - Nov, 8, 2026: Evict stale cached entry when forceRefresh is true so deleted photos never resurrect from cache.
    if (forceRefresh) {
      _imagesCache.remove(locationId);
    } else if (_imagesCache.containsKey(locationId)) {
      return _imagesCache[locationId];
    }
    */
    // Gene - Nov, 11, 2026: Bypass cache read on forceRefresh without pre-deleting _imagesCache[locationId] so offline background refreshes retain last-known photos; also guard local unsynced photo edits until pushed.
    final localRow = await _dao.getLocationById(locationId);
    if (localRow != null && !localRow.isSynced) {
      final hasPendingPhotoMutation = localRow.image != null ||
          localRow.image2 != null ||
          localRow.readingImage != null;
      if (hasPendingPhotoMutation) {
        final dto = _buildImagesDtoFromBytes(
          enc1Bytes: _resolvePhotoBytes(localRow.image) ??
              ((localRow.image == '')
                  ? null
                  : _imagesCache[locationId]?.image?.bytes),
          enc2Bytes: _resolvePhotoBytes(localRow.image2) ??
              ((localRow.image2 == '')
                  ? null
                  : _imagesCache[locationId]?.image2?.bytes),
          readingBytes: _resolvePhotoBytes(localRow.readingImage) ??
              ((localRow.readingImage == '')
                  ? null
                  : _imagesCache[locationId]?.readingImage?.bytes),
        );
        _imagesCache[locationId] = dto;
        return dto;
      }
    }

    if (!forceRefresh && _imagesCache.containsKey(locationId)) {
      return _imagesCache[locationId];
    }

    try {
      final response = await _api
          .get('/LCPNapLocations/$locationId/GetLCPNAPLocationImages');
      final data = response.data;
      if (data is Map<String, dynamic>) {
        var dto = LcpNapImagesDto.fromJson(data);

        // Fallback to GetReadingImage if readingImage was not included in JSON payload
        if (dto.readingImage == null) {
          try {
            final readingRes = await _api.get(
              '/LCPNapLocations/$locationId/GetReadingImage',
              options: Options(responseType: ResponseType.bytes),
            );
            if (readingRes.data is List<int> &&
                (readingRes.data as List<int>).isNotEmpty) {
              final b64 = base64Encode(readingRes.data as List<int>);
              final readingFile = LcpNapImageFileDto(
                fileContents: b64,
                contentType: 'image/jpeg',
                fileDownloadName: 'reading_$locationId.jpg',
              );
              dto = LcpNapImagesDto(
                image: dto.image,
                image2: dto.image2,
                readingImage: readingFile,
              );
            }
          } catch (_) {}
        }

        /*
        if (dto.hasAnyPhoto) {
          _imagesCache[locationId] = dto;
        }
        return dto;
        */
        // Gene - Oct 31, 2026: Cache photo result whenever a valid response is returned.
        _imagesCache[locationId] = dto;
        return dto;
      }
      // Gene - Nov, 13, 2026: Treat HTTP 204 or empty string response from GetLCPNAPLocationImages as an authoritative empty photo set so deleted server photos do not resurrect from cache.
      if (response.statusCode == 204 ||
          data == null ||
          (data is String && data.trim().isEmpty)) {
        const emptyDto = LcpNapImagesDto();
        _imagesCache[locationId] = emptyDto;
        return emptyDto;
      }
    } catch (_) {
      // Offline fallback or test mock
      // Gene - Oct 31, 2026: Fallback to single record endpoint GET /api/LCPNapLocations/{id} if GetLCPNAPLocationImages is unavailable.
      try {
        final singleRes = await _api.get('/LCPNapLocations/$locationId');
        final singleData = singleRes.data;
        if (singleData is Map<String, dynamic>) {
          final dto = LcpNapImagesDto.fromJson(singleData);
          /*
          if (dto.hasAnyPhoto) {
            _imagesCache[locationId] = dto;
            return dto;
          }
          */
          // Gene - Nov, 8, 2026: Always cache and return the parsed DTO from single record endpoint even when all photos have been deleted (hasAnyPhoto == false).
          _imagesCache[locationId] = dto;
          return dto;
        }
      } catch (_) {}
    }

    if (_imagesCache.containsKey(locationId)) {
      return _imagesCache[locationId];
    }

    // Reconstruct from local SQLite photo paths if completely offline with cold RAM cache
    if (localRow != null) {
      final enc1 = _resolvePhotoBytes(localRow.image);
      final enc2 = _resolvePhotoBytes(localRow.image2);
      final reading = _resolvePhotoBytes(localRow.readingImage);
      if (enc1 != null || enc2 != null || reading != null) {
        final fallbackDto = _buildImagesDtoFromBytes(
          enc1Bytes: enc1,
          enc2Bytes: enc2,
          readingBytes: reading,
        );
        _imagesCache[locationId] = fallbackDto;
        return fallbackDto;
      }
    }

    return _imagesCache[locationId];
  }

  /*
  // Gene - Oct 29, 2026: Uploads LCP NAP site enclosure and optical power reading photos via multipart/form-data PUT /api/LCPNapLocations/{id}.
  // Gene - Oct 31, 2026: Added clear flags (clearImage, clearImage2, clearReadingImage) to support deleting/clearing photos by sending empty image file/omission per backend API contract.
  Future<bool> uploadLcpNapPhotos({
    required int locationId,
    required LcpNapDto location,
    Uint8List? imageBytes,
    Uint8List? image2Bytes,
    Uint8List? readingImageBytes,
    bool clearImage = false,
    bool clearImage2 = false,
    bool clearReadingImage = false,
  }) async {
    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final map = <String, dynamic>{
        'LCP': location.lcp,
        'NAP': location.nap,
        'LCPNAP': location.lcpNap,
        'PortTotal': location.portTotal.toString(),
        if (location.coordinates != null) 'Coordinates': location.coordinates,
        if (location.street != null) 'Street': location.street,
        if (location.barangay != null) 'Barangay': location.barangay,
        if (location.city != null) 'City': location.city,
        if (location.region != null) 'Region': location.region,
        // Gene - Nov, 8, 2026: Include audit metadata fields expected by PUT /api/LCPNapLocations/{id}.
        'ModifiedBy': location.modifiedBy ?? '1',
        'ModifiedDate': nowIso,
        if (location.userEmail != null && location.userEmail!.trim().isNotEmpty)
          'UserEmail': location.userEmail!.trim(),
      };

      // 1. Enclosure Exterior (image)
      if (clearImage) {
        // Gene - Oct 31, 2026: Send empty 0-byte file when explicitly clearing/deleting photo per backend team instructions
        map['Image'] = MultipartFile.fromBytes(<int>[], filename: '');
      } else if (imageBytes != null && imageBytes.isNotEmpty) {
        map['Image'] =
            MultipartFile.fromBytes(imageBytes, filename: 'image.jpg');
      } else {
        final existingBytes = _imagesCache[locationId]?.image?.bytes ??
            _resolvePhotoBytes(location.image);
        if (existingBytes != null && existingBytes.isNotEmpty) {
          map['Image'] =
              MultipartFile.fromBytes(existingBytes, filename: 'image.jpg');
        }
      }

      // 2. Enclosure Interior (image2)
      if (clearImage2) {
        map['Image2'] = MultipartFile.fromBytes(<int>[], filename: '');
      } else if (image2Bytes != null && image2Bytes.isNotEmpty) {
        map['Image2'] =
            MultipartFile.fromBytes(image2Bytes, filename: 'image2.jpg');
      } else {
        final existingBytes = _imagesCache[locationId]?.image2?.bytes ??
            _resolvePhotoBytes(location.image2);
        if (existingBytes != null && existingBytes.isNotEmpty) {
          map['Image2'] =
              MultipartFile.fromBytes(existingBytes, filename: 'image2.jpg');
        }
      }

      // 3. Optical Power Reading (readingImage)
      if (clearReadingImage) {
        map['ReadingImage'] = MultipartFile.fromBytes(<int>[], filename: '');
      } else if (readingImageBytes != null && readingImageBytes.isNotEmpty) {
        map['ReadingImage'] = MultipartFile.fromBytes(readingImageBytes,
            filename: 'readingImage.jpg');
      } else {
        final existingBytes = _imagesCache[locationId]?.readingImage?.bytes ??
            _resolvePhotoBytes(location.readingImage);
        if (existingBytes != null && existingBytes.isNotEmpty) {
          map['ReadingImage'] = MultipartFile.fromBytes(existingBytes,
              filename: 'readingImage.jpg');
        }
      }

      final formData = FormData.fromMap(map);
      final response = await _api.put(
        '/LCPNapLocations/$locationId',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      final isSuccess =
          response.statusCode == 200 || response.statusCode == 204;
      if (isSuccess) {
        _imagesCache.remove(locationId);
        final updatedDto = location.copyWith(
          image: (imageBytes != null && imageBytes.isNotEmpty)
              ? DataUrl.encode(imageBytes, mimeType: 'image/jpeg')
              : null,
          image2: (image2Bytes != null && image2Bytes.isNotEmpty)
              ? DataUrl.encode(image2Bytes, mimeType: 'image/jpeg')
              : null,
          readingImage:
              (readingImageBytes != null && readingImageBytes.isNotEmpty)
                  ? DataUrl.encode(readingImageBytes, mimeType: 'image/jpeg')
                  : null,
          clearImage: clearImage,
          clearImage2: clearImage2,
          clearReadingImage: clearReadingImage,
          isSynced: true,
          updatedAt: DateTime.now(),
        );
        await _dao.insertOrUpdateLocation(updatedDto, synced: true);
      }
      return isSuccess;
    } catch (_) {
      return false;
    }
  }
  */
  // Gene - Nov, 11, 2026: Store photos via PhotoStorageService, warm _imagesCache immediately, preserve cold-cache sibling photos, and queue offline photo uploads/deletions in SQLite (isSynced=false) for automatic sync on reconnect.
  Future<bool> uploadLcpNapPhotos({
    required int locationId,
    required LcpNapDto location,
    Uint8List? imageBytes,
    Uint8List? image2Bytes,
    Uint8List? readingImageBytes,
    bool clearImage = false,
    bool clearImage2 = false,
    bool clearReadingImage = false,
  }) async {
    final baseLoc = (await _dao.getLocationById(locationId)) ?? location;
    final mergedBase = baseLoc.copyWith(
      lcp: location.lcp,
      nap: location.nap,
      lcpNap: location.lcpNap,
      portTotal: location.portTotal,
      coordinates: location.coordinates ?? baseLoc.coordinates,
      street: location.street ?? baseLoc.street,
      barangay: location.barangay ?? baseLoc.barangay,
      city: location.city ?? baseLoc.city,
      region: location.region ?? baseLoc.region,
      modifiedBy: location.modifiedBy ?? baseLoc.modifiedBy,
      userEmail: location.userEmail ?? baseLoc.userEmail,
    );

    final nowUtc = DateTime.now().toUtc();
    final nowIso = nowUtc.toIso8601String();

    // Gene - Nov, 27, 2026: In replicated PowerSync mode, write only changed/cleared photo slots locally so PowerSync Gateway handles multipart upload & preserves sibling photos on disk.
    if (_isReplicatedMode()) {
      final String? nextImg1 = clearImage
          ? ''
          : (imageBytes != null && imageBytes.isNotEmpty
              ? await _persistPhotoSlotLocally(locationId, 'enc1', imageBytes)
              : mergedBase.image);
      final String? nextImg2 = clearImage2
          ? ''
          : (image2Bytes != null && image2Bytes.isNotEmpty
              ? await _persistPhotoSlotLocally(locationId, 'enc2', image2Bytes)
              : mergedBase.image2);
      final String? nextReading = clearReadingImage
          ? ''
          : (readingImageBytes != null && readingImageBytes.isNotEmpty
              ? await _persistPhotoSlotLocally(
                  locationId, 'reading', readingImageBytes)
              : mergedBase.readingImage);

      final existingCache = _imagesCache[locationId];
      _imagesCache[locationId] = LcpNapImagesDto(
        image: clearImage
            ? null
            : ((imageBytes != null && imageBytes.isNotEmpty)
                ? _buildImagesDtoFromBytes(enc1Bytes: imageBytes).image
                : (existingCache?.image ??
                    _buildImagesDtoFromBytes(
                      enc1Bytes: _resolvePhotoBytes(mergedBase.image),
                    ).image)),
        image2: clearImage2
            ? null
            : ((image2Bytes != null && image2Bytes.isNotEmpty)
                ? _buildImagesDtoFromBytes(enc2Bytes: image2Bytes).image2
                : (existingCache?.image2 ??
                    _buildImagesDtoFromBytes(
                      enc2Bytes: _resolvePhotoBytes(mergedBase.image2),
                    ).image2)),
        readingImage: clearReadingImage
            ? null
            : ((readingImageBytes != null && readingImageBytes.isNotEmpty)
                ? _buildImagesDtoFromBytes(readingBytes: readingImageBytes)
                    .readingImage
                : (existingCache?.readingImage ??
                    _buildImagesDtoFromBytes(
                      readingBytes: _resolvePhotoBytes(mergedBase.readingImage),
                    ).readingImage)),
      );

      final queuedDto = mergedBase.copyWith(
        image: nextImg1,
        image2: nextImg2,
        readingImage: nextReading,
        modifiedDate: nowUtc,
        isSynced: false,
        updatedAt: DateTime.now(),
      );
      await _dao.insertOrUpdateLocation(queuedDto, synced: false);
      return true;
    }

    final needsServerSiblingCheck = !_imagesCache.containsKey(locationId) &&
        mergedBase.modifiedDate != null &&
        !ApiClient.isNetworkBlocked &&
        ((!clearImage &&
                (imageBytes == null || imageBytes.isEmpty) &&
                _resolvePhotoBytes(mergedBase.image) == null) ||
            (!clearImage2 &&
                (image2Bytes == null || image2Bytes.isEmpty) &&
                _resolvePhotoBytes(mergedBase.image2) == null) ||
            (!clearReadingImage &&
                (readingImageBytes == null || readingImageBytes.isEmpty) &&
                _resolvePhotoBytes(mergedBase.readingImage) == null));

    if (needsServerSiblingCheck) {
      try {
        await getLcpNapLocationImages(locationId);
      } catch (_) {}
    }

    final finalEnc1Bytes = clearImage
        ? null
        : ((imageBytes != null && imageBytes.isNotEmpty)
            ? imageBytes
            : (_imagesCache[locationId]?.image?.bytes ??
                _resolvePhotoBytes(mergedBase.image)));

    final finalEnc2Bytes = clearImage2
        ? null
        : ((image2Bytes != null && image2Bytes.isNotEmpty)
            ? image2Bytes
            : (_imagesCache[locationId]?.image2?.bytes ??
                _resolvePhotoBytes(mergedBase.image2)));

    final finalReadingBytes = clearReadingImage
        ? null
        : ((readingImageBytes != null && readingImageBytes.isNotEmpty)
            ? readingImageBytes
            : (_imagesCache[locationId]?.readingImage?.bytes ??
                _resolvePhotoBytes(mergedBase.readingImage)));

    final savedImg1 = (finalEnc1Bytes != null && finalEnc1Bytes.isNotEmpty)
        ? await _persistPhotoSlotLocally(locationId, 'enc1', finalEnc1Bytes)
        : null;
    final savedImg2 = (finalEnc2Bytes != null && finalEnc2Bytes.isNotEmpty)
        ? await _persistPhotoSlotLocally(locationId, 'enc2', finalEnc2Bytes)
        : null;
    final savedReading =
        (finalReadingBytes != null && finalReadingBytes.isNotEmpty)
            ? await _persistPhotoSlotLocally(
                locationId, 'reading', finalReadingBytes)
            : null;

    try {
      final map = <String, dynamic>{
        'LCP': mergedBase.lcp,
        'NAP': mergedBase.nap,
        'LCPNAP': mergedBase.lcpNap,
        'PortTotal': mergedBase.portTotal.toString(),
        if (mergedBase.coordinates != null)
          'Coordinates': mergedBase.coordinates,
        if (mergedBase.street != null) 'Street': mergedBase.street,
        if (mergedBase.barangay != null) 'Barangay': mergedBase.barangay,
        if (mergedBase.city != null) 'City': mergedBase.city,
        if (mergedBase.region != null) 'Region': mergedBase.region,
        'ModifiedBy': mergedBase.modifiedBy ?? '1',
        'ModifiedDate': nowIso,
        if (mergedBase.userEmail != null &&
            mergedBase.userEmail!.trim().isNotEmpty)
          'UserEmail': mergedBase.userEmail!.trim(),
      };

      final alsoClear1 =
          clearImage || (!mergedBase.isSynced && mergedBase.image == '');
      final alsoClear2 =
          clearImage2 || (!mergedBase.isSynced && mergedBase.image2 == '');
      final alsoClearReading = clearReadingImage ||
          (!mergedBase.isSynced && mergedBase.readingImage == '');

      if (alsoClear1 && finalEnc1Bytes == null) {
        map['Image'] = MultipartFile.fromBytes(<int>[], filename: '');
      } else if (finalEnc1Bytes != null && finalEnc1Bytes.isNotEmpty) {
        map['Image'] =
            MultipartFile.fromBytes(finalEnc1Bytes, filename: 'image.jpg');
      }

      if (alsoClear2 && finalEnc2Bytes == null) {
        map['Image2'] = MultipartFile.fromBytes(<int>[], filename: '');
      } else if (finalEnc2Bytes != null && finalEnc2Bytes.isNotEmpty) {
        map['Image2'] =
            MultipartFile.fromBytes(finalEnc2Bytes, filename: 'image2.jpg');
      }

      if (alsoClearReading && finalReadingBytes == null) {
        map['ReadingImage'] = MultipartFile.fromBytes(<int>[], filename: '');
      } else if (finalReadingBytes != null && finalReadingBytes.isNotEmpty) {
        map['ReadingImage'] = MultipartFile.fromBytes(finalReadingBytes,
            filename: 'readingImage.jpg');
      }

      final formData = FormData.fromMap(map);
      final response = await _api.put(
        '/LCPNapLocations/$locationId',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      final isSuccess =
          response.statusCode == 200 || response.statusCode == 204;
      if (isSuccess) {
        _imagesCache[locationId] = _buildImagesDtoFromBytes(
          enc1Bytes: finalEnc1Bytes,
          enc2Bytes: finalEnc2Bytes,
          readingBytes: finalReadingBytes,
        );
        final updatedDto = mergedBase.copyWith(
          image: savedImg1,
          image2: savedImg2,
          readingImage: savedReading,
          clearImage: alsoClear1 && savedImg1 == null,
          clearImage2: alsoClear2 && savedImg2 == null,
          clearReadingImage: alsoClearReading && savedReading == null,
          modifiedDate: nowUtc,
          isSynced: true,
          updatedAt: DateTime.now(),
        );
        await _dao.insertOrUpdateLocation(updatedDto, synced: true);
      }
      return isSuccess;
    } catch (e) {
      if (_isHardClientError(e)) {
        return false;
      }

      // Offline / transient network fallback: queue photo upload/delete locally for auto-sync!
      // Store '' sentinel when explicitly cleared offline so syncPendingLocations sends 0-byte delete file.
      final offlineImg1 =
          (clearImage || mergedBase.image == '') && savedImg1 == null
              ? ''
              : savedImg1;
      final offlineImg2 =
          (clearImage2 || mergedBase.image2 == '') && savedImg2 == null
              ? ''
              : savedImg2;
      final offlineReading =
          (clearReadingImage || mergedBase.readingImage == '') &&
                  savedReading == null
              ? ''
              : savedReading;

      _imagesCache[locationId] = _buildImagesDtoFromBytes(
        enc1Bytes: finalEnc1Bytes,
        enc2Bytes: finalEnc2Bytes,
        readingBytes: finalReadingBytes,
      );

      final queuedDto = mergedBase.copyWith(
        image: offlineImg1,
        image2: offlineImg2,
        readingImage: offlineReading,
        modifiedDate: nowUtc,
        isSynced: false,
        updatedAt: DateTime.now(),
      );
      await _dao.insertOrUpdateLocation(queuedDto, synced: false);
      return true;
    }
  }

  /*
  // Gene - Oct 31, 2026: Updates LCP NAP location coordinates and address fields via multipart/form-data PUT /api/LCPNapLocations/{id} and saves to local SQLite.
  Future<bool> updateLocationCoordinates({
    required int locationId,
    required LcpNapDto location,
    required String coordinates,
    String? street,
    String? barangay,
    String? city,
    String? region,
  }) async {
    try {
      final map = <String, dynamic>{
        'LCP': location.lcp,
        'NAP': location.nap,
        'LCPNAP': location.lcpNap,
        'PortTotal': location.portTotal.toString(),
        'Coordinates': coordinates,
        if (street != null || location.street != null)
          'Street': street ?? location.street,
        if (barangay != null || location.barangay != null)
          'Barangay': barangay ?? location.barangay,
        if (city != null || location.city != null)
          'City': city ?? location.city,
        if (region != null || location.region != null)
          'Region': region ?? location.region,
      };

      // Preserve existing cached photos if available
      final existingEnc1 = _imagesCache[locationId]?.image?.bytes;
      if (existingEnc1 != null && existingEnc1.isNotEmpty) {
        map['Image'] =
            MultipartFile.fromBytes(existingEnc1, filename: 'image.jpg');
      }
      final existingEnc2 = _imagesCache[locationId]?.image2?.bytes;
      if (existingEnc2 != null && existingEnc2.isNotEmpty) {
        map['Image2'] =
            MultipartFile.fromBytes(existingEnc2, filename: 'image2.jpg');
      }
      final existingReading = _imagesCache[locationId]?.readingImage?.bytes;
      if (existingReading != null && existingReading.isNotEmpty) {
        map['ReadingImage'] = MultipartFile.fromBytes(existingReading,
            filename: 'readingImage.jpg');
      }

      final formData = FormData.fromMap(map);
      final response = await _api.put(
        '/LCPNapLocations/$locationId',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      final isSuccess =
          response.statusCode == 200 || response.statusCode == 204;
      if (isSuccess) {
        final updatedDto = location.copyWith(
          coordinates: coordinates,
          street: street ?? location.street,
          barangay: barangay ?? location.barangay,
          city: city ?? location.city,
          region: region ?? location.region,
          isSynced: true,
          updatedAt: DateTime.now(),
        );
        await _dao.insertOrUpdateLocation(updatedDto, synced: true);
      }
      return isSuccess;
    } catch (_) {
      // Local optimistic fallback when offline
      final updatedDto = location.copyWith(
        coordinates: coordinates,
        street: street ?? location.street,
        barangay: barangay ?? location.barangay,
        city: city ?? location.city,
        region: region ?? location.region,
        isSynced: false,
        updatedAt: DateTime.now(),
      );
      await _dao.insertOrUpdateLocation(updatedDto, synced: false);
      return true;
    }
  }
  */
  /*
  // Gene - Nov, 11, 2026: Include audit metadata (ModifiedDate/ModifiedBy/UserEmail), preserve server & local sibling photos even when _imagesCache is cold, and protect pending offline photos on fallback.
  Future<bool> updateLocationCoordinates({
    required int locationId,
    required LcpNapDto location,
    required String coordinates,
    String? street,
    String? barangay,
    String? city,
    String? region,
  }) async {
  */
  // Gene - Nov, 11, 2026: Support editing LCP, NAP, LCPNAP site label, PortTotal capacity, address metadata, and GPS coordinates via PUT /LCPNapLocations/{id}, plus createLocation via POST /LCPNapLocations.
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
    final baseLoc = (await _dao.getLocationById(locationId)) ?? location;
    final nowUtc = DateTime.now().toUtc();
    final nowIso = nowUtc.toIso8601String();

    final resolvedLcp =
        (lcp != null && lcp.trim().isNotEmpty) ? lcp.trim() : location.lcp;
    final resolvedNap =
        (nap != null && nap.trim().isNotEmpty) ? nap.trim() : location.nap;
    final resolvedLcpNap = (lcpNap != null && lcpNap.trim().isNotEmpty)
        ? lcpNap.trim()
        : ((lcp != null || nap != null)
            ? '$resolvedLcp $resolvedNap'.trim()
            : location.lcpNap);
    final resolvedPortTotal = portTotal ?? location.portTotal;
    final resolvedCoordinates = coordinates.trim().isNotEmpty
        ? coordinates.trim()
        : (location.coordinates ?? baseLoc.coordinates ?? '');
    final resolvedModifiedBy =
        modifiedBy ?? location.modifiedBy ?? baseLoc.modifiedBy ?? '1';
    final resolvedUserEmail =
        userEmail ?? location.userEmail ?? baseLoc.userEmail;

    // If this row was created offline (negative temporary ID) or replicated PowerSync mode is active,
    // write locally so PowerSync ps_crud / syncPendingLocations handles the upload.
    if (locationId < 0 || _isReplicatedMode()) {
      final updatedOffline = baseLoc.copyWith(
        lcp: resolvedLcp,
        nap: resolvedNap,
        lcpNap: resolvedLcpNap,
        portTotal: resolvedPortTotal,
        coordinates:
            resolvedCoordinates.isNotEmpty ? resolvedCoordinates : null,
        street: street ?? location.street ?? baseLoc.street,
        barangay: barangay ?? location.barangay ?? baseLoc.barangay,
        city: city ?? location.city ?? baseLoc.city,
        region: region ?? location.region ?? baseLoc.region,
        modifiedBy: resolvedModifiedBy,
        userEmail: resolvedUserEmail,
        modifiedDate: nowUtc,
        isSynced: false,
        updatedAt: DateTime.now(),
      );
      await _dao.insertOrUpdateLocation(updatedOffline, synced: false);
      if (!_isReplicatedMode()) {
        unawaited(syncPendingLocations());
      }
      return true;
    }

    final hasLocalAny = _resolvePhotoBytes(baseLoc.image) != null ||
        _resolvePhotoBytes(baseLoc.image2) != null ||
        _resolvePhotoBytes(baseLoc.readingImage) != null ||
        baseLoc.image == '' ||
        baseLoc.image2 == '' ||
        baseLoc.readingImage == '';

    if (!_imagesCache.containsKey(locationId) &&
        !hasLocalAny &&
        (baseLoc.modifiedDate != null || location.modifiedDate != null) &&
        !ApiClient.isNetworkBlocked) {
      try {
        await getLcpNapLocationImages(locationId);
      } catch (_) {}
    }

    try {
      final resolvedStreet = street ?? location.street ?? baseLoc.street;
      final resolvedBarangay =
          barangay ?? location.barangay ?? baseLoc.barangay;
      final resolvedCity = city ?? location.city ?? baseLoc.city;
      final resolvedRegion = region ?? location.region ?? baseLoc.region;

      final queryParams = <String, dynamic>{
        'LCP': resolvedLcp,
        'NAP': resolvedNap,
        'LCPNAP': resolvedLcpNap,
        'PortTotal': resolvedPortTotal,
        if (resolvedCoordinates.isNotEmpty) 'Coordinates': resolvedCoordinates,
        if (resolvedStreet != null) 'Street': resolvedStreet,
        if (resolvedBarangay != null) 'Barangay': resolvedBarangay,
        if (resolvedCity != null) 'City': resolvedCity,
        if (resolvedRegion != null) 'Region': resolvedRegion,
        'ModifiedBy': resolvedModifiedBy,
        if (resolvedUserEmail != null && resolvedUserEmail.trim().isNotEmpty)
          'UserEmail': resolvedUserEmail.trim(),
      };

      final map = <String, dynamic>{
        'LCP': resolvedLcp,
        'NAP': resolvedNap,
        'LCPNAP': resolvedLcpNap,
        'PortTotal': resolvedPortTotal.toString(),
        'Coordinates': resolvedCoordinates,
        if (resolvedStreet != null) 'Street': resolvedStreet,
        if (resolvedBarangay != null) 'Barangay': resolvedBarangay,
        if (resolvedCity != null) 'City': resolvedCity,
        if (resolvedRegion != null) 'Region': resolvedRegion,
        'ModifiedBy': resolvedModifiedBy,
        'ModifiedDate': nowIso,
        if (resolvedUserEmail != null && resolvedUserEmail.trim().isNotEmpty)
          'UserEmail': resolvedUserEmail.trim(),
      };

      final clear1 = !baseLoc.isSynced && baseLoc.image == '';
      final clear2 = !baseLoc.isSynced && baseLoc.image2 == '';
      final clearReading = !baseLoc.isSynced && baseLoc.readingImage == '';

      final existingEnc1 = clear1
          ? null
          : (_resolvePhotoBytes(baseLoc.image) ??
              _imagesCache[locationId]?.image?.bytes);
      final existingEnc2 = clear2
          ? null
          : (_resolvePhotoBytes(baseLoc.image2) ??
              _imagesCache[locationId]?.image2?.bytes);
      final existingReading = clearReading
          ? null
          : (_resolvePhotoBytes(baseLoc.readingImage) ??
              _imagesCache[locationId]?.readingImage?.bytes);

      if (clear1) {
        map['Image'] = MultipartFile.fromBytes(<int>[], filename: '');
      } else if (existingEnc1 != null && existingEnc1.isNotEmpty) {
        map['Image'] =
            MultipartFile.fromBytes(existingEnc1, filename: 'image.jpg');
      }

      if (clear2) {
        map['Image2'] = MultipartFile.fromBytes(<int>[], filename: '');
      } else if (existingEnc2 != null && existingEnc2.isNotEmpty) {
        map['Image2'] =
            MultipartFile.fromBytes(existingEnc2, filename: 'image2.jpg');
      }

      if (clearReading) {
        map['ReadingImage'] = MultipartFile.fromBytes(<int>[], filename: '');
      } else if (existingReading != null && existingReading.isNotEmpty) {
        map['ReadingImage'] = MultipartFile.fromBytes(existingReading,
            filename: 'readingImage.jpg');
      }

      final formData = FormData.fromMap(map);
      final response = await _api.put(
        '/LCPNapLocations/$locationId',
        data: formData,
        queryParameters: queryParams,
        options: Options(contentType: 'multipart/form-data'),
      );

      final isSuccess =
          response.statusCode == 200 || response.statusCode == 204;
      if (isSuccess) {
        final updatedDto = baseLoc.copyWith(
          lcp: resolvedLcp,
          nap: resolvedNap,
          lcpNap: resolvedLcpNap,
          portTotal: resolvedPortTotal,
          coordinates:
              resolvedCoordinates.isNotEmpty ? resolvedCoordinates : null,
          street: resolvedStreet,
          barangay: resolvedBarangay,
          city: resolvedCity,
          region: resolvedRegion,
          modifiedBy: resolvedModifiedBy,
          userEmail: resolvedUserEmail,
          clearImage: clear1,
          clearImage2: clear2,
          clearReadingImage: clearReading,
          modifiedDate: nowUtc,
          isSynced: true,
          updatedAt: DateTime.now(),
        );
        await _dao.insertOrUpdateLocation(updatedDto, synced: true);
      }
      return isSuccess;
    } catch (e) {
      if (_isHardClientError(e)) {
        return false;
      }
      // Local optimistic fallback when offline (preserving any queued offline photos)
      final updatedDto = baseLoc.copyWith(
        lcp: resolvedLcp,
        nap: resolvedNap,
        lcpNap: resolvedLcpNap,
        portTotal: resolvedPortTotal,
        coordinates:
            resolvedCoordinates.isNotEmpty ? resolvedCoordinates : null,
        street: street ?? location.street ?? baseLoc.street,
        barangay: barangay ?? location.barangay ?? baseLoc.barangay,
        city: city ?? location.city ?? baseLoc.city,
        region: region ?? location.region ?? baseLoc.region,
        modifiedBy: resolvedModifiedBy,
        userEmail: resolvedUserEmail,
        modifiedDate: nowUtc,
        isSynced: false,
        updatedAt: DateTime.now(),
      );
      await _dao.insertOrUpdateLocation(updatedDto, synced: false);
      return true;
    }
  }

  // Gene - Nov, 11, 2026: Create a new LCP NAP location record via multipart/form-data POST /api/LCPNapLocations with query & form binding and offline fallback.
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
    final cleanLcp = lcp.trim();
    final cleanNap = nap.trim();
    final cleanLcpNap = (lcpNap != null && lcpNap.trim().isNotEmpty)
        ? lcpNap.trim()
        : '$cleanLcp $cleanNap'.trim();
    final cleanCoords = (coordinates != null && coordinates.trim().isNotEmpty)
        ? coordinates.trim()
        : null;
    final cleanStreet =
        (street != null && street.trim().isNotEmpty) ? street.trim() : null;
    final cleanBarangay = (barangay != null && barangay.trim().isNotEmpty)
        ? barangay.trim()
        : null;
    final cleanCity =
        (city != null && city.trim().isNotEmpty) ? city.trim() : null;
    final cleanRegion =
        (region != null && region.trim().isNotEmpty) ? region.trim() : null;
    final resolvedModifiedBy =
        (modifiedBy != null && modifiedBy.trim().isNotEmpty)
            ? modifiedBy.trim()
            : '1';
    final resolvedUserEmail = (userEmail != null && userEmail.trim().isNotEmpty)
        ? userEmail.trim()
        : null;

    final nowUtc = DateTime.now().toUtc();
    final nowIso = nowUtc.toIso8601String();

    // Gene - Nov, 27, 2026: In replicated PowerSync mode, insert locally with a negative temporary ID so PowerSync ps_crud routes to idempotent POST /api/LCPNapLocations.
    if (_isReplicatedMode()) {
      final rawTemp = -(DateTime.now().millisecondsSinceEpoch % 1000000000);
      final tempId = rawTemp == 0 ? -1 : rawTemp;
      final savedImg1 = (imageBytes != null && imageBytes.isNotEmpty)
          ? await _persistPhotoSlotLocally(tempId, 'enc1', imageBytes)
          : null;
      final savedImg2 = (image2Bytes != null && image2Bytes.isNotEmpty)
          ? await _persistPhotoSlotLocally(tempId, 'enc2', image2Bytes)
          : null;
      final savedReading = (readingImageBytes != null &&
              readingImageBytes.isNotEmpty)
          ? await _persistPhotoSlotLocally(tempId, 'reading', readingImageBytes)
          : null;

      final offlineDto = LcpNapDto(
        id: tempId,
        lcp: cleanLcp,
        nap: cleanNap,
        lcpNap: cleanLcpNap,
        portTotal: portTotal,
        coordinates: cleanCoords,
        street: cleanStreet,
        barangay: cleanBarangay,
        city: cleanCity,
        region: cleanRegion,
        image: savedImg1,
        image2: savedImg2,
        readingImage: savedReading,
        modifiedBy: resolvedModifiedBy,
        userEmail: resolvedUserEmail,
        modifiedDate: nowUtc,
        isSynced: false,
        updatedAt: DateTime.now(),
      );
      await _dao.insertOrUpdateLocation(offlineDto, synced: false);
      return offlineDto;
    }

    final queryParams = <String, dynamic>{
      'LCP': cleanLcp,
      'NAP': cleanNap,
      'LCPNAP': cleanLcpNap,
      'PortTotal': portTotal,
      if (cleanCoords != null) 'Coordinates': cleanCoords,
      if (cleanStreet != null) 'Street': cleanStreet,
      if (cleanBarangay != null) 'Barangay': cleanBarangay,
      if (cleanCity != null) 'City': cleanCity,
      if (cleanRegion != null) 'Region': cleanRegion,
      'ModifiedBy': resolvedModifiedBy,
      if (resolvedUserEmail != null) 'UserEmail': resolvedUserEmail,
    };

    final map = <String, dynamic>{
      'LCP': cleanLcp,
      'NAP': cleanNap,
      'LCPNAP': cleanLcpNap,
      'PortTotal': portTotal.toString(),
      if (cleanCoords != null) 'Coordinates': cleanCoords,
      if (cleanStreet != null) 'Street': cleanStreet,
      if (cleanBarangay != null) 'Barangay': cleanBarangay,
      if (cleanCity != null) 'City': cleanCity,
      if (cleanRegion != null) 'Region': cleanRegion,
      'ModifiedBy': resolvedModifiedBy,
      'ModifiedDate': nowIso,
      if (resolvedUserEmail != null) 'UserEmail': resolvedUserEmail,
      if (imageBytes != null && imageBytes.isNotEmpty)
        'Image': MultipartFile.fromBytes(imageBytes, filename: 'image.jpg'),
      if (image2Bytes != null && image2Bytes.isNotEmpty)
        'Image2': MultipartFile.fromBytes(image2Bytes, filename: 'image2.jpg'),
      if (readingImageBytes != null && readingImageBytes.isNotEmpty)
        'ReadingImage': MultipartFile.fromBytes(
          readingImageBytes,
          filename: 'readingImage.jpg',
        ),
    };

    try {
      final response = await _api.post(
        '/LCPNapLocations',
        data: FormData.fromMap(map),
        queryParameters: queryParams,
        options: Options(contentType: 'multipart/form-data'),
      );

      final isSuccess = response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 204;
      if (!isSuccess) return null;

      int? assignedId;
      LcpNapDto? parsedDto;
      final data = response.data;
      if (data is Map<String, dynamic> && data.isNotEmpty) {
        final candidate = LcpNapDto.fromJson(data);
        if (candidate.id > 0) {
          assignedId = candidate.id;
          parsedDto = candidate;
        }
      } else if (data is int && data > 0) {
        assignedId = data;
      }

      // If response did not echo the full record with ID, check latest server list
      if (assignedId == null && !ApiClient.isNetworkBlocked) {
        try {
          final listRes = await _api.get('/LCPNapLocations');
          if (listRes.data is List) {
            final matches = <LcpNapDto>[
              for (final item in listRes.data as List)
                if (item is Map<String, dynamic>) LcpNapDto.fromJson(item),
            ].where((s) =>
                s.lcpNap.toLowerCase() == cleanLcpNap.toLowerCase() ||
                (s.lcp.toLowerCase() == cleanLcp.toLowerCase() &&
                    s.nap.toLowerCase() == cleanNap.toLowerCase()));
            if (matches.isNotEmpty) {
              final newest = matches.reduce((a, b) => a.id > b.id ? a : b);
              assignedId = newest.id;
              parsedDto = newest;
            }
          }
        } catch (_) {}
      }

      if (assignedId == null) {
        final existing = await _dao.getAllLocations();
        final maxId = existing.fold<int>(
          1000,
          (max, e) => e.id > max ? e.id : max,
        );
        assignedId = maxId + 1;
      }

      final savedImg1 = (imageBytes != null && imageBytes.isNotEmpty)
          ? await _persistPhotoSlotLocally(assignedId, 'enc1', imageBytes)
          : parsedDto?.image;
      final savedImg2 = (image2Bytes != null && image2Bytes.isNotEmpty)
          ? await _persistPhotoSlotLocally(assignedId, 'enc2', image2Bytes)
          : parsedDto?.image2;
      final savedReading =
          (readingImageBytes != null && readingImageBytes.isNotEmpty)
              ? await _persistPhotoSlotLocally(
                  assignedId, 'reading', readingImageBytes)
              : parsedDto?.readingImage;

      if ((imageBytes != null && imageBytes.isNotEmpty) ||
          (image2Bytes != null && image2Bytes.isNotEmpty) ||
          (readingImageBytes != null && readingImageBytes.isNotEmpty)) {
        _imagesCache[assignedId] = _buildImagesDtoFromBytes(
          enc1Bytes: imageBytes,
          enc2Bytes: image2Bytes,
          readingBytes: readingImageBytes,
        );
      }

      final createdDto = LcpNapDto(
        id: assignedId,
        lcp: cleanLcp,
        nap: cleanNap,
        lcpNap: cleanLcpNap,
        portTotal: portTotal,
        coordinates: cleanCoords ?? parsedDto?.coordinates,
        street: cleanStreet ?? parsedDto?.street,
        barangay: cleanBarangay ?? parsedDto?.barangay,
        city: cleanCity ?? parsedDto?.city,
        region: cleanRegion ?? parsedDto?.region,
        image: savedImg1,
        image2: savedImg2,
        readingImage: savedReading,
        modifiedBy: resolvedModifiedBy,
        userEmail: resolvedUserEmail,
        modifiedDate: nowUtc,
        isSynced: true,
        updatedAt: DateTime.now(),
      );

      await _dao.insertOrUpdateLocation(createdDto, synced: true);
      return createdDto;
    } catch (e) {
      if (_isHardClientError(e)) {
        return null;
      }

      // Offline fallback: allocate a negative temporary ID so syncPendingLocations knows to POST it on reconnect
      final tempId = -(DateTime.now().millisecondsSinceEpoch % 1000000000);
      final savedImg1 = (imageBytes != null && imageBytes.isNotEmpty)
          ? await _persistPhotoSlotLocally(tempId, 'enc1', imageBytes)
          : null;
      final savedImg2 = (image2Bytes != null && image2Bytes.isNotEmpty)
          ? await _persistPhotoSlotLocally(tempId, 'enc2', image2Bytes)
          : null;
      final savedReading = (readingImageBytes != null &&
              readingImageBytes.isNotEmpty)
          ? await _persistPhotoSlotLocally(tempId, 'reading', readingImageBytes)
          : null;

      final offlineDto = LcpNapDto(
        id: tempId,
        lcp: cleanLcp,
        nap: cleanNap,
        lcpNap: cleanLcpNap,
        portTotal: portTotal,
        coordinates: cleanCoords,
        street: cleanStreet,
        barangay: cleanBarangay,
        city: cleanCity,
        region: cleanRegion,
        image: savedImg1,
        image2: savedImg2,
        readingImage: savedReading,
        modifiedBy: resolvedModifiedBy,
        userEmail: resolvedUserEmail,
        modifiedDate: nowUtc,
        isSynced: false,
        updatedAt: DateTime.now(),
      );
      await _dao.insertOrUpdateLocation(offlineDto, synced: false);
      return offlineDto;
    }
  }

  // Gene - Nov, 11, 2026: Single-flight background auto-sync worker that pushes all queued offline LCP NAP photo uploads, photo deletions, and GPS coordinate updates to PUT /LCPNapLocations/{id}.
  Future<int> syncPendingLocations() {
    if (_isReplicatedMode()) {
      return Future.value(0);
    }
    final inFlight = _activeSyncPendingFuture;
    if (inFlight != null) {
      return inFlight;
    }
    final future = _runSyncPendingLocations();
    _activeSyncPendingFuture = future;
    return future.whenComplete(() {
      if (identical(_activeSyncPendingFuture, future)) {
        _activeSyncPendingFuture = null;
      }
    });
  }

  Future<int> _runSyncPendingLocations() async {
    if (ApiClient.isNetworkBlocked) return 0;

    final pending = await _dao.getUnsyncedLocations();
    if (pending.isEmpty) return 0;

    var syncedCount = 0;
    for (final loc in pending) {
      final clearImg1 = loc.image != null && loc.image!.isEmpty;
      final clearImg2 = loc.image2 != null && loc.image2!.isEmpty;
      final clearReading =
          loc.readingImage != null && loc.readingImage!.isEmpty;

      var enc1Bytes = clearImg1 ? null : _resolvePhotoBytes(loc.image);
      var enc2Bytes = clearImg2 ? null : _resolvePhotoBytes(loc.image2);
      var readingBytes =
          clearReading ? null : _resolvePhotoBytes(loc.readingImage);

      // Gene - Nov, 11, 2026: If loc.id < 0, this record was created offline and needs POST /LCPNapLocations.
      if (loc.id < 0) {
        final created = await createLocation(
          lcp: loc.lcp,
          nap: loc.nap,
          lcpNap: loc.lcpNap,
          portTotal: loc.portTotal,
          coordinates: loc.coordinates,
          street: loc.street,
          barangay: loc.barangay,
          city: loc.city,
          region: loc.region,
          modifiedBy: loc.modifiedBy,
          userEmail: loc.userEmail,
          imageBytes: enc1Bytes,
          image2Bytes: enc2Bytes,
          readingImageBytes: readingBytes,
        );
        if (created != null && created.isSynced && created.id > 0) {
          await _dao.deleteLocation(loc.id);
          syncedCount++;
          continue;
        } else {
          break;
        }
      }

      // If this was an offline GPS-only edit with cold photo cache, fetch existing server photos first so PUT preserves them
      if (!clearImg1 &&
          !clearImg2 &&
          !clearReading &&
          enc1Bytes == null &&
          enc2Bytes == null &&
          readingBytes == null &&
          !_imagesCache.containsKey(loc.id) &&
          loc.modifiedDate != null) {
        try {
          await getLcpNapLocationImages(loc.id);
        } catch (_) {
          // Still offline: stop batch early
          break;
        }
      }

      enc1Bytes ??= clearImg1 ? null : _imagesCache[loc.id]?.image?.bytes;
      enc2Bytes ??= clearImg2 ? null : _imagesCache[loc.id]?.image2?.bytes;
      readingBytes ??=
          clearReading ? null : _imagesCache[loc.id]?.readingImage?.bytes;

      final nowUtc = DateTime.now().toUtc();
      final nowIso = nowUtc.toIso8601String();
      final map = <String, dynamic>{
        'LCP': loc.lcp,
        'NAP': loc.nap,
        'LCPNAP': loc.lcpNap,
        'PortTotal': loc.portTotal.toString(),
        if (loc.coordinates != null) 'Coordinates': loc.coordinates,
        if (loc.street != null) 'Street': loc.street,
        if (loc.barangay != null) 'Barangay': loc.barangay,
        if (loc.city != null) 'City': loc.city,
        if (loc.region != null) 'Region': loc.region,
        'ModifiedBy': loc.modifiedBy ?? '1',
        'ModifiedDate': nowIso,
        if (loc.userEmail != null && loc.userEmail!.trim().isNotEmpty)
          'UserEmail': loc.userEmail!.trim(),
      };

      if (clearImg1) {
        map['Image'] = MultipartFile.fromBytes(<int>[], filename: '');
      } else if (enc1Bytes != null && enc1Bytes.isNotEmpty) {
        map['Image'] =
            MultipartFile.fromBytes(enc1Bytes, filename: 'image.jpg');
      }

      if (clearImg2) {
        map['Image2'] = MultipartFile.fromBytes(<int>[], filename: '');
      } else if (enc2Bytes != null && enc2Bytes.isNotEmpty) {
        map['Image2'] =
            MultipartFile.fromBytes(enc2Bytes, filename: 'image2.jpg');
      }

      if (clearReading) {
        map['ReadingImage'] = MultipartFile.fromBytes(<int>[], filename: '');
      } else if (readingBytes != null && readingBytes.isNotEmpty) {
        map['ReadingImage'] =
            MultipartFile.fromBytes(readingBytes, filename: 'readingImage.jpg');
      }

      try {
        final response = await _api.put(
          '/LCPNapLocations/${loc.id}',
          data: FormData.fromMap(map),
          options: Options(contentType: 'multipart/form-data'),
        );
        if (response.statusCode == 200 || response.statusCode == 204) {
          _imagesCache[loc.id] = _buildImagesDtoFromBytes(
            enc1Bytes: enc1Bytes,
            enc2Bytes: enc2Bytes,
            readingBytes: readingBytes,
          );
          final syncedDto = loc.copyWith(
            clearImage: clearImg1,
            clearImage2: clearImg2,
            clearReadingImage: clearReading,
            modifiedDate: nowUtc,
            isSynced: true,
            updatedAt: DateTime.now(),
          );
          await _dao.insertOrUpdateLocation(syncedDto, synced: true);
          syncedCount++;
        }
      } catch (e) {
        if (!_isHardClientError(e)) {
          // Network still unreachable: abort remaining items until next reconnect/cycle
          break;
        }
      }
    }

    return syncedCount;
  }
}
