# Tahzeeb Libas

Android-first offline tailoring shop app. Phases 1–5 are implemented: durable SQLite records, customer management, order entry/editing, garment measurements, search/filters, advance and additional payments, audited payment corrections, and versioned Excel backup/export/import with safe previews, shop settings and offline A4 payment receipts/warehouse slips. Release hardening follows in Phase 6.

- [Project specification](docs/PROJECT_SPEC.md)
- [Implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [PDF documents and phone checks](docs/DOCUMENTS.md)
- [Excel schema and backup rules](docs/WORKBOOK_SCHEMA.md)
- [Development commands and architecture](docs/DEVELOPMENT.md)
- [Environment and validation evidence](docs/ENVIRONMENT_STATUS.md)

Use Flutter 3.47.7. Run `flutter pub get --enforce-lockfile`, `flutter analyze`, `flutter test` and `flutter build apk --debug`. See the development guide for cloud SDK activation and Android device checks.

For received amounts, enter an optional advance when creating an order. On a saved bill, open PAYMENT → Add received payment. Each payment has its original date, optional method and notes. Correct payment retains the old entry with a required reason and offers replacement or voiding; it does not perform a refund.

Version 0.4.0 adds Settings → Export Excel backup, Import Excel workbook and Blank Excel template. Prepared files can be saved or shared through Android. Imports preserve original IDs/history, flag row errors and duplicates, block changed existing records, and commit all changes atomically. Keep backups outside the phone; uninstalling or clearing app data removes local records.

Version 0.5.0 adds Settings → Shop details, PAYMENT → Payment receipt and
MEASUREMENTS → Warehouse measurement slip. Both offer preview, save, share,
Android printing and Shop copy. Warehouse slips exclude financial fields.
English fonts and INR support are bundled for offline use. Native Android
preview/file/print checks are still needed; see the document guide.

The supplied gold-on-black TL artwork is the selected app logo. Its original
PNG/JPG file is still needed in the workspace for faithful launcher-icon assets.
Theme customization is planned after release hardening, with no current theme
change.
