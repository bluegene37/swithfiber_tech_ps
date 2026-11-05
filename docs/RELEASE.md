# Release guide

<!-- Gene - Oct 08, 2026: Updated release overview to reflect automated TestFlight CI deployment and local deploy script alongside Google Play releases.
How to cut a store-ready build of Switch Fiber Tech. The CI pipeline
(`.github/workflows/ci.yml`) gates every pull request; the release pipeline
(`.github/workflows/release.yml`) builds signed Android artifacts when a `v*`
tag is pushed. iOS is built and uploaded from a Mac with Xcode signing.
-->
How to cut a store-ready build of Switch Fiber Tech. The CI pipeline
(`.github/workflows/ci.yml`) gates every pull request; the release pipeline
(`.github/workflows/release.yml`) builds signed Android artifacts (deployed to Google Play)
and signed iOS IPAs (deployed directly to Apple TestFlight) when a `v*` tag is pushed or
when triggered via workflow dispatch. Releases can also be built and deployed locally using
`./scripts/deploy_testflight.sh` or standard Flutter build commands.


## 1. One-time setup

### Android upload keystore

```bash
keytool -genkey -v -keystore ~/switchfiber-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Copy `android/key.properties.example` to `android/key.properties` and fill in
the path and passwords. The file is gitignored. **Back the keystore up
somewhere durable**: losing it means the app can never be updated on Google
Play under this application ID.

For CI, add these repository secrets:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -i ~/switchfiber-upload.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | key password |
| `PLAY_CONFIG_JSON` | Google Play Developer API Service Account JSON key (see below) |

### Google Play Console API access & service account

To allow GitHub Actions to deploy to the **Internal Testing** track automatically:

1. **Pre-requisite (Initial manual upload)**:
   Google Play Console requires the first `.aab` or `.apk` to be uploaded manually to the track once so the package name (`dev.genexis.swithfibertech`) and signing key are registered. *(Already completed!)*

2. **Google Cloud Console: Enable API & Create Service Account**:
   - Open **[Google Cloud Console](https://console.cloud.google.com/)**.
   - Create a project or select your existing project.
   - Go to **APIs & Services** > **Library**, search for **Google Play Android Developer API**, and click **Enable**.
   - Navigate to **IAM & Admin** > **Service Accounts**.
   - Click **+ Create Service Account**:
     - Name: `play-actions-deployer`
     - Click **Create and Continue**, then click **Done**.
   - Copy the generated email address of the service account (e.g. `play-actions-deployer@<project-id>.iam.gserviceaccount.com`).
   - Click the service account, go to the **Keys** tab, click **Add Key** > **Create new key**, select **JSON**, and click **Create** (this downloads your `.json` file).

3. **Google Play Console: Invite Service Account**:
   - Open **[Google Play Console](https://play.google.com/console)**.
   - In the left sidebar, click **Users & permissions**.
   - Click **Invite new users**.
   - In **Email address**, paste the service account email from Step 2.
   - Under **App permissions**, click **Add app** and select **`dev.genexis.swithfibertech`**.
   - Under **Releases**, ensure these permissions are checked:
     - ✅ *Create, edit, and roll back releases on internal testing tracks*
     - ✅ *Manage testing tracks and edit tester lists*
     - ✅ *View app information and download bulk reports (read-only)*
   - Click **Invite user** / **Send invite**.

4. **Add GitHub Secret**:
   - In GitHub repository settings, navigate to **Settings** > **Secrets and variables** > **Actions**.
   - Click **New repository secret**.
   - Name: `PLAY_CONFIG_JSON`
   - Secret: Paste the entire contents of the downloaded service account `.json` key file.

### Android SDK licenses

Release builds fail until the SDK licenses are accepted on the build machine.
This is interactive and must be run once by a person:

```bash
flutter doctor --android-licenses
```

<!-- Gene - Oct 08, 2026: Expanded iOS signing documentation into comprehensive step-by-step Apple Developer Portal, certificates, provisioning profiles, API keys, and GitHub Secrets guide.
### iOS signing

Open `ios/Runner.xcworkspace` in Xcode, select the Runner target, and enable
*Automatically manage signing* with the Switch Fiber team. The bundle
identifier is `dev.genexis.swithfibertech`; it must exist in App Store
Connect before the first upload.
-->
<!-- Gene - Oct 08, 2026: Added complete Apple signing setup, certificates/profiles export, App Store Connect API keys, and GitHub Secrets reference. -->
### iOS signing & TestFlight setup

Switch Fiber Tech uses manual App Store distribution signing for CI and local automated releases, configured via `ios/ExportOptions.plist`.
- **Bundle Identifier**: `dev.genexis.swithfibertech` (must exist in Apple Developer Portal and App Store Connect)
<!-- Gene - Oct 08, 2026: Updated Apple Team ID to personal account T7LB768N2Z.
- **Apple Team ID**: `8AD458D2K2`
-->
- **Apple Team ID**: `T7LB768N2Z`
- **Distribution Method**: `app-store`

#### Step 1: Export Apple Distribution Certificate (`.p12`)
1. Open **Keychain Access** on your macOS machine.
2. From the application menu, select **Keychain Access** > **Certificate Assistant** > **Request a Certificate from a Certificate Authority...**.
   - User Email Address: Your Apple ID email address.
   - Common Name: e.g., `Switch Fiber Tech Distribution`.
   - Request is: Choose **Saved to disk** and save `CertificateSigningRequest.certSigningRequest`.
3. Sign in to the [Apple Developer Portal - Certificates](https://developer.apple.com/account/resources/certificates/list).
4. Click the **+** button next to Certificates.
5. Under **Software**, select **Apple Distribution** (or iOS Distribution) and click **Continue**.
6. Upload your `.certSigningRequest` file and click **Generate**.
7. Download the resulting certificate (`distribution.cer`).
8. Double-click `distribution.cer` to install it into Keychain Access (under the `login` keychain).
9. In Keychain Access, find the installed certificate under **My Certificates** (`Apple Distribution: ...`). Expand it to verify the private key is nested under the certificate.
10. Select both the certificate and its private key, right-click, and choose **Export 2 items...**.
11. Choose file format **Personal Information Exchange (.p12)** and save as `switchfiber-distribution.p12`.
12. Enter a strong password to protect the exported `.p12` file. Store this password securely; it will be used for `APPLE_CERTIFICATE_PASSWORD`.

#### Step 2: Create & download App Store Provisioning Profile (`.mobileprovision`)
<!-- Gene - Oct 08, 2026: Updated Team ID to personal account T7LB768N2Z.
1. In [Apple Developer Portal - Identifiers](https://developer.apple.com/account/resources/identifiers/list), ensure the App ID `dev.genexis.swithfibertech` is registered under Team ID `8AD458D2K2`.
-->
1. In [Apple Developer Portal - Identifiers](https://developer.apple.com/account/resources/identifiers/list), ensure the App ID `dev.genexis.swithfibertech` is registered under Team ID `T7LB768N2Z`.
2. Navigate to [Apple Developer Portal - Profiles](https://developer.apple.com/account/resources/profiles/list).
3. Click the **+** button next to Profiles.
4. Under **Distribution**, select **App Store** and click **Continue**.
5. Select the App ID `dev.genexis.swithfibertech` and click **Continue**.
6. Select the **Apple Distribution Certificate** created in Step 1 and click **Continue**.
7. Name the provisioning profile (e.g. `Switch Fiber Tech App Store Distribution`) and click **Generate**.
8. Download the profile (`Switch_Fiber_Tech_App_Store_Distribution.mobileprovision`).

#### Step 3: Create App Store Connect API Key (`.p8`)
An App Store Connect API Key allows CI runners and local command-line scripts to upload builds to TestFlight without 2-factor authentication prompts.
1. Sign in to [App Store Connect](https://appstoreconnect.apple.com/).
2. Navigate to **Users and Access** > **Integrations** tab > **App Store Connect API**.
3. Click the **+** button to generate a new API key.
4. Fill in the details:
   - **Name**: e.g. `SwitchFiber-CI-Deployer`
   - **Access**: Select **App Manager** or **Admin** (required for TestFlight binary uploads and build processing).
5. Click **Generate**.
6. Note down the displayed **Key ID** (10 alphanumeric characters, e.g. `ABCD1234EF`).
7. Copy the **Issuer ID** (UUID at the top of the keys table, e.g. `69a6de70-xxxx-xxxx-xxxx-xxxxxxxxxxxx`).
8. Click **Download API Key** to download `AuthKey_<KEY_ID>.p8`.
   > [!IMPORTANT]
   > The `.p8` private key file can only be downloaded once from App Store Connect. Store it securely.
9. For local release script usage, place the key in your home directory:
   ```bash
   mkdir -p ~/.appstoreconnect/private_keys
   cp path/to/AuthKey_<KEY_ID>.p8 ~/.appstoreconnect/private_keys/
   ```

#### Step 4: Base64 encoding & GitHub Secrets configuration
To configure GitHub Actions for automated iOS builds and TestFlight releases, encode each binary asset to Base64 on macOS:

```bash
# 1. Distribution Certificate (.p12)
base64 -i switchfiber-distribution.p12 | pbcopy

