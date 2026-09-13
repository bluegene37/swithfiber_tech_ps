<p align="center">
  <img src="assets/images/logo.png" alt="Switch Fiber" width="96">
</p>

<h1 align="center">Switch Fiber Tech (PowerSync)</h1>

<p align="center">
  Field operations application for Switch Fiber installation and repair technicians.<br>
  Offline-first, built with Flutter for Android and iOS using PowerSync.
</p>

<p align="center">
  <a href="https://github.com/bluegene37/swithfiber_tech_ps/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/bluegene37/swithfiber_tech_ps/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Flutter 3.47" src="https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white">
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Android%20%7C%20iOS-3DDC84">
  <img alt="Version" src="https://img.shields.io/badge/version-1.0.0-E02424">
</p>

---

Switch Fiber Tech puts a technician's entire operational day in one glance: scheduled installations, assigned repair tickets, network plant (LCP/NAP) mapping, and pole-side fiber calculators. Built on an offline-first architecture with PowerSync and local SQLite storage, the app operates reliably in basements and dead zones without signal, seamlessly synchronizing changes when network connectivity is restored.

## Features

The application is structured into five primary areas: **Today**, **Repairs**, **Plant**, **Tools**, and **Me**.

| Area | Overview |
|---|---|
| **Today** | Scheduled installations for the day. A glance panel displays current date and job counts, prioritizing the nearest installation with direct turn-by-turn navigation. Cards provide ticket numbers, subscriber addresses, plant IDs, service plans, and quick-action buttons (*Navigate*, *Call*, *SMS*, *Copy Contact*). Map view and instant search are accessible via top action icons. |
| **Done Jobs** | Filterable archive of completed and activated jobs assigned to the signed-in technician, featuring search, date range selectors, and area filters. |
| **Job Detail** | Comprehensive work order summary including subscriber details, hardware assignments, optical signal thresholds, bill of materials, attached photo proof galleries, and the completion report workflow. |
| **Completion Report** | Multi-step validation: optical power measurements evaluated against GPON tolerances, equipment barcode scanning (ONT serials, router models), NAP port allocations, photo captures with geotags, site remarks, and subscriber digital sign-off. |
| **Repairs** | Service order management for trouble tickets (loss of service, high optical attenuation, relocations, equipment pullouts). Provides hardware swap logs, material consumption counters, photo proof captures, and customer sign-offs with offline persistence. |
| **Plant** | LCP cabinets and NAP distribution boxes visualized in interactive lists or on a map with clustering. Includes place search, satellite and street layers, and client-side map tile caching for offline map viewing. |
| **Tools** | Field utility toolkit featuring standard fiber color coding (TIA-598-C), optical link budget calculators, drop cable and bill-of-materials estimators, network diagnostics, and field troubleshooting guides. |
| **Me** | Technician account details, dark mode toggle, GPON optical attenuation reference standards, sync diagnostic logs, and connection status. |
| **Offline Sync** | Edits are persisted locally first. Offline mutations are queued and automatically synchronized with the backend once connectivity resumes, maintaining operational continuity regardless of cellular coverage. |

## Architecture

The project is organized by feature with a decoupled core layer:

```
lib/
├── core/
│   ├── constants/       App constants, optical thresholds, and configuration keys
│   ├── database/        Local SQLite schema, DAOs, and persistence layer
│   ├── network/         HTTP client, interceptors, and error handling
│   ├── services/        Camera capture, EXIF metadata, GPS location, file storage
│   ├── storage/         Secure hardware-backed storage (Keychain / Keystore)
│   ├── theme/           Calm Utility design system: typography tokens and colors
│   ├── utils/           Display helpers and data conversion utilities
│   └── widgets/         Re-usable UI components (status rail, action bars, scanners)
└── features/
    ├── auth/            Authentication, technician profile, and session management
    ├── catalogs/        Service plans, hardware models, and plant catalogs
    ├── diagnostics/     Synchronization diagnostics and error reporting
    ├── jobs/            Installation work orders: models, repositories, views
    ├── lcp_nap/         LCP and NAP plant mapping, clustering, and tile caching
    ├── reports/         Job completion reporting and customer sign-off flows
    ├── service_orders/  Repair trouble tickets and swap/pullout forms
    ├── settings/        Technician profile and app preferences
    ├── shell/           Primary navigation shell and bottom tabs
    ├── splash/          Launch screen and environment initialization
    └── toolkit/         Field engineering tools and fiber references
```

### Core Technologies

| Concern | Solution |
|---|---|
| **Data Sync** | [`powersync`](https://pub.dev/packages/powersync) for bidirectional offline-first data replication and offline SQLite caching. |
| **State Management** | [`signals_flutter`](https://pub.dev/packages/signals_flutter) for reactive, fine-grained UI updates driven directly by local data streams. |
| **Database** | SQLite via [`drift`](https://pub.dev/packages/drift) & PowerSync engine for type-safe local storage. |
| **Networking** | [`dio`](https://pub.dev/packages/dio) with TLS certificate pinning and automated token refresh. |
| **Mapping** | [`flutter_map`](https://pub.dev/packages/flutter_map) with offline tile caching. |
| **Barcode Scanning** | [`mobile_scanner`](https://pub.dev/packages/mobile_scanner) for serial and QR code capture. |
| **Secure Storage** | [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage) for secure credential and token persistence. |
| **Typography** | Barlow, Barlow Semi Condensed, and JetBrains Mono bundled locally under the SIL Open Font License. |

## Getting Started

### Prerequisites

- Flutter SDK 3.47 or newer ([flutter.dev](https://flutter.dev))
- Android Studio with Android SDK (API 34+) or Xcode 16+ for iOS development
- Accepted Android SDK licenses (`flutter doctor --android-licenses`)

### Installation & Local Run

```bash
# Clone the repository
git clone https://github.com/bluegene37/swithfiber_tech_ps.git
cd swithfiber_tech_ps

# Install dependencies
flutter pub get

# Generate database and serialization code (if modifying schema or models)
dart run build_runner build --delete-conflicting-outputs

# Launch the app
flutter run
```

### Configuration

Service endpoints and application configurations are defined in `lib/core/constants/app_constants.dart` and can be configured per environment or modified at runtime within the technician settings screen. 

No secret credentials, API keys, or private certificates are stored in the repository. Environment-specific secrets and release keystores are injected via CI/CD pipeline secrets and gitignored configuration files (`key.properties`).

## Testing

The project maintains comprehensive test coverage across unit logic, widget rendering, layout scaling, and accessibility contracts:

```bash
# Run static analysis
flutter analyze --fatal-infos

# Check code formatting
dart format --set-exit-if-changed -o none lib test

# Execute test suite
flutter test
```

## Release Build

See [`docs/RELEASE.md`](docs/RELEASE.md) for complete distribution instructions. Build commands:

```bash
# Android App Bundle (Play Store)
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols/android

# Android APK (Direct Deployment)
flutter build apk --release --obfuscate --split-debug-info=build/symbols/android

# iOS IPA
flutter build ipa --release --obfuscate --split-debug-info=build/symbols/ios
```

## License

Proprietary. Copyright © Switch Fiber. All rights reserved.
