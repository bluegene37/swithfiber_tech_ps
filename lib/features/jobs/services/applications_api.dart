// Gene - Oct 24, 2026: Service for querying customer application images via GET /api/Applications/{id}/GetApplicationImages.
import '../../../core/network/api_client.dart';
import '../models/application_images_model.dart';

/// Service for fetching customer application images and KYC proofs.
class ApplicationsApi {
  static final ApplicationsApi instance = ApplicationsApi._internal();
  final ApiClient _api;

  ApplicationsApi._internal([ApiClient? api])
      : _api = api ?? ApiClient.instance;

  factory ApplicationsApi({ApiClient? api}) =>
      api == null ? instance : ApplicationsApi._internal(api);

  final Map<String, ApplicationImagesDto> _cache = {};

  /// Clears in-memory image cache (useful in tests).
  void clearCache() {
    _cache.clear();
  }

  /// Fetches application images for [applicationId] (the string tracking ID, e.g. "202610232250088505279").
  Future<ApplicationImagesDto?> getApplicationImages(
    String applicationId, {
    bool forceRefresh = false,
  }) async {
    final cleanId = applicationId.trim();
    if (cleanId.isEmpty) return null;

    if (!forceRefresh && _cache.containsKey(cleanId)) {
      return _cache[cleanId];
    }

    try {
      final response =
          await _api.get('/Applications/$cleanId/GetApplicationImages');
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final dto = ApplicationImagesDto.fromJson(data);
        if (dto.hasAnyImage) {
          _cache[cleanId] = dto;
        }
        return dto;
      }
    } catch (_) {
      // 404 Not Found, empty, offline, or tests network block
    }
    return _cache[cleanId];
  }
}
