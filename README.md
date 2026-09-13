<p align="center">
  <img src="assets/images/logo.png" alt="Switch Fiber" width="96">
</p>

<h1 align="center">Switch Fiber Tech</h1>

<p align="center">
  Field operations app for Switch Fiber installation and repair technicians.<br>
  Offline-first, built with Flutter for Android and iOS.
</p>

<p align="center">
  <a href="https://github.com/bluegene37/switchfiber_tech/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/bluegene37/switchfiber_tech/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Flutter 3.47" src="https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white">
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Android%20%7C%20iOS-3DDC84">
  <img alt="Version" src="https://img.shields.io/badge/version-1.0.0-E02424">
</p>

---

Switch Fiber Tech puts a technician's whole day on one glance: the next
installation with one red button, the repair tickets assigned to them, the
LCP/NAP plant on a map, and the calculators they reach for on a pole. Every
record is cached in SQLite, so the app keeps working in a basement with no
signal and syncs when the connection returns.

## Features

The app has five tabs: **Today**, **Repairs**, **Plant**, **Tools** and **Me**.

| Area | What it does |
|---|---|
| **Today** | The day's scheduled installations. A glance panel with the date and job count, the nearest job lifted to the top with one *Navigate* verb, then plain rows. Each card carries the ticket, address, plant ids, plan and contact with *Navigate*, *Call*, *SMS* and *Copy contact*. Search and a map view sit behind icons. |
| **Done jobs** | Behind a toggle on Today: every activated or completed job assigned to the signed-in technician, view-only, with search, a counts line, and status, date range and area filter sheets. |
| **Job detail** | Read-first header with *Navigate* and *Call*, the plant line in monospace, subscriber and location details, hardware allocation, optical reading, materials used, a zoomable gallery of attached photos, and one sticky action: fill the completion report. |
| **Completion report** | Five numbered steps: optical reading against GPON thresholds, hardware and port (ONT model, serial with a barcode scanner, NAP port tiles), photo proofs, remarks, and a drawn subscriber sign-off. Materials consumed on site (drop cable, fast connectors, S-clamps) are recorded as a bill of materials. *Save* names whatever is still missing. Submitting completes the job. |
| **Repairs** | Service orders (trouble tickets: no connection, high loss, relocation, pullout) with concern, priority and visit status. The detail screen has *Call client* and *Directions*, a hardware swap or pullout form, materials, three photo proofs plus house front, and subscriber sign-off. Works offline like jobs. |
| **Plant** | LCP cabinets and NAP boxes as flat rows or on a map. Cabinet grouping, filters, place search, street and satellite layers, and a tile cache so viewed areas keep rendering without a signal. |
| **Tools** | Fiber color code (TIA-598-C), optical link budget calculator, drop cable and materials estimator, network and DNS diagnostics, a field troubleshooting guide, and subscriber disconnections (RADIUS session connect and disconnect). |
| **Me** | Technician profile, dark mode, GPON optical power standards, the sync error log, API base URL with a connectivity test, a password-gated *Force Full Sync*, and sign out. |
| **Offline sync** | Edits are written to SQLite first with a pending flag. Background workers replay job and service order edits to the API, show pending counts across the app, and log every refused push with the exact request so it can be handed to the backend team. |

## Architecture

The app is organised by feature, with a thin core layer underneath.

```
lib/
├── core/
│   ├── constants/       App-wide constants, storage keys, optical thresholds
│   ├── database/        Drift (SQLite) schema, migrations, and DAOs
│   ├── network/         Dio client with certificate pinning and 401 handling
│   ├── services/        Camera capture, EXIF, GPS, photo files, map navigation
│   ├── storage/         Secure storage (Keychain / Keystore)
│   ├── theme/           Calm Utility theme: bundled fonts, paper and ink tokens
│   ├── utils/           Data URL helpers, server display
│   └── widgets/         Status rail row, stamp, sticky action bar, scanner sheet
└── features/
    ├── auth/            Login, session restore, technician profile
    ├── catalogs/        Plans, router models, NAPs and ports from the API
    ├── diagnostics/     Sync error log, RADIUS subscriber sessions
    ├── jobs/            Job orders: models, repository, sync worker, Today home
    ├── lcp_nap/         Plant records, map tiles, clustering
    ├── reports/         Completion report
    ├── service_orders/  Repairs: models, sync worker, screens
    ├── settings/        Me tab and preferences
    ├── shell/           Bottom tabs and drawer
    ├── splash/          Launch screen
    └── toolkit/         Field calculators and references
```

Each feature follows the same shape: `models/` (DTOs), `repositories/` or
`services/` (API plus local cache), `signals/` (reactive state), `screens/`
and `widgets/`.

