# Environment and validation — Phases 1–5

Phase 5 is implemented and validated in the cloud checkout. Development version
0.5.0+5 adds editable shop details and English offline A4 payment receipts and
warehouse measurement slips with preview, save/share, Android printing and Shop
copy. Phases 1–4 functionality is preserved. The developer reported v0.3 working;
phone model/Android version were not supplied. No Android target is attached here,
so native PDF/file/print, actual installation/upgrade and physical output remain
local device checks. Phase 6 release hardening is not started. The selected TL
logo is recorded, pending original PNG/JPG file delivery; themes are planned as
optional Phase 7, not implemented.

## Prepared development environment

- Flutter stable 3.47.7, commit abaf9c523780a608bd46686fd5e53740a07077f8; bundled Dart 3.13.5.
- Temurin JDK 21.0.12.1+1 with javac. Its archive was verified against the official SHA-256. The preinstalled Java runtime lacked a compiler.
- Android command-line tools 19.0 verified against official repository metadata; SDK platforms 34/35/36, build tools 36.0.0, NDK 28.2.13676358 and CMake 3.22.1. SDK licenses accepted through the supported setup flow.
- Android minimum API 24 (Android 7.0), AGP 9.1.0, Kotlin 2.4.0 and Gradle 9.3.1. The Gradle wrapper pins the official distribution SHA-256.
- Package and Gradle caches reside under /workspace/toolchains. Gradle and SDK manager use the environment's supplied proxy and maintained Java CA trust store; certificate/checksum verification remains enabled.
- The network policy now permits storage.googleapis.com. The earlier release manifest URL returned NoSuchKey after access was enabled; installation used Flutter's official Git checkout and its standard SDK/artifact bootstrap instead.

## Executed Phase 5 checks

- `flutter pub get --enforce-lockfile`: passed. Compatible additions are pdf
  3.12.0 and printing 5.14.3; working Excel 4.0.6/archive 3.6.1 remain pinned.
- `flutter analyze --no-pub`: **zero issues** on final source/tests.
- `flutter test --no-pub --reporter expanded`: **97 tests passed**, zero failures
  or skips, retaining all 83 previous tests and adding 14 document/settings tests.
  Coverage includes exact receipt sums/discount/active historical corrections,
  pending/paid/zero totals, warehouse financial/private-note exclusion, variants,
  optional phones/measurements and distinct upper/lower fields, embedded INR
  fonts, long multiline and unbroken text, 160 garments spanning over 20 pages,
  unsupported-character errors, consistent/fresh immutable snapshots, settings
  streams/stale edits/Excel-preview invalidation/file reopen/backup fields,
  compact copy/actions/cancel/error feedback, frozen A4 print callbacks and
  guarded shop editing. Widget native raster/print/file actions are mocks.
- Synthetic receipt and warehouse PDFs (both original/shop labels) were generated
  with `TAHZEEB_PDF_SAMPLES=/workspace/toolchains/phase5-samples`. Independent
  `python3 scripts/inspect_document_samples.py /workspace/toolchains/phase5-samples`
  passed using Poppler extraction: correct INR charges and active receipt amounts,
  warehouse exclusions, A4 dimensions and all 800 instructions/200 long-token
  repetitions/final marker preserved in a 20-page long slip. Receipt/warehouse
  first-page images were rendered with `pdftoppm` and visually inspected. These
  are synthetic document checks, not Android-native preview or physical printing.
- `flutter build apk --debug --no-pub`: passed in **116.1 seconds**. APK:
  `build/app/outputs/flutter-apk/app-debug.apk`; SHA-256
  **a786dca1c6ddc0c3f6cd32a37a79c66f62141fce619402d860331b02157f6b50**.
  Package `in.tahzeeb.tahzeeb_libas`, versionName `0.5.0`, versionCode `5`, minimum
  API 24, target API 36. APK inspection shows only Flutter debug Internet and
  AndroidX's internal signature-protected receiver permission; no broad storage
  permission. Main manifest remains unchanged with no Internet/storage permission.
  A local APK signed with the local key may have a different checksum.
- `flutter devices`: only Linux desktop; no Android target.
- Setup now explicitly installs Android platform 34 alongside 35/36 because the
  compatible printing plugin compiles against 34. It was installed through the
  supported SDK/license flow during the successful build. SDK tools still emit
  the previously recorded XML-version warning; the printing plugin emits three
  Java 8 source/target obsolescence warnings under JDK 21. These are nonblocking
  vendor-toolchain warnings; no app analysis warnings/errors remain. No warnings
  were suppressed or third-party package cache source patched.
