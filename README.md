# Tahzeeb Libas

Android-first offline tailoring shop app. Phases 1 and 2 are implemented: durable SQLite records, customer management, order entry/editing, garment measurements, search and filters. Payment entry, Excel transfer, PDFs and release hardening follow in later phases.

- [Project specification](docs/PROJECT_SPEC.md)
- [Implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [Development commands and architecture](docs/DEVELOPMENT.md)
- [Environment and validation evidence](docs/ENVIRONMENT_STATUS.md)

Use Flutter 3.47.7. Run `flutter pub get --enforce-lockfile`, `flutter analyze`, `flutter test` and `flutter build apk --debug`. See the development guide for cloud SDK activation and Android device checks.
