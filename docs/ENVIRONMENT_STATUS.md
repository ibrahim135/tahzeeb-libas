# Environment and validation — Phases 1 and 2

Phase 2 is implemented and validated in the cloud checkout. Development version 0.2.0+2 supports customer management, order creation/editing, independent garment measurements, history, search and filters. Advance/additional payment entry, XLSX and PDFs remain later phases. Android-device installation/startup remains unverified because no Android device or emulator is attached.

## Prepared development environment

- Flutter stable 3.47.7, commit abaf9c523780a608bd46686fd5e53740a07077f8; bundled Dart 3.13.5.
- Temurin JDK 21.0.12.1+1 with javac. Its archive was verified against the official SHA-256. The preinstalled Java runtime lacked a compiler.
- Android command-line tools 19.0 verified against official repository metadata; SDK platforms 35/36, build tools 36.0.0, NDK 28.2.13676358 and CMake 3.22.1. SDK licenses accepted through the supported setup flow.
- Android minimum API 24 (Android 7.0), AGP 9.1.0, Kotlin 2.4.0 and Gradle 9.3.1. The Gradle wrapper pins the official distribution SHA-256.
- Package and Gradle caches reside under /workspace/toolchains. Gradle and SDK manager use the environment's supplied proxy and maintained Java CA trust store; certificate/checksum verification remains enabled.
- The network policy now permits storage.googleapis.com. The earlier release manifest URL returned NoSuchKey after access was enabled; installation used Flutter's official Git checkout and its standard SDK/artifact bootstrap instead.

## Executed checks

- `flutter analyze`: clean for the final Phase 2 source, zero issues.
- `flutter test --reporter expanded`: 32 tests passed, zero failures or skips (16 foundation tests plus 16 Phase 2 tests). Covers exact amounts, catalog/measurement validation, derived payments, customer/order persistence, multiple garments, transactional rollback, foreign keys, bill uniqueness, item snapshot isolation, a file-backed close/reopen through background isolates and schema v1 baseline comparison. Phase 2 coverage adds actual-ledger edit guards, stale edits, failed-edit rollback, customer duplicates and escaped search, inclusive date/payment/status filters, all nine sorts with stable ties, reactive summaries, independent copied snapshots, customer reuse/discard prompts and real order creation/editing on a 360px phone layout.
- `flutter build apk --debug`: passed for final Phase 2 source. APK: build/app/outputs/flutter-apk/app-debug.apk; SHA-256 b93d29fb80e413715678f9c2b6e65d4fb37f1153692c738e976f3b620dba85a5. APK metadata confirms version 0.2.0, version code 2, minimum API 24, target API 36 and ARM32/ARM64/x86_64 native libraries. Debug APK includes Flutter development Internet permission; the production main manifest has none.
- `bash scripts/setup_cloud.sh`: repeated successfully with frozen package resolution. Source files and lockfile are not rewritten by setup.
- `flutter doctor -v`: Flutter and Android toolchain pass; licenses accepted. No Android target is attached. Chrome/Linux desktop prerequisites and the maven.google.com diagnostic probe are unavailable; the actual Android build resolves its dependencies successfully.

## Limitations

This development APK supports real offline customer/order entry and editing with per-garment measurements, PAYMENT summaries and MEASUREMENTS views. It cannot yet record payments through the UI or generate backups/documents. Unsaved form drafts live in memory and do not survive process termination. Saved data remains local; uninstall or device loss has no recovery UI until Phase 4. It is not the final shop deployment. Release signing is deliberately unconfigured.

No physical-device install, force-stop/relaunch, sharing, printing or APK upgrade validation has been claimed. Tests prove file-backed persistence after connection restart, not Android force-stop behavior. There are no historic schema upgrades before initial v1; comparison against the baseline is tested and future schema changes must add explicit upgrade/data-preservation tests.

SDK tools 19.0 emit a nonblocking XML-version warning with current metadata. Tools 23.0 introduced an incompatible launcher and were retired outside the active SDK; the tested Java-based tools remain pinned. No application analysis warnings remain.

## Reuse and publication

See DEVELOPMENT.md and scripts/setup_cloud.sh for the working directories and tested commands. The environment configuration draft retains the tested complete installation script and updates startup instructions for the Phase 2 workflow. A draft save does not execute scripts, apply settings or publish a new snapshot. Review/save the draft in environment settings and publish to retain this prepared environment for future tasks. Restoration in a new task has not yet been tested.

On a local machine with Flutter 3.47.7 and an Android target, use the existing checkout, run flutter pub get --enforce-lockfile and flutter run -d <device-id>. Await user instruction before beginning Phase 3 payment entry/corrections.

## Phase 2 review map

Changed application areas: `lib/app/` navigation/providers; `lib/features/customers/presentation/` customer CRUD, picker and history; `lib/features/orders/domain/` query/repository APIs; `lib/features/orders/data/` transactional edits and reactive queries; `lib/features/orders/application/` form drafts; `lib/features/orders/presentation/` list, filters, editor, garments and details; `lib/shared/presentation/` shared formatting/errors/discard handling. `pubspec.yaml` now declares 0.2.0+2; dependencies and schema v1 remain unchanged.

New tests: `test/phase2_repository_test.dart`, `test/order_draft_test.dart` and `test/phase2_widget_test.dart`. Updated documentation: README, DEVELOPMENT, IMPLEMENTATION_PLAN and this validation record. No Phase 3 work is authorized by Phase 2 completion.
