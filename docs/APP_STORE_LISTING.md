<!-- Gene - Nov 05, 2026: Created comprehensive App Store listing pack, metadata, privacy disclosures, screenshot guidelines, and Apple Review notes for iOS production release. -->
# Apple App Store Production Listing Pack & Review Guide

This guide provides the complete submission package, store copy, privacy disclosures, and Apple App Review reviewer notes for releasing **Switch Fiber Tech** (`dev.genexis.swithfibertech`) on the Apple App Store.

---

## 1. App Store Connect Metadata

### General App Information
- **App Name**: `SF Tech` *(Matches iOS bundle display name)*
- **Primary Category**: `Business`
- **Secondary Category**: `Utilities`
- **Age Rating**: `4+` *(No age-restricted content, simulated gambling, or unmoderated UGC)*
- **Bundle ID**: `dev.genexis.swithfibertech`
- **SKU**: `SWITHFIBER-TECH-IOS`
- **Copyright**: `© 2026 Switch Fiber. All rights reserved.`

### Version Information (Version 1.0.3)
- **Version String**: `1.0.3`
- **Subtitle** *(Max 30 characters)*:
  ```text
  Field Technician Network Tools
  ```

- **Promotional Text** *(Max 170 characters)*:
  ```text
  Official Switch Fiber field operations app for technicians to manage job orders, record optical readings, scan serials, navigate to NAP poles, and submit reports.
  ```

- **Keywords** *(Max 100 characters, comma-separated)*:
  ```text
  switchfiber,fiber,technician,telecom,nap,ont,gpon,job order,optical,field service,dispatch
  ```

- **Support URL**: `https://switchfiber.ph`
- **Marketing URL**: `https://switchfiber.ph`
- **Privacy Policy URL**: `https://switchfiber.ph/privacy`

---

### App Store Description

```text
SF Tech is the official distributed field operations application engineered specifically for Switch Fiber network technicians, contractors, and field support crews. 

Designed for high-reliability in both connected and offline field environments, SF Tech equips technicians with the mission-critical tools needed to execute subscriber installations, service repairs, and fiber plant maintenance.

KEY FEATURES:

• WORK ORDER & DISPATCH QUEUE:
Access assigned daily work orders and service tickets with an optimized Today glance view. View subscriber details, service tiers, scheduled windows, and contact lines with one-tap native calling and messaging.

• FIBER PLANT & NAP MAPS:
Navigate directly to assigned NAP (Network Access Point) poles, cabinets, and LCP splitters using integrated offline map tiles and external routing via Apple Maps, Google Maps, or Waze.

• 5-STEP INSTALLATION & COMPLETION REPORTS:
Streamline on-site handoffs with structured validation:
1. Real-time GPON optical power readings (dBm) with visual threshold validation.
2. Hardware serial verification with integrated high-speed barcode/QR scanner.
3. Drop cable footage and dynamic materials-used accounting.
4. Geo-tagged photo documentation (NAP box, ONT power, installation setup, speed test, house front).
5. Digital subscriber signature capture.

• HARDWARE REPAIRS & PULLOUTS:
Diagnose trouble tickets on-site with hardware swap tracking, replacement router provisioning, pullout notes, and technician diagnostics.

• OFFLINE-FIRST CAPABILITY:
Operate seamlessly in remote fiber corridors with zero cellular connectivity. Local changes queue securely in an offline database and synchronize automatically once connectivity is restored.

• TECHNICIAN TOOLKIT:
Built-in utilities including optical loss budget calculator, drop cable length estimator, 12-color fiber color-code chart, and live ping/latency diagnostics.

NOTE: SF Tech is an enterprise field tool intended for authorized Switch Fiber technicians and contracted partners. Active credentials provisioned by Switch Fiber IT Dispatch are required to access network features.
```

---

### What's New in This Version (Release Notes)

```text
• Official production release for Apple iOS devices.
• Offline-first synchronization powered by PowerSync engine.
• 5-step standardized work order completion reports with camera proofs and signature sign-off.
• High-performance barcode and QR scanner for router serial tracking.
• Interactive NAP pole and LCP plant cluster map with turn-by-turn navigation.
• Optical power gauge with GPON threshold indicator.
• Service order and trouble-ticket repair workflows.
• Built-in technician toolkit and diagnostic utilities.
```

---

## 2. App Store Review Information (Guideline 2.1 Compliance)

> [!IMPORTANT]
> Apple App Review testers require valid credentials and pre-loaded test data to evaluate the application. Provide the exact text below in the **App Review Information > Notes** field in App Store Connect.

### Reviewer Notes Template (Paste into App Store Connect)