- `bash -n scripts/setup_cloud.sh`: passed; the revised complete setup script was
  rerun successfully after adding SDK platform 34. Frozen package resolution and
  the same pinned Flutter/JDK/Android tools are retained.

## Historical Phase 4 checks

- `flutter analyze`: final Phase 4 source and tests are clean, zero issues.
- `flutter test --reporter expanded`: **83 tests passed**, zero failures/skips, with all 51 previous tests and 32 new transfer tests. Previous tests retain coverage of exact finances, durable storage, multiple garments, measurement snapshots, search/filter/sort, migrations, customer/order entry and advance/received/correction workflows. Transfer tests cover complete persisted-field XLSX round trips (including settings, counter, voids/replacements and exact measurements), reordered/no-write repeated imports, invalid rows/enums/dates/amounts/references, conflicting IDs/bills/history, similar-customer/settings confirmations, cancelled preview/picker, stale commit, late counter-trigger rollback of every table, file-backed restore/reopen and reactive order updates. Codec checks cover explicit text/leading zeroes/Unicode/multiline/null versus empty text, formulas including cached shared strings, corrupt/oversized ZIPs, forged expansion sizes, sparse coordinates and XML declarations. Three compact widget tests cover save cancellation/retry/share, blocked invalid previews/cancel and reviewed duplicate/settings commit with double-tap prevention. No Drift database warnings remain.
- `flutter build apk --debug`: passed for final Phase 4 source in 173.3 seconds, including new native plugins. APK: `build/app/outputs/flutter-apk/app-debug.apk`; SHA-256 **17ac4d00dd7103f0e960f456375d898eb78f1ab10c3d973ff61417f857793a01**. Package `in.tahzeeb.tahzeeb_libas`, versionName `0.4.0`, versionCode `4`, minimum API 24, target API 36; ARM32/ARM64/x86_64. APK inspection shows Flutter debug Internet permission and AndroidX’s internal signature-protected receiver permission, with no broad storage permission. Main manifest and file/share plugin manifests request no runtime Internet or storage permission. A local APK signed with the local debug key can have a different checksum.
- `flutter devices`: only Linux desktop detected; no Android target.
- `flutter pub get --enforce-lockfile`: passed with the Phase 4 lockfile; dependency installation remains reproducible.
- `bash scripts/setup_cloud.sh`: repeated successfully with frozen package resolution. Source files and lockfile are not rewritten by setup.
- `flutter doctor -v`: Flutter and Android toolchain pass; licenses accepted. No Android target is attached. Chrome/Linux desktop prerequisites and the maven.google.com diagnostic probe are unavailable; the actual Android build resolves its dependencies successfully.

## Limitations

This development APK supports offline records, received payments and portable XLSX backups/restoration. Phase 5 adds receipts/measurement-slip PDFs; native phone preview/save/share/print remains unverified. Unsaved form drafts and in-progress transfer previews live in memory and do not survive process termination; confirmed database records do. Keep exports outside the device. Release signing is deliberately unconfigured; this is not final shop deployment.

The developer’s v0.3 report is recorded above. No cloud-executed Android installation, force-stop/relaunch, APK upgrade or real picker/save/share/print has been claimed. Mock file interfaces in widget tests prove app flow, not Android document-provider integration. Test file-backed connection restart separately from Android lifecycle. Baseline schema v1 tests still pass; Phases 4–5 do not change SQLite schema. No historical upgrade before initial v1 exists, and future schema changes require explicit migration/data-preservation tests. Workbook bounds and add-only/conflict behavior are documented in WORKBOOK_SCHEMA.md.

SDK tools 19.0 emit a nonblocking XML-version warning with current metadata. Tools 23.0 introduced an incompatible launcher and were retired outside the active SDK; the tested Java-based tools remain pinned. No application analysis warnings remain.

## Reuse and publication

