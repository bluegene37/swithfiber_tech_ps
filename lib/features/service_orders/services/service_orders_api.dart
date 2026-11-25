import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
// Gene - Nov, 25, 2026: Added ApiException import for 404 handling in fetchServiceOrderImages.
import '../../../core/network/network_exceptions.dart';
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

  // Gene - Nov, 25, 2026: Fetch Service Order images and client signature from GET /api/ServiceOrders/{id}/GetServiceOrderImage.
  Future<Map<String, dynamic>?> fetchServiceOrderImages(int id) async {
    try {
      final response =
          await _api.get('/ServiceOrders/$id/GetServiceOrderImage');
      final data = response.data;
      return data is Map<String, dynamic> ? data : null;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  static const Map<String, String> _scalarParamMapping = <String, String>{
    'createdDate': 'CreatedDate',
    'accountNumber': 'AccountNumber',
    'dateInstalled': 'DateInstalled',
    'fullName': 'FullName',
    'contactNumber': 'ContactNumber',
    'emailAddress': 'EmailAddress',
    'address': 'Address',
    'plan': 'Plan',
    'provider': 'Provider',
    'username': 'Username',
    'connectionType': 'ConnectionType',
    'routerModemSN': 'RouterModemSN',
    'lcp': 'Lcp',
    'nap': 'Nap',
    'port': 'Port',
    'vlan': 'Vlan',
    'supportStatus': 'SupportStatus',
    'concern': 'Concern',
    'connectionRemarks': 'ConnectionRemarks',
    'priorityLevel': 'PriorityLevel',
    'visitStatus': 'VisitStatus',
    'visitBy': 'VisitBy',
    'visitWith': 'VisitWith',
    'visitWithOthers': 'VisitWithOthers',
    'visitRemarks': 'VisitRemarks',
    'modifiedBy': 'ModifiedBy',
    'modifiedDate': 'ModifiedDate',
    'userEmail': 'UserEmail',
    'requestedBy': 'RequestedBy',
    'assignedEmail': 'AssignedEmail',
    'startTimestamp': 'StartTimestamp',
    'stopTimestamp': 'StopTimestamp',
    'duration': 'Duration',
    'repairCategory': 'RepairCategory',
    'newRouterModemSN': 'NewRouterModemSN',
    'newLCP': 'NewLCP',
    'newNAP': 'NewNAP',
    'newPORT': 'NewPORT',
    'newVLAN': 'NewVLAN',
    'routerModel': 'RouterModel',
    'newPLAN': 'NewPLAN',
    'supportRemarks': 'SupportRemarks',
    'pulloutRemarks': 'PulloutRemarks',
    'pulloutRouterModel': 'PulloutRouterModel',
    'pulloutRouterModelSN': 'PulloutRouterModelSN',
    'pulloutCPESN': 'PulloutCPESN',
    'itemName': 'ItemName',
    'itemQuantity': 'ItemQuantity',
    'itemName1': 'ItemName1',
    'itemQuantity1': 'ItemQuantity1',
    'itemName2': 'ItemName2',
    'itemQuantity2': 'ItemQuantity2',
    'itemName3': 'ItemName3',
    'itemQuantity3': 'ItemQuantity3',
    'itemName4': 'ItemName4',
    'itemQuantity4': 'ItemQuantity4',
    'itemName5': 'ItemName5',
    'itemQuantity5': 'ItemQuantity5',
    'itemName6': 'ItemName6',
    'itemQuantity6': 'ItemQuantity6',
    'itemName7': 'ItemName7',
    'itemQuantity7': 'ItemQuantity7',
    'itemName8': 'ItemName8',
    'itemQuantity8': 'ItemQuantity8',
    'itemName9': 'ItemName9',
    'itemQuantity9': 'ItemQuantity9',
    'itemName10': 'ItemName10',
    'itemQuantity10': 'ItemQuantity10',
    'serviceCharge': 'ServiceCharge',
    'barangay': 'Barangay',
    'city': 'City',
    'addressCoordinates': 'AddressCoordinates',
    'techModifiedDate': 'TechModifiedDate',
    'assignedBy': 'AssignedBy',
    'assignedDate': 'AssignedDate',
  };

  /// Update a service order (e.g. submit completion, equipment swap, or materials)
  /*
  Future<bool> updateServiceOrder(int id, Map<String, dynamic> payload) async {
    final response = await _api.put('/ServiceOrders/$id', data: payload);
    return response.statusCode == 200 || response.statusCode == 204;
  }
  */
  /*
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
  */
  // Gene - Nov, 25, 2026: Align PUT /api/ServiceOrders/{id} with live OpenAPI contract: PascalCase queryParameters for scalars + multipart/form-data IFormFile attachments (including explicit empty file clears and PNG/JPG mime detection).
  Future<bool> updateServiceOrder(int id, Map<String, dynamic> payload) async {
    const fileFieldMapping = <String, String>{
      'clientSignature': 'ClientSignature',
      'image1': 'Image1',
      'image2': 'Image2',
      'image3': 'Image3',
      'houseFrontPicture': 'HouseFrontPicture',
      'ClientSignature': 'ClientSignature',
      'Image1': 'Image1',
      'Image2': 'Image2',
      'Image3': 'Image3',
      'HouseFrontPicture': 'HouseFrontPicture',
    };

    final queryParams = <String, dynamic>{};
    final formMap = <String, dynamic>{};

    payload.forEach((key, value) {
      if (value == null) return;
      final fileParam = fileFieldMapping[key];
      if (fileParam != null) {
        final strVal = value.toString().trim();
        if (strVal.isEmpty) {
          // Send empty MultipartFile on explicit photo removal (same pattern as LCPNapLocations).
          formMap[fileParam] = MultipartFile.fromBytes(<int>[], filename: '');
          return;
        }
        if (DataUrl.isDataUrl(strVal)) {
          final bytes = DataUrl.decode(strVal);
          if (bytes != null && bytes.isNotEmpty) {
            final mime = DataUrl.mimeTypeOf(strVal);
            final ext = mime == 'image/png' ? 'png' : 'jpg';
            formMap[fileParam] = MultipartFile.fromBytes(
              bytes,
              filename: '${fileParam.toLowerCase()}.$ext',
            );
          }
        }
        // Existing server filenames/URLs are omitted as IFormFile parts so the server preserves them.
        return;
      }

      if (key == 'id' || key == 'Id') return;

      final mappedKey = _scalarParamMapping[key] ??
          (_scalarParamMapping.containsValue(key) ? key : null);
      final strScalar = value.toString();
      if (mappedKey != null) {
        queryParams[mappedKey] = strScalar;
        formMap[mappedKey] = strScalar;
      } else {
        formMap[key] = strScalar;
      }
    });

    final formData = FormData.fromMap(formMap);
    final response = await _api.put(
      '/ServiceOrders/$id',
      data: formData,
      queryParameters: queryParams.isEmpty ? null : queryParams,
      options: Options(contentType: 'multipart/form-data'),
    );
    return response.statusCode == 200 || response.statusCode == 204;
  }

  // Gene - Nov, 25, 2026: Added POST /ServiceOrders/createtiming and PUT /ServiceOrders/updatetiming for Start/Finish tracking.
  Future<bool> createTiming({
    required int joId,
    required String techId,
    required DateTime startTime,
    DateTime? endTime,
  }) async {
    final startIso = startTime.toUtc().toIso8601String();
    final endIso = (endTime ?? startTime).toUtc().toIso8601String();
    final response = await _api.post(
      '/ServiceOrders/createtiming',
      data: {
        'joId': joId,
        'techId': techId,
        'startTime': startIso,
        'endTime': endIso,
      },
    );
    return response.statusCode == 200 ||
        response.statusCode == 201 ||
        response.statusCode == 204;
  }

  Future<bool> updateTiming({
    required int joId,
    required String techId,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final response = await _api.put(
      '/ServiceOrders/updatetiming',
      data: {
        'joId': joId,
        'techId': techId,
        'startTime': startTime.toUtc().toIso8601String(),
        'endTime': endTime.toUtc().toIso8601String(),
      },
    );
    return response.statusCode == 200 || response.statusCode == 204;
  }
}
