/// Application constants and storage keys.
class AppConstants {
  // Gene - Oct 08, 2026: Updated appName from 'Switch Fiber Tech' to 'SwitchFiber Tech'
  // static const String appName = 'Switch Fiber Tech';
  // Gene - Oct 09, 2026: Updated appName to 'SF Tech' to match app label
  // static const String appName = 'SwitchFiber Tech';
  static const String appName = 'SF Tech';
  // Gene - Nov, 11, 2026: Updated appVersion from '1.0.0' to '1.0.3' to match pubspec.yaml store release version.
  // static const String appVersion = '1.0.0';
  static const String appVersion = '1.0.3';
  static const String companyName = 'Switch Fiber';
  static const String appTagline = 'Distributed Fiber Network Management';

  // API Config
  // Gene - Oct 13, 2026: Updated defaultBaseUrl to production domain https://admin.switchfiber.ph/api over standard HTTPS port 443.
  static const String defaultBaseUrl = 'https://admin.switchfiber.ph/api';
  static const int connectTimeout = 30000; // 30s
  /*
  // GET /JobOrders/status/Activated returns every finished job (~10 MB, a few
  // seconds on the current server, far longer on a poor mobile link). Kept
  // generous until the endpoint can be scoped to one technician.
  */
  // Gene - Nov, 23, 2026: Updated note: JobRepository.fetchRemoteJobs now fetches GET /JobOrders/status-assigned scoped per technician; 120s receive timeout is kept generous for slow mobile links.
  static const int receiveTimeout = 120000; // 120s

  /// SHA-256 fingerprint of the API server's self-signed certificate.
  /// Update this whenever the server certificate is reissued.
  static const String pinnedApiCertSha256 =
      'E8:4A:39:61:FB:BC:68:C4:21:38:8A:71:D7:41:2C:8E:'
      '14:CB:BA:2A:BC:F5:E9:E4:03:65:F6:A7:D5:2E:FA:CC';

  // Storage Keys
  static const String keyJwtToken = 'jwt_token';
  static const String keyUserSession = 'user_session';
  static const String keyApiBaseUrl = 'api_base_url';
  static const String keyDarkMode = 'dark_mode_enabled';
  static const String keyPowerSyncToken = 'powersync_token';
  // Gene - Nov, 27, 2026: Added PowerSync Gateway token/session keys and compile-time gateway URL config.
  static const String keyPowerSyncGatewayToken = 'powersync_gateway_token';
  // Gene - Nov, 28, 2026: Track gateway session expiry, lookups ETag, and optional gateway URL override for PowerSync v12.
  static const String keyPowerSyncGatewayTokenExpiresAt =
      'powersync_gateway_token_expires_at';
  static const String keyLookupsEtag = 'lookups_etag';
  static const String keyPowerSyncGatewayUrlOverride =
      'powersync_gateway_url_override';
  static const String keyPowerSyncTokenExpiresAt = 'powersync_token_expires_at';
  static const String keyPowerSyncUserId = 'powersync_user_id';
  static const String keyPowerSyncEndpoint = 'powersync_endpoint';
  // Gene - Nov, 20, 2026: Added local storage keys for tracking read Job Orders and Service Orders across restarts.
  static const String keyReadJobIds = 'read_job_order_ids';
  static const String keyReadServiceOrderIds = 'read_service_order_ids';
  // Gene - Nov, 23, 2026: Added storage keys for technician navigation app preference and same-day crew partner memory.
  static const String keyPreferredNavApp = 'preferred_nav_app';
  static const String keyLastVisitWith = 'last_visit_with';
  static const String keyLastVisitWithDate = 'last_visit_with_date';

  // PowerSync Self-Hosted Server Config
  // Gene - Nov, 23, 2026: Moved PowerSync endpoint and dev signing key to compile-time --dart-define environment variables so no server IP or secret is hardcoded in source.
  static const String defaultPowerSyncEndpoint =
      String.fromEnvironment('POWERSYNC_ENDPOINT', defaultValue: '');
  // Gene - Nov, 27, 2026: Added compile-time PowerSync Gateway base URL and helper to detect replicated PowerSync configuration.
  static const String defaultPowerSyncGatewayUrl =
      String.fromEnvironment('POWERSYNC_GATEWAY_URL', defaultValue: '');
  /*
  static bool get isPowerSyncConfigured =>
      defaultPowerSyncEndpoint.trim().isNotEmpty;
  */
  /*
  // Gene - Nov, 28, 2026: Require both POWERSYNC_ENDPOINT and POWERSYNC_GATEWAY_URL so replicated mode never runs without an upload gateway.
  static bool get isPowerSyncConfigured =>
      defaultPowerSyncEndpoint.trim().isNotEmpty &&
      defaultPowerSyncGatewayUrl.trim().isNotEmpty;
  */
  // Gene - Nov, 28, 2026: Gateway login/refresh dynamically returns powersync.endpoint, so configuring POWERSYNC_GATEWAY_URL activates replicated PowerSync mode.
  static bool get isPowerSyncConfigured =>
      defaultPowerSyncGatewayUrl.trim().isNotEmpty;
  static const String devSecretKey =
      String.fromEnvironment('POWERSYNC_DEV_KEY', defaultValue: '');

  // Optical Power dBm Standards (GPON standard)
  static const double opticalMinOptimal = -24.0;
  static const double opticalMaxOptimal = -12.0;
  static const double opticalMarginalFloor = -27.0;
  static const double opticalSaturationCeiling = -8.0;

  // Job Order Status Constants: see JobStatus for the workflow.
  static const String statusScheduled = 'Scheduled';
  static const String statusActivated = 'Activated';
  static const String statusCompleted = 'Completed';
}
