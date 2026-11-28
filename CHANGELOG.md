# Changelog

All notable changes to Switch Fiber Tech are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **PowerSync v11 & RS256 Gateway Integration (Dual-Mode).** Connects to self-hosted PowerSync streaming and authenticated Gateway uploads when `POWERSYNC_ENDPOINT` and `POWERSYNC_GATEWAY_URL` are supplied via `--dart-define`, while remaining in local-only REST fallback mode when unset.
- **Job & Service Order Work Timing Controls.** Start, Finish/Stop, and restartable work timing with pre-Start editing lock, single-active-order enforcement, and a local technician timing history log.
- **Service Order Visual Parity & 4-Slot Photo Gallery.** `GetServiceOrderImage` gallery viewer, multipart photo uploads across all repair slots, and structured repair completion reporting.
- **PowerSync v12 & v13 Schema, On-Demand History & Hardened Gateway.** Canonical `item_name_1..10` / `item_quantity_1..10` columns with v13 MSSQL-aligned types, offline SQL-joinable local lookup tables synced via `GET /api/sync/lookups` (`ETag`), on-demand history streams, coalesced multipart PATCH uploads, conflict & `403 NOT_ASSIGNED` handling, `429` login rate-limit backoff, photo compression, and periodic/one-off background sync (`workmanager`).

### Changed
- **Service Order Timing & Queue Grouping.** Standardized Service Order end-timing button label from *Stop* to *Finish* for parity with Job Orders, and grouped *Rescheduled* Job Orders and Service Orders under a bottom *Rescheduled* section.

### Fixed
- **Fresh-Install Sync Deadlock & Work Timing Reliability.** Cleared stale keychain credentials on fresh installs so first-launch sync works without re-login, hardened single-active-order start locking across hidden/rescheduled jobs, and added synced start/end timestamp fallback in order timing history.
- **Android AGP 9 WorkManager Build.** Upgraded `workmanager` to `^0.10.10` (`workmanager_android 0.10.9`) to fix Kotlin compilation under AGP 9 with `android.builtInKotlin=false` and improve Android 16 background isolate reliability.
- **Terminal Ghost Start Locks & Active Order Banner.** Tightened `ServiceOrderDto.isOpen` and active Repairs filtering so completed/cancelled history rows cannot silently hide `Start` buttons, excluded site-exception Job Orders (`Rescheduled`/`Failed`) from holding active locks, and added a persistent active-order banner with one-tap *Finish* across Job Orders and Service Orders.
- **iOS TestFlight `BGTaskScheduler` Launch Crash.** Pre-registered `dev.genexis.swithfibertech.backgroundSync` and `WorkmanagerPlugin.setPluginRegistrantCallback` during `AppDelegate.didFinishLaunchingWithOptions` (and set `initialDelay: 15m` in `BackgroundSyncService`) so `workmanager_apple` never registers a launch handler after app launch finishes.

## [1.0.3] - 2026-11-07

### Added
- **LCP NAP Create, Edit & Calm Utility UX Polish.** Bottom floating *+ Add* pill on Plant lists, searchable LCP cabinet picker sheet, create new LCP NAP site / edit site details support, and three standalone Calm Utility photo proof cards on NAP detail screens.
- **High-Resolution Google Street & Hybrid Map Tiles (Zoom 22).** Upgraded Plant and Job map layers to crisp Google street and satellite hybrid tiles supporting zoom up to level 22 for exact pole-level GPS pinning.
- **LCP NAP Image & GPS Auto-Sync (Online & Offline Queue).** Offline NAP site photo uploads, single-photo `0`-byte deletions, and GPS coordinate updates now queue locally (`is_synced = 0`) and automatically push to `PUT /api/LCPNapLocations/{id}` on network reconnect, app resume, or background sync; remote photo and GPS updates by other technicians automatically invalidate in-memory cache and refresh live without restarting the app.
- **Job Order Photo Proofs & Multipart Upload.** View remote site photos and upload installation photo proofs (NAP reading, ONT reading, installation setup, speed test, house front, signed contract, port label) via multipart API.
- **LCP NAP Location Mapping.** Current GPS lock, interactive map pin picker sheet, and coordinate update API integration.
- **LCP NAP Photo Capture & Upload.** Site enclosure and reading photo proofs with camera capture, photo clearance, and multipart upload.
- **Apple App Store Production Package.** Full App Store Connect metadata pack, reviewer credentials, support URLs, and Guideline 2.1 compliance guide.
- **iOS TestFlight Automated CI/CD.** Ephemeral keychain, automated certificate and profile signing, and TestFlight deployment via `release.yml` and `./scripts/deploy.sh`.
- **Dynamic Materials Picker.** Searchable inventory materials selector and usage counter on job order reports.
- **Repairs tab.** Service orders (trouble tickets) are pulled from the API,
  persisted in their own Drift table, and completed offline: hardware swap or
  pullout, materials consumed, three photo proofs plus house front, and a
  subscriber sign-off. A dedicated sync worker replays repair edits.
- **Today home.** The Today tab replaces the scheduled list: a glance panel
  with the date and job count, the nearest job lifted with one red
  *Navigate* verb, status rail rows, and done jobs behind a toggle. No app
  bar.
- **Uniform job cards** with *Navigate*, *Call* and *SMS* on every card, a
  ticket (id) line, icon-led address, plan, phone and email lines, and a
  *Copy contact* button. Phone and SMS open the native dialler and messaging
  app.