| Concern | Choice |
|---|---|
| State | [`signals_flutter`](https://pub.dev/packages/signals_flutter): Drift streams are piped into signals, screens rebuild from computed values. |
| Storage | [`drift`](https://pub.dev/packages/drift) over SQLite, schema version 9. Tables: job orders, LCP/NAP locations, service orders, sync queue, sync error log. Job orders keep the untouched API record in a `rawJson` column so updates round-trip every field the app does not model. |
| Networking | [`dio`](https://pub.dev/packages/dio) with the API server's self-signed certificate pinned by SHA-256 fingerprint. |
| Maps | [`flutter_map`](https://pub.dev/packages/flutter_map) on Esri World Street Map and World Imagery tiles, cached on disk through Drift. |
| Photos | [`image_picker`](https://pub.dev/packages/image_picker) plus [`geolocator`](https://pub.dev/packages/geolocator): captures are compressed to 1600 px at 80 % quality, tagged with GPS EXIF, and stored as files in the app documents directory rather than inside SQLite rows. |
| Barcodes | [`mobile_scanner`](https://pub.dev/packages/mobile_scanner) reads ONT and router serials. |
| Secrets | [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage) for the session and base URL. |
| Type | Barlow, Barlow Semi Condensed and JetBrains Mono, bundled under the SIL Open Font License so nothing is fetched at runtime. |

### Data flow

1. On sign-in the shell fetches the technician's profile, then pulls their
   job orders through `GET /api/JobOrders/status-assigned` scoped to their
   email, across Scheduled, Activated and Completed. Nothing is pulled until
   the email is known. Service orders come from `GET /api/ServiceOrders`,
   plant records from `GET /api/LCPNapLocations`, and plans, router models,
   NAPs and ports from their catalog endpoints. Everything is upserted into
   SQLite, and synced rows the server no longer returns are dropped.
2. Screens watch Drift streams through signals, so any local write repaints
   the UI immediately.
3. Technician edits (completion reports, repair completions) are written
   locally with `isSynced = false`, then a sync worker replays them with
   `PUT /api/JobOrders/{id}` or `PUT /api/ServiceOrders/{id}`. On success the
   local row is replaced by the server's own copy of the record. If the server
   answers 404 the job was deleted by the office and the local row is dropped.
   Any other refusal is written to the sync error log with the status, the
   server's message and the request body, and retried on the next cycle. A
   refresh never overwrites a row whose edit is still pending.

## Getting started

### Prerequisites

- Flutter 3.47 or newer on the stable channel (`flutter --version`)
- Android Studio with an SDK, or Xcode 16+ for iOS
- Android SDK licenses accepted: `flutter doctor --android-licenses`

### Run

```bash
git clone git@github.com:bluegene37/switchfiber_tech.git
cd switchfiber_tech
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

The generated Drift files (`*.g.dart`) are committed, so the `build_runner`
step is only needed after changing anything under `lib/core/database`. CI
fails if they are stale.

### Configuration

There are no build-time secrets. The API base URL defaults to
`AppConstants.defaultBaseUrl` in
[`lib/core/constants/app_constants.dart`](lib/core/constants/app_constants.dart)
and can be overridden at runtime from *Me*. The same file holds the pinned
certificate fingerprint; if the server certificate is reissued, update
`pinnedApiCertSha256` and ship a new build, otherwise every request fails.

The live API differs from its published schema in places. Each divergence the
app has to work around is recorded in a code comment next to the workaround,
for example in the job order model and the job repository.

## Testing

```bash
flutter analyze --fatal-infos
dart format --set-exit-if-changed -o none lib test
flutter test
```

Tests live in [`test/`](test/) and cover the status model, the PUT payload
round-trip against the API's required-field list, Drift-to-signals data flow,
schema migrations, the done-jobs filters, map clustering, the serial scanner,
the report steps, and the main screens as widget tests on an in-memory
database. Layout tests assert no overflow at 100 %, 130 % and 200 % text
scale on a phone width, and a guard test keeps raw font sizes out of widgets.

## Release

See [`docs/RELEASE.md`](docs/RELEASE.md) for signing setup, the
pre-submission checklist, and the tag-driven release workflow. In short:

```bash
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols/android
flutter build ipa --release --obfuscate --split-debug-info=build/symbols/ios
```

Pushing a `v*` tag runs [`release.yml`](.github/workflows/release.yml), which
builds a signed App Bundle and APK and attaches them to a GitHub Release.

## Project conventions

- A job arrives *Scheduled* (the office's `Applied` / `Confirmed` count as
  Scheduled) and the technician finishes it by submitting the completion
  report, which marks it *Completed*. *Activated* is an older finished state
  and is treated the same way. Finished jobs leave Today's queue and are
  view-only under done jobs.
- `onsiteStatus` values *Failed* and *Reschedule* are surfaced as an extra
  badge so problem visits stay visible.
- Job orders never send a partial update: the original record is replayed
  with only the technician's edits applied.
- Photos and the signature stay on the phone as files. The API's image
  columns are too short for inline images, so the sync worker sends
  placeholder URLs until the backend accepts uploads. Flip
  `JobOrderDto.serverAcceptsInlineImages` when it does.
- Sensitive profile fields returned by the API are deliberately not modelled
  and never reach storage.
- Design follows a "Calm Utility" system: warm paper and ink, one red action
  per screen, status as a 4 px rail plus one word, no shadows, no pills, a
  13 px text floor, and every text style routed through the theme roles in
  `lib/core/theme/app_theme.dart` rather than literal font sizes.

## Changelog

See [`CHANGELOG.md`](CHANGELOG.md).

## License

Proprietary. Copyright © Switch Fiber. All rights reserved.
