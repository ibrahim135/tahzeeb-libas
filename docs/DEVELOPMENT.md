# Development guide — Phases 1 and 2

## Scope

Phase 1 introduced an Android Flutter scaffold, Material 3 navigation, Riverpod-owned database/repository providers, validated immutable domain records and transactional Drift persistence. Phase 2 adds customer/order entry and editing, customer history, duplicate review/reuse, search and filters, and per-garment measurements. The PAYMENT tab displays derived charges/balance; advance/additional payment entry and correction history remain Phase 3. XLSX and PDFs remain in their specified later phases. Current development version: 0.2.0+2.

## Toolchain

Tested SDK: Flutter stable 3.47.7 (commit abaf9c523780a608bd46686fd5e53740a07077f8), bundled Dart 3.13.5. `.flutter-version` records the pin. Java is Temurin JDK 21.0.12.1+1; the preinstalled Java runtime lacked javac. Android SDK platforms 35/36, build tools 36.0.0, NDK 28.2.13676358 and CMake 3.22.1. Generated Android defaults use AGP 9.1.0, Kotlin 2.4.0 and Gradle 9.3.1. The wrapper includes the official distribution SHA-256. Minimum Android API 24 (Android 7.0) follows Flutter's generated default; review it against the owner's phone before release. Application ID `in.tahzeeb.tahzeeb_libas` is provisional until Phase 6.

Current resolved packages include Riverpod 3.4.3, Drift 2.35.2, drift_dev 2.35.1, sqlite3 3.7.0, path_provider 2.1.6, uuid 4.6.0 and intl 0.20.3. Exact transitive resolution and package hashes are in pubspec.lock. SQLite uses sqlite3's native assets; no obsolete sqlite3_flutter_libs dependency is needed. Excel/share/PDF packages are deliberately not installed yet.

## Commands

Use an existing local Flutter 3.47.7 SDK or the prepared cloud SDK. Do not create a worktree unless explicitly requested.

```sh
# Cloud only; run the setup script if prerequisites need refreshing.
bash scripts/setup_cloud.sh
source /workspace/toolchains/env.sh
# Working directory: repository root.
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build apk --debug
flutter devices
flutter run -d <android-device-id>
```

Cloud Flutter initializes per-user `.dart-tool`; analysis also writes `.dartServer`; adb uses `.android`. These tools require supported filesystem access to their per-user cache paths in addition to redirected package/Gradle caches. If sandboxed analysis reports a read-only cache, request the specific tool cache permission; do not change HOME or disable validation. Chrome/Linux desktop doctor failures are outside this Android-only workflow.

Gradle does not automatically honor HTTPS_PROXY. Cloud setup configures its user properties from the supplied proxy hostname/port without copying authentication, and uses the machine's maintained Java trust store. Never disable TLS, artifact checksums or package hashes. `storage.googleapis.com` is required for Flutter artifacts in addition to standard package-manager network presets. No runtime internet permission is present in the main manifest; debug/profile overlays retain Flutter's development service permission.

## Data and migration rules

Database file: `tahzeeb_libas.sqlite` under application support storage. NativeDatabase runs in a background isolate. Foreign keys and a busy timeout are applied on every opened connection. Schema v1 includes customers, orders, order items, measurements, payments, shop settings and bill allocation state with relationship/search indexes. Amount/status aggregates are calculated by validated domain models, never stored as independent payment status.

Repository `createOrder` inserts the aggregate and optional new customer atomically, including dated advances and independent measurement rows. It never overwrites an existing customer through order creation. Customer updates preserve original creation timestamps and use expected-updated-time checks from editors. Phase 2 order edits check for stale changes and rebuild the proposed aggregate with the actual saved ledger inside the transaction. They preserve existing payments and reject totals below received, including when a caller supplies an empty payment list. Bill conflicts or item collisions roll back the complete edit and any newly created customer. Future payment/correction APIs must apply the same transaction rules.

Bounds: ₹1 billion maximum subtotal/amount, 1–10000 quantity per garment, at most 1000 garments per order, date years 1900–9999, bill labels 1–64 characters, measurements positive and less than 1000 inches with up to three decimals. Automatic numeric bill suggestions are below 10^12; larger historic labels remain valid text and do not advance the bounded counter. Leading-zero bill labels remain distinct visible identifiers; historic numeric labels within the counter range advance its suggestion.

Version-control generated code and schema baseline as project artifacts. After an authorized table change:

```sh
dart run build_runner build
dart run drift_dev schema dump lib/data/database/app_database.dart drift_schemas
dart run drift_dev schema generate drift_schemas test/generated
dart format lib test
flutter analyze
flutter test
```

Never replace a released schema snapshot. Increment the database version, implement an explicit migration and add data-preservation upgrade tests. There is no historical version before v1. Existing v1 opens without destructive migration; unimplemented version transitions fail rather than drop records. A narrowly scoped recursive_getters lint exclusion documents Drift's column-check DSL references; generated column constraints are tested against SQLite.

Android platform automatic backup is disabled pending deliberate user-visible XLSX backup in Phase 4. Data currently survives restarts but uninstall/device loss can remove it. Release signing is left unconfigured, preventing the generated debug key from being mistaken for production ownership.

## Phase 2 code map and workflow

- `lib/features/customers/presentation/`: customer list, search, picker, add/edit and history. New customer drafts selected during order entry remain unpersisted until the order transaction succeeds. Duplicate review offers reuse for creation and explicit confirmation for legitimate separate customers; editing retains the selected identity.
- `lib/features/orders/application/order_draft.dart`: input drafts, exact amounts, measurement section changes and independent snapshot copying. Unsaved drafts live in memory; back navigation asks before discarding. Drafts are not restored after process death.
- `lib/features/orders/domain/order_query.dart`: validated inclusive filters, sort options, summaries and edit conflicts.
- `lib/features/orders/data/drift_tailoring_repository.dart`: atomic create/edit, expected-version checks, escaped customer/bill/phone search, independent charge/payment aggregation and reactive list updates. Lists load 100 orders at a time, up to 10000; narrow filters for larger result sets. Customer measurement-copy selection considers the latest 1000 orders.
- `lib/features/orders/presentation/`: order lists, filters, editor, garment inputs and separate PAYMENT/MEASUREMENTS views. Numeric bill suggestion remains editable for historic bills. A selected garment type suggests measurement sections; populated sections require confirmation before clearing. Copying saved measurements copies fitting notes as well.
- `lib/shared/presentation/common.dart`: INR/date display, local error messages, discard prompts and shared inputs. `lib/app/providers.dart` owns dependencies and reactive queries; the navigation shell retains search/filter state between tabs.

No database tables or dependency versions changed in Phase 2; schema remains v1. Tests in `phase2_repository_test.dart`, `order_draft_test.dart` and `phase2_widget_test.dart` cover financial/stale guards, rollback, search/filter/sort, snapshot isolation and the real input/navigation flows. Existing persistence and migration-baseline tests remain active.

Before shop deployment, finish payment entry, user-controlled backup and release/device validation. This development APK has no export or recovery UI yet.
