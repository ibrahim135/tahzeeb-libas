# Tahzeeb Libas

Android-first offline tailoring shop app. Phases 1–3 are implemented: durable SQLite records, customer management, order entry/editing, garment measurements, search/filters, advance and additional payments, and audited payment corrections. Excel transfer, PDFs and release hardening follow in later phases.

- [Project specification](docs/PROJECT_SPEC.md)
- [Implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [Development commands and architecture](docs/DEVELOPMENT.md)
- [Environment and validation evidence](docs/ENVIRONMENT_STATUS.md)

Use Flutter 3.47.7. Run `flutter pub get --enforce-lockfile`, `flutter analyze`, `flutter test` and `flutter build apk --debug`. See the development guide for cloud SDK activation and Android device checks.

For received amounts, enter an optional advance when creating an order. On a saved bill, open PAYMENT → Add received payment. Each payment has its original date, optional method and notes. Correct payment retains the old entry with a required reason and offers replacement or voiding; it does not perform a refund.