See DEVELOPMENT.md and scripts/setup_cloud.sh for the working directories and tested commands. The environment configuration draft retains the tested complete installation script and updates startup instructions for the Phases 1–5 workflow. A draft save does not execute scripts, apply settings or publish a new snapshot. Review/save the draft in environment settings and publish to retain this prepared environment for future tasks. This workspace retained the pinned tools and Phase 3 checkout for this task; setup files and caches were reused. New native package dependencies were resolved using the same maintained TLS trust and Gradle proxy configuration. Live processes were not assumed to survive restoration. This does not establish a later publication or fresh-task restore of Phase 5 changes.

On a local machine with Flutter 3.47.7 and an Android target, use the existing checkout, run flutter pub get --enforce-lockfile and flutter run -d <device-id>. Await user instruction before beginning Phase 6 release hardening.

## Phase 2 review map

Changed application areas: `lib/app/` navigation/providers; `lib/features/customers/presentation/` customer CRUD, picker and history; `lib/features/orders/domain/` query/repository APIs; `lib/features/orders/data/` transactional edits and reactive queries; `lib/features/orders/application/` form drafts; `lib/features/orders/presentation/` list, filters, editor, garments and details; `lib/shared/presentation/` shared formatting/errors/discard handling. The Phase 2 version was 0.2.0+2; dependencies and schema v1 remain unchanged.

New tests: `test/phase2_repository_test.dart`, `test/order_draft_test.dart` and `test/phase2_widget_test.dart`. Updated documentation: README, DEVELOPMENT, IMPLEMENTATION_PLAN and this validation record. Phase 3 was implemented only after the subsequent developer instruction.

## Phase 3 review map

Changed: order repository API/implementation and immutable records; order draft/editor and PAYMENT details; new `lib/features/payments/application/payment_draft.dart`, `presentation/payment_editor.dart` and `presentation/payment_history.dart`; app version in `pubspec.yaml` and Settings; project/development/plan/validation docs. New tests: `payment_draft_test.dart`, `payment_repository_test.dart`, `payment_widget_test.dart` and shared `widget_helpers.dart`. The prior widget test imports the same shared scrolling helper. Schema, dependencies, customer search and measurement storage remain unchanged.

The same `phase-2-offline-orders` Git branch carries this incremental update. Use DEVELOPMENT.md’s local pull/build/install commands to produce the APK on the machine where Flutter and the phone are connected. Phase 4 was implemented after the developer reported v0.3 working and authorized continuing. Phase 5 was authorized by the subsequent developer instruction.

## Phase 4 review map

Changed: `lib/app/` providers/navigation, new `lib/features/transfer/{domain,data,application,presentation}/`, new `lib/features/settings/presentation/settings_screen.dart`, version/dependencies and resolved lockfile. New tests: `workbook_repository_test.dart`, `workbook_codec_test.dart`, `workbook_widget_test.dart`. New schema guide: `docs/WORKBOOK_SCHEMA.md`; updated specification, plan, development guide, README and this evidence record. Database v1/generated schema artifacts, app ID, previous customer/order/payment logic and main-manifest permissions are preserved.

Validation logs for this run are under `/workspace/toolchains/`: `phase4-analyze-final.log`, `phase4-tests-final.log`, `phase4-build-progress.log`, `phase4-devices.log` and `phase4-pub-get.log`. Build directories/APKs, logs and private business databases are not committed. The same `phase-2-offline-orders` branch carries the source update; build/install locally with the same signing key as the tested v0.3 app.

## Phase 5 review map

New `features/documents/{domain,data,application,presentation}/` and
`features/settings/{domain,data}/`/shop editor; document actions in both bill tabs;
new shared pure display helpers and system file actions (also reused by XLSX);
packaged/registered fonts/license; version/dependencies/lockfile; three new test
files; `docs/DOCUMENTS.md`, independent synthetic PDF inspection script, cloud
setup SDK 34 addition and updated plan/spec/README/development/validation notes.
Kotlin generated build state is ignored. SQLite/generated schema, workbook schema,
application ID and existing financial/query rules remain unchanged. Logo selection
and future theme planning are recorded without claiming launcher/theme changes.

Final logs under `/workspace/toolchains/`: `phase5-pub-get.log`,
`phase5-analyze-clean.log`, `phase5-tests-clean.log`, `phase5-build-progress.log`,
`phase5-devices.log` and `phase5-setup-recheck.log`. APKs, synthetic PDFs/raster
images, databases, native caches and logs are not committed. Changes continue on
`phase-2-offline-orders`; main is untouched. Build/install locally with the same
debug signing key used for the installed app. Phase 6 needs explicit instruction.
