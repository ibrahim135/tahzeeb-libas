# Tahzeeb Libas — project specification

Status: agreed baseline; Phases 1 and 2 are implemented. Changes to these defaults can be agreed before their implementation milestone. See IMPLEMENTATION_PLAN.md for the current stopping point.

## Purpose and boundaries

An Android-first, single-device Flutter app replaces a tailoring shop's bill book. Customer history, orders, garment-specific measurements, payments, XLSX backups and two PDF formats work offline. No backend, login, cloud services, inventory, WhatsApp automation, Bluetooth printer integration or cloth/material calculation is included. Runtime internet access is not required. Development dependency downloads are separate from app connectivity.

The final deliverable is an installable Android APK with tested durable storage. Production release signing requires an owner-controlled signing key; never commit signing secrets.

## Business defaults and decisions

These defaults allow planning without blocking on preferences:

- Currency is INR. Monetary input accepts at most two decimal places and is parsed directly into integer paise. Never use floating-point arithmetic for money. Quantity is a positive whole number; optional cut/description is text. Fractional cuts are recorded as descriptions, not used as quantities. Confirm fractional billing before the order milestone if needed.
- Discount is a fixed amount, from zero through subtotal. Payment entries must be positive; advance is an ordinary dated payment. Zero-total orders are Paid with zero balance. Otherwise zero received is Pending, positive received below total is Partially paid, and exact total is Paid.
- Overpayment and edits reducing total below received are blocked. Payment corrections require an explicit correction workflow: retain an original entry, void it with a reason and timestamp, and optionally insert a replacement in the same transaction. Only active entries contribute to received totals. No refund workflow in this version; a real refund requirement needs a business decision before implementation.
- Cancellation changes delivery status only; it does not erase payments or imply a refund. Delivered orders may retain a balance. Customers/orders are not hard-deleted in this version. Incorrect orders can be cancelled, preserving history.
- Bill numbers are trimmed, nonempty text and globally unique using a case-insensitive normalized key. Historic values and leading zeroes are preserved for display. Automatic suggestions use a transactional numeric counter, skip occupied numeric values, and retain a uniqueness constraint to handle conflicts. Historic numeric entries advance the counter; nonnumeric entries do not. Bill sorting is deterministic lexical sorting by normalized key; numeric ordering can be added if requested. Bill changes are allowed only through explicit editing with uniqueness validation.
- Business dates are date-only ISO `YYYY-MM-DD` values and display as DD/MM/YYYY. Timestamps are UTC instants. Order date cannot follow delivery date; historic dates are allowed. Payments cannot predate their order and cannot be in the future. Confirm if the shop accepts pre-order deposits before payment implementation.
- Customer name is required; phone is optional text. Preserve entered formatting, with a separate digits-based search key. No numeric conversion. Matching phone or similar name prompts reuse/review; legitimate duplicates remain possible after explicit confirmation. No uniqueness constraint on name or phone.
- Measurements default to inches, use exact decimal strings with at most three fractional places, and must be positive when present. Blank means absent, never zero. No unit conversion is performed. Measurement sections can be manually changed; disabling a populated section requires confirmation before clearing its values. Copying prior measurements creates new item-owned snapshots.
- Measurement defaults: Sherwani, Suit and Jothpuri use both sections; Sadri, Shirt, Kurta and Thobe use upper; Pant and Payjama use lower; Joota and Pagdi use neither. All can be overridden.
- PDFs use A4 initially, with clear multiline wrapping and page breaks. Shop copies use the same two layouts. Warehouse slips exclude all monetary values. Multiple copies use Android's print dialog.
- Import defaults to add-only. Identical existing IDs are unchanged; differing content for an existing ID is a conflict and blocks commit. Never merge or overwrite silently. Different IDs with an occupied bill number are conflicts; possible duplicate customers require explicit review. Entire validated imports commit atomically or not at all.

Important owner input before the affected milestone: refund needs, fractional billing, pre-order deposits, preferred bill format, real sample bills and receipt paper size. Before release: shop identity, app identifier, supported phone/Android version, release-signing ownership and backup destination. These do not block specification work.

## Catalog and measurements

Stable catalog identifiers and display terminology:

