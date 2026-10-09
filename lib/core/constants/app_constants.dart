/// Application constants and storage keys.
class AppConstants {
  // Gene - Oct 08, 2026: Updated appName from 'Switch Fiber Tech' to 'SwitchFiber Tech'
  // static const String appName = 'Switch Fiber Tech';
  // Gene - Oct 09, 2026: Updated appName to 'SF Tech' to match app label
  // static const String appName = 'SwitchFiber Tech';
  static const String appName = 'SF Tech';
  static const String appVersion = '1.0.0';
  static const String companyName = 'Switch Fiber';
  static const String appTagline = 'Distributed Fiber Network Management';

  // API Config
  static const String defaultBaseUrl = 'https://103.249.198.50:8090/api';
  static const int connectTimeout = 30000; // 30s
  // GET /JobOrders/status/Activated returns every finished job (~10 MB, a few
  // seconds on the current server, far longer on a poor mobile link). Kept
  // generous until the endpoint can be scoped to one technician.
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

  // PowerSync Self-Hosted Server Config
  static const String defaultPowerSyncEndpoint = 'http://103.249.198.50:8080';

  /// Development shared secret matching service.yaml for local/direct sync.
  static const String devSecretKey =
      'switchfiber_powersync_dev_secret_key_2026';

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
