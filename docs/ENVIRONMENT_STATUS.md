# Environment and validation — Phases 1–4

Phase 4 is implemented and validated in the cloud checkout. Development version 0.4.0+4 adds versioned offline Excel backups, a blank template with separate examples, Android save/share/picker integrations and read-only import previews with atomic add-only commits. All working customer/order/measurement/search/filter/payment features remain. The developer reported testing v0.3 and that it works; this is the developer’s device report, without device model/Android version supplied. No Android target is attached to this cloud workspace, so v0.4 picker/save/share and install/upgrade behavior have not been executed here. PDFs and release hardening remain later phases.

## Prepared development environment

- Flutter stable 3.47.7, commit abaf9c523780a608bd46686fd5e53740a07077f8; bundled Dart 3.13.5.
- Temurin JDK 21.0.12.1+1 with javac. Its archive was verified against the official SHA-256. The preinstalled Java runtime lacked a compiler.
- Android command-line tools 19.0 verified against official repository metadata; SDK platforms 35/36, build tools 36.0.0, NDK 28.2.13676358 and CMake 3.22.1. SDK licenses accepted through the supported setup flow.
- Android minimum API 24 (Android 7.0), AGP 9.1.0, Kotlin 2.4.0 and Gradle 9.3.1. The Gradle wrapper pins the official distribution SHA-256.
- Package and Gradle caches reside under /workspace/toolchains. Gradle and SDK manager use the environment's supplied proxy and maintained Java CA trust store; certificate/checksum verification remains enabled.
- The network policy now permits storage.googleapis.com. The earlier release manifest URL returned NoSuchKey after access was enabled; installation used Flutter's official Git checkout and its standard SDK/artifact bootstrap instead.

## Executed checks

- `flutter analyze`: final Phase 4 source and tests are clean, zero issues.
- `flutter test --reporter expanded`: **83 tests passed**, zero failures/skips, with all 51 previous tests and 32 new transfer tests. Previous tests retain coverage of exact finances, durable storage, multiple garments, measurement snapshots, search/filter/sort, migrations, customer/order entry and advance/received/correction workflows. Transfer tests cover complete persisted-field XLSX round trips (including settings, counter, voids/replacements and exact measurements), reordered/no-write repeated imports, invalid rows/enums/dates/amounts/references, conflicting IDs/bills/history, similar-customer/settings confirmations, cancelled preview/picker, stale commit, late counter-trigger rollback of every table, file-backed restore/reopen and reactive order updates. Codec checks cover explicit text/leading zeroes/Unicode/multiline/null versus empty text, formulas including cached shared strings, corrupt/oversized ZIPs, forged expansion sizes, sparse coordinates and XML declarations. Three compact widget tests cover save cancellation/retry/share, blocked invalid previews/cancel and reviewed duplicate/settings commit with double-tap prevention. No Drift database warnings remain.
- `flutter build apk --debug`: passed for final Phase 4 source in 173.3 seconds, including new native plugins. APK: `build/app/outputs/flutter-apk/app-debug.apk`; SHA-256 **17ac4d00dd7103f0e960f456375d898eb78f1ab10c3d973ff61417f857793a01**. Package `in.tahzeeb.tahzeeb_libas`, versionName `0.4.0`, versionCode `4`, minimum API 24, target API 36; ARM32/ARM64/x86_64. APK inspection shows Flutter debug Internet permission and AndroidX’s internal signature-protected receiver permission, with no broad storage permission. Main manifest and file/share plugin manifests request no runtime Internet or storage permission. A local APK signed with the local debug key can have a different checksum.
- `flutter devices`: only Linux desktop detected; no Android target.
- `flutter pub get --enforce-lockfile`: passed with the Phase 4 lockfile; dependency installation remains reproducible.
- `bash scripts/setup_cloud.sh`: repeated successfully with frozen package resolution. Source files and lockfile are not rewritten by setup.
- `flutter doctor -v`: Flutter and Android toolchain pass; licenses accepted. No Android target is attached. Chrome/Linux desktop prerequisites and the maven.google.com diagnostic probe are unavailable; the actual Android build resolves its dependencies successfully.

## Limitations

This development APK supports offline records, received payments and portable XLSX backups/restoration. It cannot yet generate receipts/measurement-slip PDFs. Unsaved form drafts and in-progress transfer previews live in memory and do not survive process termination; confirmed database records do. Keep exports outside the device. Release signing is deliberately unconfigured; this is not final shop deployment.

