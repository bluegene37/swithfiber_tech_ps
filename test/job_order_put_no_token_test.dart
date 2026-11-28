import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/constants/app_constants.dart';
import 'package:swithfiber_tech_ps/core/network/api_client.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';

/// Records every outgoing request instead of hitting the live server.
class _RecordingAdapter implements HttpClientAdapter {
  final captured = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    captured.add(options);
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingAdapter adapter;

  setUp(() {
    // A signed-in phone holds a token; the point is what the PUT does with it.
    final store = <String, String>{AppConstants.keyJwtToken: 'jwt-abc'};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async =>
          call.method == 'read' ? store[call.arguments['key']] : null,
    );

    adapter = _RecordingAdapter();
    final dio = ApiClient.instance.dio;
    // This test drives a mocked HTTP adapter through the real client.
    ApiClient.blockNetworkForTesting = false;
    addTearDown(() => ApiClient.blockNetworkForTesting = true);
    final original = dio.httpClientAdapter;
    dio.httpClientAdapter = adapter;
    addTearDown(() => dio.httpClientAdapter = original);
  });

  test('the job order PUT sends the Authorization Bearer session token',
      () async {
    await DioJobOrdersApi().update(3979, {'status': 'Completed'});

    final put = adapter.captured.single;
    expect(put.method, 'PUT');
    expect(put.uri.toString(), endsWith('/api/JobOrders/3979'));
    // Gene - Nov, 28, 2026: Gateway / API endpoints enforce Authorization: Bearer <sessionToken> on PUT/PATCH/POST/GET.
    expect(put.headers['Authorization'], 'Bearer jwt-abc');
    expect(put.headers['Content-Type'], 'application/json');
  });

  test('every other call still carries the token', () async {
    await DioJobOrdersApi().fetchById(3979);

    final get = adapter.captured.single;
    expect(get.method, 'GET');
    expect(get.headers['Authorization'], 'Bearer jwt-abc',
        reason: 'only the update is sent bare');
  });
}
