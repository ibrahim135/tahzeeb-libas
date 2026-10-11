# Implementation plan

Status: Phases 1–4 authorized and implemented; see ENVIRONMENT_STATUS.md for verification and device limitations. Start later phases only after an explicit user instruction. Work on one requested phase at a time; preserve previously working functionality.

## Environment and dependency selection

Initial repository has README.md only. Flutter/Dart/adb are unavailable on PATH; Java exists. Phase 1 verifies Java version, host architecture/resources, Flutter stable and its bundled Dart, Android SDK/platform/build tools, Gradle/AGP and device availability. Use the official Flutter SDK with verified artifacts; pin the tested release rather than choosing versions from memory. Run `flutter doctor -v`, resolve Android prerequisites and record remaining device/license constraints. Accept SDK licenses only through an authorized supported flow.

Candidate packages: flutter_riverpod, drift/drift_dev, the current supported native SQLite Flutter integration, path_provider/path, uuid, intl, excel, file_picker, share_plus, pdf and printing. Add build_runner if Drift generation needs it. Check actual SDK constraints, native plugin minimum Android versions and package APIs before choosing compatible versions. Use Flutter's bundled Dart; avoid independently mismatched Dart installs. Commit pubspec.lock and schema snapshots once implementation is authorized. No credentials or backend services are needed for normal app operation.

Required per-phase validation includes analysis, relevant executed tests and applicable Android builds. Formatting is useful but not a substitute for tests. Device-only share/print/force-stop checks require an Android target and are reported separately if unavailable. CI setup is optional until core code is present; it must run the same meaningful checks.

## Proposed structure

```text
lib/
  main.dart
  app/                 # bootstrap, theme, navigation, providers
  core/                # exact money/date parsing, shared errors/validation
  data/database/       # Drift tables, connections, migrations, schema snapshots
  features/
    customers/{domain,data,application,presentation}/
    orders/{domain,data,application,presentation}/
    measurements/{domain,application,presentation}/
    payments/{domain,application,presentation}/
    settings/{domain,data,application,presentation}/
    transfer/{domain,data,application,presentation}/
    documents/{application,presentation}/
test/                  # mirrors features, DB/migration/fixture tests
integration_test/      # Android lifecycle and critical workflows
docs/                  # spec, workbook schema, validation and release guides
android/               # generated project and minimal supported configuration
```

Create folders when functionality needs them; do not populate them with placeholder abstractions. Database repositories map rows to immutable domain records. Riverpod controls screen state and dependency injection. Transfer and PDF services remain separate from widgets and database transaction policy.

## Phase 1 — runnable foundation and durable data

Deliver: verified/pinned Flutter and Android tooling; Flutter Android scaffold; Material 3 navigation shell; compatible dependencies; exact money/date/catalog models; Drift schema v1, repository interfaces/implementations, durable app-private database, generated schema snapshot and initial migration strategy. Record environment reproduction steps and validation evidence. No broad storage/runtime internet permission in the production manifest.

Acceptance: `flutter analyze`, executed model/repository tests and debug APK build pass. Tests create/reopen a file-backed database, preserve customers/orders with multiple garment snapshots, enforce foreign keys/bill uniqueness and verify transactional rollback. Verify initial database creation/migration baseline. Shell starts on an available Android target; explicitly record if no target exists. No claim that business UI is complete.

## Phase 2 — customer and order workflow

Deliver: customer add/edit/search/history, duplicate warning/reuse; order list/detail and transactional create/edit; stable catalog/variants, numeric bill suggestion and historic bills, quantities/rates/discounts, dates/delivery status, garment measurements/notes. Safe draft/discard handling. Build domain payment-sum guard into edits even before the full payment UI. Measurement copying produces independent snapshots.

Acceptance: multiple garments save and reload with independent configuration and notes; historic bill and leading-zero phone survive; duplicate bills fail clearly; customer reuse works; optional phones/measurements work; disabled populated sections require confirmation. Search by bill/name/phone and requested filters/sorts pass tests including inclusive dates and deterministic ties. Required analyze/tests/debug build pass.

## Phase 3 — payments and complete bill views

Deliver: initial advance and additional dated payments, PAYMENT/MEASUREMENTS tabs, derived balances/status, validation and audited void/replace correction workflow. Display original corrected payments clearly. Cancellation and delivery status stay independent from money. Complete home list payment summaries/filters.

Acceptance: integer-paise calculations for multi-item discounts and partial/full payments; zero-total behavior; rejected overpayment/negative input; transactional concurrent payment checks; edits below received rejected; historical dates and void/replacement records persist. Reopening database preserves history. Critical widget flows and analyze/tests/APK build pass. Confirm refund/deposit business exceptions before extending defaults.

## Phase 4 — versioned XLSX backups and import

Deliver: complete schema documentation, export, save/share, blank template with separate examples, picker, read-only preview, row-specific diagnostics and atomic add-only commit. Include settings, counter metadata, voided payment history and all garment snapshots. Implement bounded parsing and formula rejection. Provide backup/restore guidance in Settings.

Acceptance: round-trip all persisted fields into an empty database; second import makes zero changes; conflicting IDs/bills block writes; malformed dates/amounts/types/references/formulas are reported by row; injected mid-commit failure rolls back every table. Cancel leaves database unchanged. Test cross-sheet references, leading zeroes, Unicode and multiline notes. Verify picker/share on Android; analyze/tests/APK build pass.

## Phase 5 — customer receipts and warehouse slips

Deliver: separate PDF builders, shop settings, previews, save/share and Android printing. Support multiline/page-spanning content and embedded fonts. Shop copies use these layouts; print copies use platform dialog.

Acceptance: receipt displays accurate charges/discount/received/balance; warehouse PDF contains garment measurements/notes and no monetary data. Test missing measurements, long notes, multiple garments/pages and INR rendering. Verify preview/share/save/print on an Android target with the intended paper format. Required automated checks and build pass; physical printing is reported distinctly from PDF generation.

## Phase 6 — release hardening and installable APK

Deliver: compact-screen/accessibility pass, migration fixtures and upgrade tests, lifecycle integration tests, user backup guide, owner-approved shop identity/app identifier, versioning and signed release APK/checksum. Owner securely provides/manages signing configuration outside Git. Do not generate disposable production signing ownership silently.

Acceptance: full analyze/test suite passes; migration upgrade preserves every business field; process force-stop/relaunch retains records; import/export and PDF/file integrations work on a supported real Android target; production manifest needs no internet or broad storage access; release APK installs and survives an upgrade. Record tested device/Android version, known limitations and reproducible build commands. Release sign-off requires review of actual workflow with the shop owner, not only test success.

## Working and reporting rules

Use the existing isolated `/workspace/tahzeeb-libas` checkout; no worktree unless explicitly requested. For every phase report changed files, exact checks and outcomes, unresolved issues and next phase. Avoid sensitive customer data in logs/fixtures. Never silently change business defaults. If toolchain/device/signing access blocks a required check, complete independent work and report the precise unmet prerequisite without claiming readiness. Keep environment install/start instructions tested and saved when setup is actually performed.

## Current stopping point

Phase 4 versioned XLSX backup/export/import is implemented, including settings/counter restoration, safe preview, bounded parsing and atomic add-only commits. Await instruction to begin Phase 5 (customer receipt and warehouse measurement-slip PDFs). Release hardening remains Phase 6. Android file picker/save/share still needs a real-device check; cloud compilation and automated tests are separate evidence. See ENVIRONMENT_STATUS.md for executed checks and outstanding Android-device validation.