- **Completion report as five numbered steps**: optical reading, hardware and
  port with NAP port tiles, photo proofs, remarks, and customer sign-off.
  *Save* names exactly what is still missing.
- **Serial barcode scanner** on the hardware step and the repair form, tuned
  for Code 128, Code 39, QR, Data Matrix and EAN serial labels, with a torch
  toggle.
- **Materials used (bill of materials).** Drop cable, SC/APC fast connectors
  and S-clamps are captured on the report, shown on the job detail, and
  round-tripped through the job order's item name and quantity fields.
- **Map view for jobs** with a list / map toggle and navigation to the
  nearest NAP pole.
- **NAP catalog selection and map place search** on the plant screens.
- **Catalogs.** Plans, router models, NAPs and ports are fetched from the API,
  with bundled fallback plans for offline first launch.
- **Sync error log** in the Me tab: every refused push is stored with its
  status, the server's message and the exact request body so it can be
  handed to the backend team.
- **Force Full Sync** in the Me tab, gated behind the technician's password:
  pushes what is pending, then replaces the local cache with the server's
  copy.
- **Subscriber disconnections tool**: look up a RADIUS subscriber session and
  connect or disconnect it.
- **GPS status badge** on photo capture, with EXIF GPS tags written into each
  JPEG and no fallback coordinate spoofing.
- **Photo file store.** Photo proofs and signatures are saved as files in the
  app documents directory instead of inside SQLite rows, which kept large
  reports under Android's cursor window limit.
- Phone-width layout regression tests at 100 %, 130 % and 200 % text scale,
  and a guard test that keeps raw font sizes and undersized tap targets out
  of widgets.

### Changed
- **Calm Utility design system.** Bundled Barlow, Barlow Semi Condensed and
  JetBrains Mono; warm paper and ink colour tokens; hairline surfaces with no
  shadows; one red action per screen; status as a 4 px rail plus one word;
  native platform transitions. Tabs renamed to Today, Repairs, Plant, Tools
  and Me.
- Job detail rebuilt read-first: header with *Navigate* and *Call*, a
  monospace plant line, one sticky verb, and history last.
- Plant screen shows cabinets as flat rows with a text-only *List | Map*
  switch and plain tool rows.
- Done-jobs header compacted to one counts line and filter buttons that open
  sheets; the *This month* range was removed.
- Job pulls are scoped to the technician's email through the
  `status-assigned` endpoint and nothing is pulled until the email is known.
- A finished job now goes straight from Scheduled to Completed when its
  report is submitted; Activated is treated as finished as well.
- Directions open Google Maps or the phone's default map app instead of the
  browser.
- Job order updates replay the full record with only the technician's edits
  applied, matching the API's required-field list, and send placeholder
  image URLs until the backend accepts uploads (its image columns are capped
  at 255 characters).
- All text routes through the theme's text roles with a 13 px floor; icons
  meet minimum sizes and tap targets are at least 48 dp.
- Removed all bundled dummy data; every screen reads from the live API or the
  local cache.

### Fixed
- HTTP 400 that blocked every job completion.
- Version 9 database migration crashing phones upgrading from below
  version 8.
- Repairs detail crash on a blank router model; its header rows now wrap.
- Other technicians' jobs appearing on a phone after sign-in, caused by an
  unscoped pull that outlived the scoped one.
- Signature pad losing strokes to the page scroll.
- Overflows at large text sizes in the LCP/NAP toolbar, NAP detail header,
  plant map overlays, service order cards, toolkit screens, and header and
  badge rows.
- Site map preview stealing the page scroll on NAP detail.
- Image memory use on the detail gallery, by bounding decoded image width.

## [1.0.0] - 2026-09-02

First production release for Switch Fiber field technicians.

### Added
- Technician sign-in against the Switch Fiber API with a persisted session.
- Scheduled work-order queue with search; tapping a ticket opens its details.
- Two-stage workflow: a job is Scheduled, then marked Activated (with
  confirmation) from its details or by submitting a completion report.
  Activation records the technician's email and install date.
- My Job History: the technician's activated jobs, view-only, with date range,
  area and text filters and weekly / monthly counts.
- Work-order detail screen: workflow stepper, subscriber and location details,
  plant and hardware allocation, optical power reading, on-site records, and
  external navigation to Google Maps, Waze, or Apple Maps.
- On-site completion report with optical power gauge, ONT details, seven
  photo proofs captured from the camera or gallery, and a drawn subscriber
  signature. Photos are compressed on the phone and shown in a zoomable
  gallery on the detail screen.
- LCP/NAP plant records with a clustered map view, satellite layer, cabinet
  grouping, filters, and offline tile cache.
- Technician toolkit: optical budget calculator, drop cable estimator, fiber
  color code reference, network diagnostic pings, and a field troubleshooting
  guide.
- Offline-first storage in SQLite (Drift) with a background sync queue for
  edits made without a connection.
- Certificate-pinned HTTPS client, configurable API base URL, dark mode.
- CI workflow (analyze, format, test, debug APK) and a tag-driven release
  workflow that builds a signed App Bundle and APK.

### Security
- The API server's self-signed certificate is pinned by SHA-256 fingerprint.
- Session data is stored in the platform keychain / keystore; sensitive profile
  fields returned by the API are never persisted.

[Unreleased]: https://github.com/bluegene37/switchfiber_tech/compare/v1.0.3...HEAD
[1.0.3]: https://github.com/bluegene37/switchfiber_tech/compare/v1.0.0...v1.0.3
[1.0.0]: https://github.com/bluegene37/switchfiber_tech/commits/v1.0.0
