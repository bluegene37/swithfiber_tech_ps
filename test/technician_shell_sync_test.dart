import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swithfiber_tech_ps/core/database/app_database.dart';
import 'package:swithfiber_tech_ps/features/auth/models/user_model.dart';
import 'package:swithfiber_tech_ps/features/auth/signals/auth_signals.dart';
import 'package:swithfiber_tech_ps/features/jobs/repositories/job_repository.dart';
import 'package:swithfiber_tech_ps/features/jobs/services/job_orders_api.dart';
import 'package:swithfiber_tech_ps/features/jobs/signals/jobs_signals.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/repositories/lcp_nap_repository.dart';
import 'package:swithfiber_tech_ps/features/lcp_nap/signals/lcp_nap_signals.dart';
import 'package:swithfiber_tech_ps/features/service_orders/models/service_order_model.dart';
import 'package:swithfiber_tech_ps/features/service_orders/services/service_orders_api.dart';
import 'package:swithfiber_tech_ps/features/service_orders/signals/service_orders_signals.dart';
import 'package:swithfiber_tech_ps/features/shell/technician_shell.dart';

class _TrackingJobsApi implements JobOrdersApi {
  int fetchCallCount = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchByStatus(String status) async => [];

  @override
  Future<List<Map<String, dynamic>>> fetchByStatusAssigned({
    required String status,
    String? assignedEmail,
  }) async {
    fetchCallCount++;
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchByStatusDate({
    String? status,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async =>
      [];

  @override
  Future<Map<String, dynamic>?> fetchById(int id) async => null;

  @override
  Future<void> update(int id, Map<String, dynamic> body) async {}
}

class _TrackingServiceApi extends ServiceOrdersApi {
  int fetchCallCount = 0;

  @override
  Future<List<ServiceOrderDto>> fetchServiceOrders() async {
    fetchCallCount++;
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TechnicianShell Lifecycle and Auto-Sync Tests', () {
    testWidgets('triggers background sync on AppLifecycleState.resumed',
        (tester) async {
      late AppDatabase db;
      late _TrackingJobsApi jobsApi;
      late _TrackingServiceApi serviceApi;
      late JobRepository jobRepository;
      late JobsSignals jobsSignals;
      late LcpNapSignals lcpNapSignals;
      late ServiceOrdersSignals serviceOrdersSignals;

      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        jobsApi = _TrackingJobsApi();
        serviceApi = _TrackingServiceApi();
        jobRepository = JobRepository(db.jobOrdersDao, api: jobsApi);
        jobsSignals = JobsSignals(jobRepository);
        jobsSignals.setTechnicianEmail('tech@switchfiber.ph');
        lcpNapSignals = LcpNapSignals(LcpNapRepository(db.lcpNapLocationsDao));
        serviceOrdersSignals = ServiceOrdersSignals(api: serviceApi);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      addTearDown(() async {
        await jobsSignals.dispose();
        await lcpNapSignals.dispose();
        serviceOrdersSignals.dispose();
        await db.close();
      });

      AuthSignals.instance.currentUser.value = UserModel(
        id: 1,
        username: 'tech_juan',
        fname: 'Juan',
        lname: 'Dela Cruz',
        email: 'tech@switchfiber.ph',
      );

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: TechnicianShell(
              authSignals: AuthSignals.instance,
              jobsSignals: jobsSignals,
              lcpNapSignals: lcpNapSignals,
              serviceOrdersSignals: serviceOrdersSignals,
              enableAutoSync: false,
            ),
          ),
        );
        // Allow real database I/O to complete initial fetch and phase transition
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      });
      await tester.pump();

      final initialJobsCalls = jobsApi.fetchCallCount;
      expect(initialJobsCalls, 5,
          reason: 'Initial load must fetch all 5 statuses');

      // Transition lifecycle to resumed
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      await tester.runAsync(() async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(jobsApi.fetchCallCount, greaterThan(initialJobsCalls),
          reason:
              'AppLifecycleState.resumed must trigger automatic remote sync');
    });

    testWidgets('triggers background sync when tapping on bottom tabs',
        (tester) async {
      late AppDatabase db;
      late _TrackingJobsApi jobsApi;
      late _TrackingServiceApi serviceApi;
      late JobRepository jobRepository;
      late JobsSignals jobsSignals;
      late LcpNapSignals lcpNapSignals;
      late ServiceOrdersSignals serviceOrdersSignals;

      await tester.runAsync(() async {
        db = AppDatabase.forTesting();
        jobsApi = _TrackingJobsApi();
        serviceApi = _TrackingServiceApi();
        jobRepository = JobRepository(db.jobOrdersDao, api: jobsApi);
        jobsSignals = JobsSignals(jobRepository);
        jobsSignals.setTechnicianEmail('tech@switchfiber.ph');
        lcpNapSignals = LcpNapSignals(LcpNapRepository(db.lcpNapLocationsDao));
        serviceOrdersSignals = ServiceOrdersSignals(api: serviceApi);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      addTearDown(() async {
        await jobsSignals.dispose();
        await lcpNapSignals.dispose();
        serviceOrdersSignals.dispose();
        await db.close();
      });

      AuthSignals.instance.currentUser.value = UserModel(
        id: 1,
        username: 'tech_juan',
        fname: 'Juan',
        lname: 'Dela Cruz',
        email: 'tech@switchfiber.ph',
      );

      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: TechnicianShell(
              authSignals: AuthSignals.instance,
              jobsSignals: jobsSignals,
              lcpNapSignals: lcpNapSignals,
              serviceOrdersSignals: serviceOrdersSignals,
              enableAutoSync: false,
            ),
          ),
        );
        // Allow real database I/O to complete initial fetch and phase transition
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      });
      await tester.pump();

      final initialJobsCalls = jobsApi.fetchCallCount;
      expect(initialJobsCalls, 5,
          reason: 'Initial load must fetch all 5 statuses');

      // Tap on Repairs tab inside runAsync
      await tester.runAsync(() async {
        await tester.tap(find.text('Repairs'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(jobsApi.fetchCallCount, greaterThan(initialJobsCalls),
          reason: 'Switching tabs must trigger background sync');
    });
  });
}