| Type ID | Display | Variant IDs / labels |
| --- | --- | --- |
| sherwani | Sherwani | sherwani / Sherwani; three_piece / 3-piece |
| suit | Suit | two_piece / 2-piece; three_piece / 3-piece; four_piece / 4-piece |
| jothpuri | Jothpuri | none |
| sadri | Sadri | none |
| pant | Pant | none |
| shirt | Shirt | none |
| kurta | Kurta | none |
| payjama | Payjama | none |
| thobe | Thobe | none |
| joota | Joota | none |
| pagdi | Pagdi | none |

Variants are validated within their type. Every garment has independent quantity, price, description, configuration, measurements and fitting notes.

Upper keys: `upper_length`, `upper_shoulder`, `upper_sleeves`, `upper_arms`, `upper_cuffs`, `upper_chest`, `upper_stomach`, `upper_hips`, `upper_neck`.

Lower keys: `lower_length`, `lower_waist`, `lower_hips`, `lower_thighs`, `lower_knees`, `lower_bottom`, `lower_allround`, `lower_inside`.

Configuration is `upper`, `lower`, `both` or `none`. Show only enabled sections, with an explicit selector to change them. All values are optional. Below each garment provide multiline fitting notes for alterations, fitting preference, cuts and stitching instructions; footwear/headwear size details use description/notes.

## Architecture

Feature-oriented Flutter with Material 3 and Riverpod. UI consumes application controllers and immutable models; controllers call repositories. Repository implementations own Drift queries and transactions. Workbook/PDF services consume validated models and never write directly around repository rules. One SQLite database in persistent application documents/support storage; never cache storage. Enable foreign keys on every connection.

Use a simple explicit layering rather than generic enterprise abstractions. Keep payment arithmetic, bill allocation, validation and query/filter definitions outside widgets. Database and file work must not freeze the UI. Dependency versions are selected only after the installed Flutter/Dart and Android toolchains are verified; commit the resolved application lockfile during implementation.

## Database schema (initial migration target)

All business entity IDs are UUIDs independent of visible bill numbers. Foreign keys enforce relationships. Required indexes include normalized phone/name, bill key, order customer, delivery/date/status and payment order. Totals and payment status are derived, not independently editable columns.

| Table | Fields and constraints |
| --- | --- |
| customers | id PK; name; normalized_name; mobile TEXT nullable; mobile_search nullable; alternate_mobile nullable; alternate_mobile_search nullable; address nullable; notes nullable; created_at; updated_at |
| orders | id PK; bill_number; bill_key UNIQUE; customer_id FK; order_date; delivery_date; status enum (new/in_progress/ready/delivered/cancelled); discount_paise INTEGER >= 0; notes nullable; created_at; updated_at |
| order_items | id PK; order_id FK; position INTEGER; garment_type; variant nullable; quantity INTEGER > 0; unit_price_paise INTEGER >= 0; description nullable; measurement_config enum; measurement_unit = inches; fitting_notes nullable; created_at; updated_at; UNIQUE(order_id, position) |
| measurements | item_id FK; field_key; value_decimal TEXT; PRIMARY KEY(item_id, field_key) |
| payments | id PK; order_id FK; amount_paise INTEGER > 0; payment_date; method nullable; notes nullable; created_at; updated_at; voided_at nullable; void_reason nullable; replaces_payment_id nullable FK |
| shop_settings | singleton key; name; address nullable; contact nullable; receipt_notes nullable; updated_at |
| app_state | singleton key; next_bill_number INTEGER; timestamps as needed |

SQLite schema versioning uses Drift migrations with generated schema snapshots and migration tests. Database schema version and workbook schema version are independent. Cross-row financial validation is enforced in the same transaction as each write. Queries calculate subtotal, net total and active payment sum without joining item/payment rows into multiplied totals. Limit inputs to documented bounds supported by SQLite integers and reject overflow before multiplication/summation.

Order save (customer if new, order, items, measurements and advance), payment insertion/correction, measurement edits and workbook import are transactional. Recheck balance and bill uniqueness within the transaction. Historical item values never reference a mutable shared measurement profile.

## Screens and interaction