```text
Dear Apple App Review Team,

Switch Fiber Tech ("SF Tech") is an enterprise field-service application used by field technicians and installation contractors working for Switch Fiber, a telecommunications and broadband provider in the Philippines.

1. DEMO CREDENTIALS:
- Username: <ENTER_DEMO_USERNAME_HERE> (e.g. apple_reviewer)
- Password: <ENTER_DEMO_PASSWORD_HERE>

2. ENTERPRISE ACCOUNT MODEL (Guideline 4.8 / 3.1.1):
Accounts are enterprise-only and provisioned directly by Switch Fiber IT Dispatch. Technicians do not register for public accounts in the app; each user is an employee or contracted technician whose account is created by dispatch administrators.

3. PRE-POPULATED TEST DATA:
The demo account has been seeded with 2 active "Scheduled" work orders located near the service area:
- Ticket #JO-TEST-101: Standard Fiber Installation
- Ticket #JO-TEST-102: Service Order / Trouble Ticket

Reviewers can test the full technician lifecycle:
- Tap on Ticket #JO-TEST-101 to view customer info, address, and assigned NAP pole.
- Tap "Navigate" to test external map launching.
- Tap "Create Report" to step through the 5-step completion flow:
  * Optical Power Reading (enter e.g. -18.5 dBm)
  * Hardware & Port selection (enter router model & serial)
  * Photo proof captures (uses camera or photo library)
  * Digital signature capture
  * Submit report

4. APP TRANSPORT SECURITY (ATS) SCOPING:
The main REST API operates over encrypted TLS at https://admin.switchfiber.ph. The app connects to a dedicated, self-hosted PowerSync real-time sync daemon on internal IP 103.249.198.50:8080. Per ATS guidelines, this host is explicitly isolated in Info.plist under NSExceptionDomains (NSExceptionAllowsInsecureHTTPLoads = true), with global arbitrary loads disabled (NSAllowsArbitraryLoads = false).

5. CONTACT INFORMATION:
If you need any assistance, live server verification, or credential resets during review, please contact:
- Technical Lead / Admin: dev-support@switchfiber.ph
- Phone: +63 917 000 0000

Thank you for your time and review!
```

---

## 3. App Privacy "Nutrition Labels" Responses

When completing the **App Privacy** questionnaire in App Store Connect:

### 1. Does the app collect data?
- Select **Yes, we collect data from this app**.

### 2. Data Types Collected & Declarations:

| Data Type | Purpose | Linked to User? | Used for Tracking? |
|---|---|---|---|
| **Location** *(Precise Location)* | **App Functionality**: Distance calculation to jobs, prioritizing nearest work order, and geo-stamping photo proofs on completion reports. | **Yes** *(Linked to technician account)* | **No** |
| **User Content** *(Photos or Videos)* | **App Functionality**: Capturing proof of installation photos (NAP box reading, ONT setup, house front, port label). | **Yes** *(Associated with job order report)* | **No** |
| **Identifiers** *(User ID)* | **App Functionality**: Authenticating technician sessions and attributing completed work orders to the technician. | **Yes** *(Technician username/ID)* | **No** |
| **Diagnostics** *(Crash Data & Error Logs)* | **App Functionality / Analytics**: Logging synchronization failures and app errors to support field stability. | **No** *(Not linked to identity)* | **No** |

### 3. Tracking Declaration:
- **Do you use data to track the user across apps and websites owned by other companies?**: **No**.

---

## 4. App Store Screenshot Specifications

Apple requires screenshots for iPhone display sizes. Per user policy, all captured screenshots should be mirrored to:
`~/Documents/personal_projects/screenshots/swithfiber_tech_ps/`

### Required Device Displays:
1. **6.9" Display** (iPhone 16 Pro Max / 15 Pro Max):
   - Resolution: `1320 x 2868 pixels` (portrait) or `1290 x 2796 pixels`
2. **6.5" Display** (iPhone 11 Pro Max / XS Max / XR):
   - Resolution: `1242 x 2688 pixels` (portrait)
3. *(Optional / Recommended)* **5.5" Display** (iPhone 8 Plus):
   - Resolution: `1242 x 2208 pixels` (portrait)

### 5 Recommended Showcase Screens:
1. **`01_today_dispatch.png`**: Today Home dashboard showing assigned job orders, date glance, and the highlighted nearest job with *Navigate* action.
2. **`02_job_detail.png`**: Work order detail screen showing subscriber metadata, address, contact buttons, and assigned NAP pole.
3. **`03_plant_map.png`**: Clustered plant map displaying nearby NAP poles, fiber routes, and satellite layer.
4. **`04_completion_report.png`**: 5-step completion report showing optical power gauge, port selection tiles, and photo proof cards.
5. **`05_barcode_scanner.png`**: In-app serial number scanner view with optical viewfinder and torch toggle.

---

## 5. Production Release Checklist & Runbook

- [x] **ATS Scoped**: `ios/Runner/Info.plist` has `NSAllowsArbitraryLoads: false` with `103.249.198.50` in `NSExceptionDomains`.
- [x] **CI/CD Hardened**: `.github/workflows/release.yml` supports both `BUILD_*` and `APPLE_*` secret aliases.
- [x] **Static Analysis**: `flutter analyze --fatal-infos` passes cleanly.
- [x] **Unit & Widget Tests**: All 547 unit/widget tests pass.
- [ ] **Demo Account Provisioned**: IT Dispatch has created the demo technician account with 2 test job orders on `https://admin.switchfiber.ph`.
- [ ] **App Store Connect App Record**: App created in App Store Connect with bundle identifier `dev.genexis.swithfibertech`.
- [ ] **Metadata & Screenshots Uploaded**: Descriptions, keywords, URLs, and 6.9"/6.5" screenshots entered.
- [ ] **CI Build Triggered**: Run `./scripts/deploy.sh ios` to build and upload the signed IPA.
- [ ] **Submit for Review**: Select the uploaded build under Version 1.0.3 and click **Submit for Review**.