The developer’s v0.3 report is recorded above. No cloud-executed Android installation, force-stop/relaunch, APK upgrade or real picker/save/share/print has been claimed. Mock file interfaces in widget tests prove app flow, not Android document-provider integration. Test file-backed connection restart separately from Android lifecycle. Baseline schema v1 tests still pass; Phase 4 does not change SQLite schema. No historical upgrade before initial v1 exists, and future schema changes require explicit migration/data-preservation tests. Workbook bounds and add-only/conflict behavior are documented in WORKBOOK_SCHEMA.md.

SDK tools 19.0 emit a nonblocking XML-version warning with current metadata. Tools 23.0 introduced an incompatible launcher and were retired outside the active SDK; the tested Java-based tools remain pinned. No application analysis warnings remain.

## Reuse and publication

See DEVELOPMENT.md and scripts/setup_cloud.sh for the working directories and tested commands. The environment configuration draft retains the tested complete installation script and updates startup instructions for the Phase 4 workflow. A draft save does not execute scripts, apply settings or publish a new snapshot. Review/save the draft in environment settings and publish to retain this prepared environment for future tasks. This workspace retained the pinned tools and Phase 3 checkout for this task; setup files and caches were reused. New native package dependencies were resolved using the same maintained TLS trust and Gradle proxy configuration. Live processes were not assumed to survive restoration. This does not establish a later publication or fresh-task restore of Phase 4 changes.

On a local machine with Flutter 3.47.7 and an Android target, use the existing checkout, run flutter pub get --enforce-lockfile and flutter run -d <device-id>. Await user instruction before beginning Phase 5 PDF receipts/measurement slips.

## Phase 2 review map

Changed application areas: `lib/app/` navigation/providers; `lib/features/customers/presentation/` customer CRUD, picker and history; `lib/features/orders/domain/` query/repository APIs; `lib/features/orders/data/` transactional edits and reactive queries; `lib/features/orders/application/` form drafts; `lib/features/orders/presentation/` list, filters, editor, garments and details; `lib/shared/presentation/` shared formatting/errors/discard handling. The Phase 2 version was 0.2.0+2; dependencies and schema v1 remain unchanged.

New tests: `test/phase2_repository_test.dart`, `test/order_draft_test.dart` and `test/phase2_widget_test.dart`. Updated documentation: README, DEVELOPMENT, IMPLEMENTATION_PLAN and this validation record. Phase 3 was implemented only after the subsequent developer instruction.

## Phase 3 review map

Changed: order repository API/implementation and immutable records; order draft/editor and PAYMENT details; new `lib/features/payments/application/payment_draft.dart`, `presentation/payment_editor.dart` and `presentation/payment_history.dart`; app version in `pubspec.yaml` and Settings; project/development/plan/validation docs. New tests: `payment_draft_test.dart`, `payment_repository_test.dart`, `payment_widget_test.dart` and shared `widget_helpers.dart`. The prior widget test imports the same shared scrolling helper. Schema, dependencies, customer search and measurement storage remain unchanged.

The same `phase-2-offline-orders` Git branch carries this incremental update. Use DEVELOPMENT.md’s local pull/build/install commands to produce the APK on the machine where Flutter and the phone are connected. Phase 4 was implemented after the developer reported v0.3 working and authorized continuing. Phase 5 remains unstarted.

## Phase 4 review map

Changed: `lib/app/` providers/navigation, new `lib/features/transfer/{domain,data,application,presentation}/`, new `lib/features/settings/presentation/settings_screen.dart`, version/dependencies and resolved lockfile. New tests: `workbook_repository_test.dart`, `workbook_codec_test.dart`, `workbook_widget_test.dart`. New schema guide: `docs/WORKBOOK_SCHEMA.md`; updated specification, plan, development guide, README and this evidence record. Database v1/generated schema artifacts, app ID, previous customer/order/payment logic and main-manifest permissions are preserved.

Validation logs for this run are under `/workspace/toolchains/`: `phase4-analyze-final.log`, `phase4-tests-final.log`, `phase4-build-progress.log`, `phase4-devices.log` and `phase4-pub-get.log`. Build directories/APKs, logs and private business databases are not committed. The same `phase-2-offline-orders` branch carries the source update; build/install locally with the same signing key as the tested v0.3 app.