- Home / Orders: search by name, either phone and bill; add order; list customer/phone, bill, garment summary, dates, payment status/balance and delivery status. Empty/error/loading states are explicit.
- Filters: inclusive order-date and delivery-date ranges, Pending/Partially paid/Paid, balance greater than zero and delivery status. Sort newest/oldest, delivery ascending/descending, balance ascending/descending, total ascending/descending and bill; use stable ID tie breakers.
- Create/Edit Order: select/reuse/create customer, dates, one or more garments, quantities/prices, discount, advance with date, optional measurements and fitting notes. Show calculated totals. Preserve draft during navigation and confirm discarding unsaved changes. Saving is disabled during commit to prevent duplicate taps.
- Details: PAYMENT tab shows charges, dates, totals, full payment history including visibly voided corrections, add payment and receipt actions. MEASUREMENTS tab shows each garment's sections/notes, editing and warehouse slip actions. Both share one bill number.
- Customers: search, add/edit and complete order history. Warn about likely duplicates before creation without blocking legitimate matches.
- Settings: shop identity, XLSX export/import/template, backup/restore explanation and application version. Import displays row errors, new/existing/conflicting counts and a confirmation action. Cancelling preview writes nothing.

Large touch targets, phone/numeric keyboards, INR formatting and compact-phone layouts are required. Dates use date pickers plus visible DD/MM/YYYY. No sensitive details in diagnostic logs. No broad storage permission; use system picker/save/share integrations and app-private persistent storage.

## XLSX schema v1

Document exact headers/types in `docs/WORKBOOK_SCHEMA.md` when implemented. Sheets are Customers, Orders, OrderItems, Measurements, Payments, ShopSettings and Metadata. Customer/order/item/payment fields above are exported including correction records and timestamps; omit only reproducible search keys. Measurements contain item_id, field_key and value_decimal. ShopSettings preserves shop identity. Metadata includes workbook_schema_version, source_database_schema_version, exported_at, currency, measurement_unit and next_bill_number. Restore counter must be at least both the imported counter and next available local number.

IDs, phones and bill numbers are explicit text cells to preserve leading zeroes. Money is integer paise with `_paise` headers. Date-only and UTC timestamps are ISO text. Optional values use blank cells. Never include derived totals as authoritative inputs. Schema-version checks reject unsupported versions rather than guessing.

Parse sheet/header presence, types, date formats, enums, UUIDs, duplicate IDs, foreign references, item positions, measurements and all financial/date invariants before preview. Reject formula cells in imported data; never evaluate formulas. Treat formula-like strings as literal text when exporting. Bound file size, row count and expanded workbook processing to avoid resource exhaustion; define tested limits during implementation.

Re-import comparison uses canonical persisted fields, including IDs/timestamps, independent of row order. Preview is read-only and commit revalidates against current database state. Invalid/conflicting data blocks the whole commit and reports sheet, row, field and actionable reason without dumping customer data. Identical imports produce zero changes. Existing and new references may coexist. A blank template has required headers and separate documented examples; example records must not accidentally be imported as shop records.

Export reads a consistent transactional snapshot. Save/share complete files only after successful encoding. Explain that an export is a portable backup and that uninstall/device loss can destroy unexported data; encourage regular copies outside the device. XLSX contains personal information; users choose trusted storage/share destinations.

## PDF outputs

Payment receipt: shop details, bill, customer/phone, order/delivery dates, descriptions, quantities, rates, discount, total, received, balance and shop notes. Warehouse slip: bill, customer identification, delivery date, garment descriptions/quantities, section-labelled measurements and fitting instructions, with no payment amounts. Embed fonts supporting INR and required customer text. Provide preview/save/share/print; test long content, multiple pages and missing optional data.

## Quality and release acceptance

Meaningful tests cover persistence, multiple items, measurement isolation/configuration, exact monetary calculations, partial/full payments and rejected overpayments/under-total edits; search/filter/sort boundaries; XLSX full-field round trips, idempotency, conflicting/invalid rows, formulas and transaction rollback; migrations; closing/reopening persistent databases. Widget tests cover critical entry and error flows. Android integration checks cover force-stop/relaunch, files, PDF preview/share/print and compact screens.

Run `flutter analyze` and `flutter test` at each applicable milestone and build an APK before release. Report actual execution, skips and blockers separately. Verify a real install/run on an Android target; unit tests or APK compilation alone do not prove device behavior. Never call a phase complete with compilation errors, critical warnings or failing required tests.

## Initial inspection evidence

Repository `main` initially contains only README.md; there is no Flutter project, package manifest, lockfile, CI or tests. Flutter, Dart and adb are not on PATH; Java is available. No SDK compatibility or Flutter validation has been claimed. Phase 1 must install/verify a stable Flutter toolchain and Android prerequisites before selecting versions. This planning task intentionally stops before app scaffolding, dependency installation and implementation.
