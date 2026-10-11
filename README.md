# Tahzeeb Libas

Android-first offline tailoring shop app. Phases 1–4 are implemented: durable SQLite records, customer management, order entry/editing, garment measurements, search/filters, advance and additional payments, audited payment corrections, and versioned Excel backup/export/import with safe previews. PDFs and release hardening follow in later phases.

- [Project specification](docs/PROJECT_SPEC.md)
- [Implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [Excel schema and backup rules](docs/WORKBOOK_SCHEMA.md)
- [Development commands and architecture](docs/DEVELOPMENT.md)
- [Environment and validation evidence](docs/ENVIRONMENT_STATUS.md)

Use Flutter 3.47.7. Run `flutter pub get --enforce-lockfile`, `flutter analyze`, `flutter test` and `flutter build apk --debug`. See the development guide for cloud SDK activation and Android device checks.

For received amounts, enter an optional advance when creating an order. On a saved bill, open PAYMENT → Add received payment. Each payment has its original date, optional method and notes. Correct payment retains the old entry with a required reason and offers replacement or voiding; it does not perform a refund.

Version 0.4.0 adds Settings → Export Excel backup, Import Excel workbook and Blank Excel template. Prepared files can be saved or shared through Android. Imports preserve original IDs/history, flag row errors and duplicates, block changed existing records, and commit all changes atomically. Keep backups outside the phone; uninstalling or clearing app data removes local records.