# 2. Provisioning Profile (.mobileprovision)
base64 -i Switch_Fiber_Tech_App_Store_Distribution.mobileprovision | pbcopy

# 3. App Store Connect API Key (.p8)
base64 -i ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 | pbcopy
```

<!-- Gene - Oct 08, 2026: Updated secrets table to reflect standard names used in activity_timer and offline_bible with backwards-compatible aliases.
| Secret | Value | Description |
|---|---|---|
| `APPLE_CERTIFICATE_BASE64` | `base64 -i switchfiber-distribution.p12` | Base64-encoded `.p12` distribution certificate with private key |
| `APPLE_CERTIFICATE_PASSWORD` | `<certificate-password>` | Password set when exporting the `.p12` file |
| `APPLE_PROVISIONING_PROFILE_BASE64` | `base64 -i profile.mobileprovision` | Base64-encoded `.mobileprovision` App Store distribution profile |
| `APP_STORE_CONNECT_API_KEY_BASE64` | `base64 -i AuthKey_<KEY_ID>.p8` | Base64-encoded App Store Connect API private key (`.p8`) |
| `APP_STORE_CONNECT_KEY_ID` | e.g. `ABCD1234EF` | App Store Connect API 10-character Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | e.g. `69a6de70-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | App Store Connect API Issuer ID UUID |
-->
| Secret Name (Standard) | Alternative Alias | Description |
|---|---|---|
| `BUILD_CERTIFICATE_BASE64` | `APPLE_CERTIFICATE_BASE64` | Base64-encoded `.p12` distribution certificate with private key |
| `P12_PASSWORD` | `APPLE_CERTIFICATE_PASSWORD` | Password set when exporting the `.p12` file |
| `BUILD_PROVISION_PROFILE_BASE64` | `APPLE_PROVISIONING_PROFILE_BASE64` | Base64-encoded `.mobileprovision` App Store distribution profile |
| `APPSTORE_PRIVATE_KEY` | `APP_STORE_CONNECT_API_KEY_BASE64` | Base64-encoded App Store Connect API private key (`.p8`) |
| `APPSTORE_KEY_ID` | `APP_STORE_CONNECT_KEY_ID` | App Store Connect API 10-character Key ID |
| `APPSTORE_ISSUER_ID` | `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect API Issuer ID UUID |


### Application identifiers

| Platform | Identifier |
|---|---|
| Android | `dev.genexis.swithfibertech` |
| iOS | `dev.genexis.swithfibertech` |

One identifier on both stores. Identifiers cannot be changed after the first
store upload. If it ever has to change again, update
`android/app/build.gradle.kts` (`namespace` and `applicationId`), the Kotlin
package directory under `android/app/src/main/kotlin`, and every
`PRODUCT_BUNDLE_IDENTIFIER` in `ios/Runner.xcodeproj/project.pbxproj`.

## 2. Cutting a release

1. Update `CHANGELOG.md`: move the *Unreleased* entries under a new version
   heading with today's date.
2. Bump `version:` in `pubspec.yaml` (`MAJOR.MINOR.PATCH+BUILD`). The build
   number must be higher than every build ever uploaded to either store. CI
   overrides it with the workflow run number, so it only needs bumping for
   local uploads.
3. Verify locally:

   ```bash
   flutter analyze --fatal-infos && dart format --set-exit-if-changed -o none lib test && flutter test
   ```

4. Tag and push (Automated Release):

   ```bash
   git tag v1.0.1 && git push origin v1.0.1
   ```

<!-- Gene - Oct 08, 2026: Updated release pipeline description to reflect simultaneous Android and iOS TestFlight builds and new workflow_dispatch platform input.
   The release workflow (`.github/workflows/release.yml`):
   - Runs test checks (`flutter test`).
   - Restores the upload keystore from secrets.
   - Builds signed release `.aab` (App Bundle) and `.apk` with obfuscation.
   - Automatically deploys the `.aab` to Google Play **Internal Testing** track.
   - Attaches `app-release.aab`, `app-release.apk`, and the obfuscation symbols archive to a GitHub Release.

5. Alternative: Manual Run via GitHub Actions UI (Workflow Dispatch):
   - In GitHub, go to the **Actions** tab.
   - Select the **Release** workflow in the left sidebar.
   - Click **Run workflow**.
   - Choose target branch (e.g., `main`), track (`internal` by default, or `alpha`/`beta`/`production`), and optionally specify a custom build number.
   - Click **Run workflow** to initiate deployment to Google Play.
-->
<!-- Gene - Oct 08, 2026: Documented concurrent Android and iOS TestFlight CI release jobs, symbol archiving, and workflow_dispatch platform targeting. -->
   The release workflow (`.github/workflows/release.yml`) executes two parallel jobs:
   - **Android Job (`android`)**:
     - Runs test checks (`flutter test`).
     - Restores the upload keystore from `ANDROID_KEYSTORE_BASE64`.
     - Compiles signed release `.aab` (App Bundle) and `.apk` with Dart obfuscation (`--split-debug-info=build/symbols/android`).
     - Automatically deploys the `.aab` to Google Play (**Internal Testing** track by default).
     - Archives obfuscation symbols (`symbols-android-<tag>.tar.gz`) and attaches artifacts (`.aab`, `.apk`, symbols) to the GitHub Release.
   - **iOS Job (`ios`)**:
     - Runs on `macos-latest`.
     - Runs test checks (`flutter test`).
     - Creates an ephemeral keychain and imports the distribution certificate and provisioning profile.
     - Compiles signed release `.ipa` with Dart obfuscation using `ios/ExportOptions.plist` (`--split-debug-info=build/symbols/ios`).
     - Deploys the `.ipa` to Apple TestFlight via `xcrun altool` using App Store Connect API credentials (`.p8`).
     - Archives obfuscation symbols (`symbols-ios-<tag>.tar.gz`) and attaches artifacts (`.ipa`, symbols) to the GitHub Release.
     - Cleans up the temporary keychain and credentials.

<!-- Gene - Oct 09, 2026: Added terminal deployment commands using ./scripts/deploy.sh and gh CLI, and documented that auto-trigger on push to main is disabled.
5. Alternative: Manual Run via GitHub Actions UI (Workflow Dispatch):
   - In GitHub, go to the **Actions** tab.
   - Select the **Release** workflow in the left sidebar.
   - Click **Run workflow**.
   - Configure workflow inputs:
     - **Target platform to release** (`platform`): `all` (default), `android`, or `ios`. Allows deploying only Android or only iOS independently.
     - **Google Play track** (`track`): `internal` (default), `alpha`, `beta`, or `production` (applies to Android).
     - **Override build number** (`build_number`): Integer override (leave blank to use the sequential GitHub run number).
   - Click **Run workflow** to initiate automated deployment to Google Play, TestFlight, or both.

-->
<!-- Gene - Oct 09, 2026: Updated terminal deployment instructions to prioritize unified release.yml dispatching across both platforms and tracks.
5. Triggering Deployments from the Terminal (On-Demand):

   Auto-triggering on `push` to `main` is disabled for all deployment workflows to prevent unintentional builds. You can trigger deployments anytime from your terminal:

   **Option A: Using `./scripts/deploy.sh` helper script**:
   ```bash
   # Deploy iOS app to TestFlight:
   ./scripts/deploy.sh ios

   # Deploy Android app to Google Play (Internal Testing):
   ./scripts/deploy.sh android

   # Deploy both iOS and Android via Release pipeline:
   ./scripts/deploy.sh all

   # Add --watch to follow live runner logs directly in terminal:
   ./scripts/deploy.sh ios --watch

   # Interactive menu:
   ./scripts/deploy.sh
   ```

   **Option B: Using GitHub CLI directly (`gh`)**:
   ```bash
   # Deploy to Apple TestFlight:
   gh workflow run deploy-testflight.yml

   # Deploy to Google Play Internal Testing:
   gh workflow run deploy-internal.yml

   # Deploy both (or either) via Release pipeline:
   gh workflow run release.yml -f platform=all
   gh workflow run release.yml -f platform=ios
   gh workflow run release.yml -f platform=android -f track=internal
   ```

6. Alternative: Manual Run via GitHub Actions Web UI (Workflow Dispatch):
   - In GitHub, navigate to the **Actions** tab.
   - Select **Deploy to Apple TestFlight**, **Deploy to Google Play Internal Testing**, or **Release** in the left sidebar.
   - Click **Run workflow** -> select branch (`main`) -> click **Run workflow**.
-->
<!-- Gene - Oct 09, 2026: Documented unified release.yml terminal dispatch commands for Apple TestFlight, Google Play Closed Testing, and Internal Testing. -->
5. Triggering Deployments from the Terminal (On-Demand):

   Auto-triggering on `push` to `main` is disabled across all workflows to prevent unintentional builds. You can trigger deployments anytime directly from your terminal using the unified `release.yml` workflow:

   **Unified GitHub CLI (`gh`) Commands**:
   ```bash
   # 🚀 Deploy both Apple TestFlight and Google Play:
   gh workflow run release.yml -f platform=all

   # 🍏 Deploy only to Apple TestFlight:
   gh workflow run release.yml -f platform=ios

   # 🤖 Deploy only to Google Play Internal Testing:
   gh workflow run release.yml -f platform=android -f track=internal

   # 🤖 Deploy only to Google Play Closed Testing (alpha default):
   gh workflow run release.yml -f platform=android
   ```

   **Alternative: Using `./scripts/deploy.sh` wrapper**:
   ```bash
   ./scripts/deploy.sh all               # Deploy both TestFlight & Play Closed Testing
   ./scripts/deploy.sh all-internal      # Deploy both TestFlight & Play Internal Testing
   ./scripts/deploy.sh ios               # Deploy only to TestFlight
   ./scripts/deploy.sh android           # Deploy to Google Play Closed Testing (alpha)
   ./scripts/deploy.sh android-internal  # Deploy to Google Play Internal Testing
   ./scripts/deploy.sh                   # Interactive selection menu
   ```

6. Alternative: Manual Run via GitHub Actions Web UI (Workflow Dispatch):
   - In GitHub, navigate to the **Actions** tab.
   - Select **Release** in the left sidebar.
   - Click **Run workflow**:
     - **Target platform to release**: `all`, `ios`, or `android`
     - **Google Play track**: `alpha` (Closed Testing, default), `internal`, `beta`, or `production`
   - Click **Run workflow**.


## 3. Building locally

Android, signed and obfuscated:

```bash
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols/android
```

Direct-install APK for technicians outside the Play Store:

```bash
flutter build apk --release --obfuscate --split-debug-info=build/symbols/android
```

<!-- Gene - Oct 08, 2026: Replaced basic iOS build snippet with comprehensive instructions for ./scripts/deploy_testflight.sh local release script and manual IPA build with export options.
iOS:

```bash
flutter build ipa --release --obfuscate --split-debug-info=build/symbols/ios
```

Then upload `build/ios/ipa/*.ipa` with Transporter or
`xcrun altool --upload-app`.
-->
<!-- Gene - Oct 08, 2026: Documented automated local TestFlight deploy script (options, env vars, examples) and manual export-options build commands. -->
iOS (Local TestFlight Automation Script):

The repository provides `./scripts/deploy_testflight.sh`, a turnkey macOS release script that verifies prerequisites, executes static analysis and unit tests, compiles an obfuscated release IPA with `ios/ExportOptions.plist`, archives debug symbols, and uploads directly to Apple TestFlight.

```bash
# 1. Standard build, test, and upload to TestFlight (using env vars or stored .p8 key):
./scripts/deploy_testflight.sh

# 2. Build and upload with explicit build number and API credentials:
./scripts/deploy_testflight.sh \
  --build-number 105 \
  --api-key ABCD1234EF \
  --api-issuer 69a6de70-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# 3. Build signed IPA and archive symbols only (skip upload, for Transporter manual delivery):
./scripts/deploy_testflight.sh --skip-upload

# 4. Fast development build skipping test suite:
./scripts/deploy_testflight.sh --skip-tests --skip-upload
```

**Script Options & Environment Variables:**
- `--build-number <num>`: Integer build number override.
- `--skip-tests`: Skip `flutter analyze --fatal-infos` and `flutter test`.
- `--skip-upload`: Build the IPA and symbols archive without uploading to TestFlight.
- `--api-key <key-id>`: App Store Connect API Key ID (defaults to `$APP_STORE_CONNECT_KEY_ID`).
- `--api-issuer <uuid>`: App Store Connect Issuer ID UUID (defaults to `$APP_STORE_CONNECT_ISSUER_ID`).
- `-h`, `--help`: Display usage and prerequisites help.

**Manual iOS build:**

If you prefer building manually without the script:

```bash
flutter build ipa --release \
  --obfuscate --split-debug-info=build/symbols/ios \
  --export-options-plist=ios/ExportOptions.plist
```

Then upload the resulting `build/ios/ipa/*.ipa` using:
1. **Apple Transporter App**: Download "Transporter" from the Mac App Store, sign in, and drag-and-drop the generated `.ipa` file to deliver.
2. **`xcrun altool` Command Line**:
   ```bash
   xcrun altool --upload-app \
     -f build/ios/ipa/*.ipa \
     -t ios \
     --apiKey "$APP_STORE_CONNECT_KEY_ID" \
     --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"
   ```


**Keep the `build/symbols` directory for every release.** Without it, crash
stack traces from obfuscated builds cannot be read, and the symbols cannot be
regenerated later.

## 4. Store submission checklist

- [ ] Version and build number bumped; build number never used before.
- [ ] `android/key.properties` present, or CI secrets set: the Gradle log must
      not print the "signed with the DEBUG key" warning.
- [ ] Obfuscation symbols archived with the release.
- [ ] Signed build tested on a real low-end Android device against the
      production API, including sign-in, pull-to-refresh, and an offline edit
      that syncs when the connection returns.
- [ ] Play Console *Data safety* form completed: the app collects technician
      account data and job-order records, transmitted over TLS, not shared.
<!-- Gene - Nov 05, 2026: Added reference to docs/APP_STORE_LISTING.md for Apple App Store production metadata, review credentials, and ATS declarations.
- [ ] App Store Connect privacy questions answered to match.
-->
- [ ] App Store Connect privacy questions answered to match (see `docs/APP_STORE_LISTING.md`).
- [ ] Apple App Review notes and demo credentials configured per `docs/APP_STORE_LISTING.md`.
- [ ] Certificate pin in `AppConstants.pinnedApiCertSha256` matches the
      production server's current certificate. A reissued server certificate
      breaks every installed build until an update ships.
- [ ] Staged rollout on Play (start at 10 to 20 percent); TestFlight before App
      Store review.

## 5. After release

Watch crash-free sessions for the first 24 hours. A Play staged rollout can be
halted; an App Store release can only be superseded by a new build, so the iOS
bar for "ready" is higher.
