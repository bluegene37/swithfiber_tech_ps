import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
// Gene - Nov, 8, 2026: Imported DataUrl and Dio FormData/MultipartFile so PUT /api/ServiceOrders/{id} conforms to backend multipart/form-data contract.
import '../../../core/utils/data_url.dart';
import '../models/service_order_model.dart';

/// API client for interacting with `/api/ServiceOrders` on the Switch Fiber backend.
class ServiceOrdersApi {
  final ApiClient _api;

  ServiceOrdersApi([ApiClient? api]) : _api = api ?? ApiClient.instance;

  /// Fetch all active service orders from the backend
  Future<List<ServiceOrderDto>> fetchServiceOrders() async {
    final response = await _api.get('/ServiceOrders');
    /*
    final data = response.data;
    if (data is List) {
      return [
        for (final item in data)
          if (item is Map<String, dynamic>) ServiceOrderDto.fromJson(item),
      ];
    }
    return [];
    */
    // Gene - Nov, 13, 2026: Reject unexpected non-list payloads instead of silently returning [] so verified empty lists can safely prune deleted live service orders.
    final data = response.data;
    if (data == null) return [];
    if (data is List) {
      return [
        for (final item in data)
          if (item is Map<String, dynamic>) ServiceOrderDto.fromJson(item),
      ];
    }
    throw const FormatException(
      'Unexpected non-list response from /ServiceOrders',
    );
  }

  /// Fetch a single service order by its unique ID
  Future<ServiceOrderDto?> fetchServiceOrderById(int id) async {
    final response = await _api.get('/ServiceOrders/$id');
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return ServiceOrderDto.fromJson(data);
    }
    return null;
  }

  /// Update a service order (e.g. submit completion, equipment swap, or materials)
  /*
  Future<bool> updateServiceOrder(int id, Map<String, dynamic> payload) async {
    final response = await _api.put('/ServiceOrders/$id', data: payload);
    return response.statusCode == 200 || response.statusCode == 204;
  }
  */
  // Gene - Nov, 8, 2026: Send PUT /api/ServiceOrders/{id} as multipart/form-data with IFormFile attachments for ClientSignature, Image1, Image2, Image3, and HouseFrontPicture per live OpenAPI contract.
  Future<bool> updateServiceOrder(int id, Map<String, dynamic> payload) async {
    const fileFieldMapping = <String, String>{
      'clientSignature': 'ClientSignature',
      'image1': 'Image1',
      'image2': 'Image2',
      'image3': 'Image3',
      'houseFrontPicture': 'HouseFrontPicture',
    };

    final formMap = <String, dynamic>{};
    payload.forEach((key, value) {
      if (value == null) return;
      final fileParam = fileFieldMapping[key];
      if (fileParam != null) {
        final strVal = value.toString().trim();
        if (strVal.isEmpty) {
          // Omitted when explicitly cleared so the server clears/ignores the slot
          return;
        }
        final bytes = DataUrl.decode(strVal);
        if (bytes != null && bytes.isNotEmpty) {
          formMap[fileParam] = MultipartFile.fromBytes(
            bytes,
            filename: '${key.toLowerCase()}.jpg',
          );
        }
        return;
      }
      formMap[key] = value.toString();
    });

    final formData = FormData.fromMap(formMap);
    final response = await _api.put(
      '/ServiceOrders/$id',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    return response.statusCode == 200 || response.statusCode == 204;
  }
}
