# Environment and validation — Phases 1–3

Phase 3 is implemented and validated in the cloud checkout. Development version 0.3.0+3 adds advance entry, additional dated received payments and audited corrections to the working customer/order/measurement/search/filter features. XLSX and PDFs remain later phases. The developer reported installing/testing the Phase 2 APK and that filters and other existing controls work; payment entry was absent in that version. Device model/Android version were not supplied. No Android device or emulator is attached to this cloud workspace, so Phase 3 installation/upgrade and force-stop behavior remain unverified here.

## Prepared development environment

- Flutter stable 3.47.7, commit abaf9c523780a608bd46686fd5e53740a07077f8; bundled Dart 3.13.5.
- Temurin JDK 21.0.12.1+1 with javac. Its archive was verified against the official SHA-256. The preinstalled Java runtime lacked a compiler.
- Android command-line tools 19.0 verified against official repository metadata; SDK platforms 35/36, build tools 36.0.0, NDK 28.2.13676358 and CMake 3.22.1. SDK licenses accepted through the supported setup flow.
- Android minimum API 24 (Android 7.0), AGP 9.1.0, Kotlin 2.4.0 and Gradle 9.3.1. The Gradle wrapper pins the official distribution SHA-256.
- Package and Gradle caches reside under /workspace/toolchains. Gradle and SDK manager use the environment's supplied proxy and maintained Java CA trust store; certificate/checksum verification remains enabled.
- The network policy now permits storage.googleapis.com. The earlier release manifest URL returned NoSuchKey after access was enabled; installation used Flutter's official Git checkout and its standard SDK/artifact bootstrap instead.

## Executed checks

- `flutter analyze`: clean for the final Phase 3 source, zero issues.
- `flutter test --reporter expanded`: 51 tests passed, zero failures or skips (32 existing tests plus 19 Phase 3 tests). Existing tests still cover exact amounts, catalog/measurement validation, persistence, multiple garments, rollback, foreign keys, uniqueness, item snapshot isolation, schema v1/reopen, customer/order forms and all requested filters/sorts. Phase 3 tests add optional/dated advances, partial/full received amounts, overlapping requests, stale and wrong-bill corrections, linked correction chains, visibly retained history, invalid dates/overpayments, late-insert rollback, order edit guards, cancelled/delivered independence, zero-total bills and file-backed payment-history reopen. Three widget tests exercise order advance entry, receive/replace/void history and overpayment/back navigation on compact layouts. No Drift database warnings remain in the final test run.
- `flutter build apk --debug`: passed for final Phase 3 source. APK: build/app/outputs/flutter-apk/app-debug.apk; SHA-256 19b42d8884ee054a6211c7c2282fdea6473550d5ba2b7a18dd5448c427453feb. Development version is 0.3.0+3. Debug APK includes Flutter development Internet permission; the production main manifest has none. The local build uses the local debug signing key, so its binary checksum can differ from this cloud build.
- `flutter devices`: only Linux desktop detected; no Android target.
- `bash scripts/setup_cloud.sh`: repeated successfully with frozen package resolution. Source files and lockfile are not rewritten by setup.
- `flutter doctor -v`: Flutter and Android toolchain pass; licenses accepted. No Android target is attached. Chrome/Linux desktop prerequisites and the maven.google.com diagnostic probe are unavailable; the actual Android build resolves its dependencies successfully.

## Limitations

This development APK supports real offline customer/order entry and editing with per-garment measurements, PAYMENT summaries and MEASUREMENTS views. It supports advance and received-payment entry plus void/replacement corrections, but cannot yet generate backups/documents. Unsaved form drafts live in memory and do not survive process termination. Saved data remains local; uninstall or device loss has no recovery UI until Phase 4. It is not the final shop deployment. Release signing is deliberately unconfigured.

Phase 2 device testing is recorded only as the developer’s report above. No cloud-executed physical-device install, force-stop/relaunch, sharing, printing or APK upgrade validation has been claimed; Phase 3 still needs its device check. Tests prove file-backed persistence after connection restart, not Android force-stop behavior. There are no historic schema upgrades before initial v1; comparison against the baseline is tested and future schema changes must add explicit upgrade/data-preservation tests.

SDK tools 19.0 emit a nonblocking XML-version warning with current metadata. Tools 23.0 introduced an incompatible launcher and were retired outside the active SDK; the tested Java-based tools remain pinned. No application analysis warnings remain.

## Reuse and publication

See DEVELOPMENT.md and scripts/setup_cloud.sh for the working directories and tested commands. The environment configuration draft retains the tested complete installation script and updates startup instructions for the Phase 3 workflow. A draft save does not execute scripts, apply settings or publish a new snapshot. Review/save the draft in environment settings and publish to retain this prepared environment for future tasks. The published workspace restored the pinned tools and Phase 2 artifacts for this task; persisted setup files and caches were reused. Live processes were not assumed to survive restoration. This does not establish a later publication or restore of Phase 3 changes.

On a local machine with Flutter 3.47.7 and an Android target, use the existing checkout, run flutter pub get --enforce-lockfile and flutter run -d <device-id>. Await user instruction before beginning Phase 4 XLSX backup/export/import.

## Phase 2 review map

Changed application areas: `lib/app/` navigation/providers; `lib/features/customers/presentation/` customer CRUD, picker and history; `lib/features/orders/domain/` query/repository APIs; `lib/features/orders/data/` transactional edits and reactive queries; `lib/features/orders/application/` form drafts; `lib/features/orders/presentation/` list, filters, editor, garments and details; `lib/shared/presentation/` shared formatting/errors/discard handling. The Phase 2 version was 0.2.0+2; dependencies and schema v1 remain unchanged.

New tests: `test/phase2_repository_test.dart`, `test/order_draft_test.dart` and `test/phase2_widget_test.dart`. Updated documentation: README, DEVELOPMENT, IMPLEMENTATION_PLAN and this validation record. Phase 3 was implemented only after the subsequent developer instruction.

## Phase 3 review map

Changed: order repository API/implementation and immutable records; order draft/editor and PAYMENT details; new `lib/features/payments/application/payment_draft.dart`, `presentation/payment_editor.dart` and `presentation/payment_history.dart`; app version in `pubspec.yaml` and Settings; project/development/plan/validation docs. New tests: `payment_draft_test.dart`, `payment_repository_test.dart`, `payment_widget_test.dart` and shared `widget_helpers.dart`. The prior widget test imports the same shared scrolling helper. Schema, dependencies, customer search and measurement storage remain unchanged.

The same `phase-2-offline-orders` Git branch carries this incremental update. Use DEVELOPMENT.md’s local pull/build/install commands to produce the APK on the machine where Flutter and the phone are connected. Phase 4 is the next authorized milestone only when requested.
