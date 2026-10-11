# Offline Excel workbook — schema v1

Version 0.4.0 exports and imports `.xlsx` entirely on the device. Workbook schema **1** and SQLite schema **1** are independent versions. Export reads one consistent database transaction. There are seven required sheets, with exactly the headers below. Header order and record order may change; header names and sheet names are case-sensitive. Unknown sheets are rejected except the optional, ignored `Examples` sheet.

## Cell types and shared rules

- UUID IDs/references, phones, bills, measurements, dates and timestamps are **Text cells**. Format the column as Text before entering values. Numeric phone/bill/ID cells are rejected rather than guessing lost leading zeroes. References match the exact ID text.
- Integer columns accept whole-number Excel cells or digit-only text. Floating-point cells, even with currency formatting, are rejected. All `_paise` fields are integer INR paise: `10025` means ₹100.25. No derived totals or editable payment status are imported.
- Business dates are ISO text `YYYY-MM-DD`, years 1900–9999. Timestamps are UTC ISO text `YYYY-MM-DDTHH:mm:ss[.ffffff]Z`, with valid calendar/time components. Export preserves original persisted timestamp values. `updated_at` cannot precede `created_at`.
- Optional fields use genuinely empty cells for null. An explicit empty text cell retains an empty string; it is distinct from an absent cell. Required values cannot be empty. Text is limited to Excel's 32,767 characters per cell. Unicode and multiline notes are preserved.
- Formula cells are rejected, including formulas with cached numeric or shared-string results. Formulas are never evaluated. Export writes formula-like strings beginning with `=`, `+`, `-` or `@` as literal text. Do not put formulas in the template.
- Entity IDs are UUIDs, separate from visible bills. Generate fresh IDs for new records and use those IDs consistently in related sheets. Reusing an exported ID with changed content is a conflict, not an editing mechanism.

## Customers

```text
id,name,mobile,alternate_mobile,address,notes,created_at,updated_at
```

`id`, `name`, `created_at`, `updated_at` are required text. Other fields are optional text. Phones are optional and may include formatting or leading zeroes. Search keys are regenerated from name/phones; these are the only omitted customer columns. Names are required after trimming. No uniqueness rule on name or phone: new rows matching a normalized name, first name of at least three characters, or either normalized phone are flagged for explicit duplicate review, both against local customers and other workbook rows.

## Orders

```text
id,bill_number,customer_id,order_date,delivery_date,status,discount_paise,notes,created_at,updated_at
```

Only `notes` is optional. `discount_paise` is an integer; the others are text. `customer_id` must reference a workbook customer or a customer already saved locally. Bill text is trimmed for its normalized case-insensitive uniqueness key; leading zeroes remain intact. Labels have 1–64 characters. Delivery must be on/after order date. Status is exactly one of `new`, `in_progress`, `ready`, `delivered`, `cancelled`.

Every workbook order must include its complete garment, measurement and payment history. At least one garment is required, up to 1,000 garments. Subtotal is sum(quantity × rate), total is subtotal − discount, and paid is the sum of nonvoided payments. Subtotal and individual monetary values are bounded at `100000000000` paise. Discount cannot exceed subtotal; active payments cannot exceed total. Delivery and payment status remain independent.

## OrderItems

```text
id,order_id,position,garment_type,variant,quantity,unit_price_paise,description,measurement_config,measurement_unit,fitting_notes,created_at,updated_at
```

`variant`, `description`, `fitting_notes` are optional text. `position`, `quantity`, `unit_price_paise` are integers; other fields are required text. `order_id` must identify a workbook Orders row, even if it exists locally. Positions must be unique and consecutive `0,1,...` within each order, preserving display order. Quantity is 1–10,000. Rate is nonnegative integer paise; quantity × rate must fit the monetary bound.

| garment_type | Allowed variant |
| --- | --- |
| sherwani | sherwani, three_piece (required) |
| suit | two_piece, three_piece, four_piece (required) |
| jothpuri, sadri, pant, shirt, kurta, payjama, thobe, joota, pagdi | blank |

`measurement_config` is `upper`, `lower`, `both` or `none`; every type may use any configuration. `measurement_unit` is `inches`. Joota/Pagdi can use `none`, with size/details in description or fitting notes. Measurements belong to the item ID and never change another order's snapshots.

## Measurements

```text
item_id,field_key,value_decimal
```

All fields are required text. Composite key `(item_id,field_key)` is unique. `item_id` must reference a workbook garment. Omit a row when its measurement is unknown. Values are positive exact decimals less than 1,000 inches with up to three fractional places; no unit conversion is performed. Keys must belong to the item's enabled sections:

- Upper: `upper_length`, `upper_shoulder`, `upper_sleeves`, `upper_arms`, `upper_cuffs`, `upper_chest`, `upper_stomach`, `upper_hips`, `upper_neck`.
- Lower: `lower_length`, `lower_waist`, `lower_hips`, `lower_thighs`, `lower_knees`, `lower_bottom`, `lower_allround`, `lower_inside`.

## Payments

```text
id,order_id,amount_paise,payment_date,method,notes,created_at,updated_at,voided_at,void_reason,replaces_payment_id
```

`amount_paise` is a positive integer. `method`, `notes`, `voided_at`, `void_reason`, `replaces_payment_id` are optional text; other fields are required text. `order_id` must identify a workbook order. Payment date must be between its order date and today's device date, including historic records. Creation timestamps remain separate from the original payment date.

Both `voided_at` and a nonblank `void_reason` must be present, or both absent. Void time cannot precede original creation. Only nonvoided payments contribute to received amounts. A replacement references a different voided payment from the same workbook order. References are resolved after all payment rows are inserted, so row order does not matter. Each corrected payment has at most one replacement, and correction references cannot form a cycle. Export retains every original entry, void reason/time and replacement link. Voiding corrects an entry; it does not execute a refund.

## ShopSettings

```text
id,name,address,contact,receipt_notes,updated_at
```

Zero or one row. `id` is integer `1`; `name` and `updated_at` are required text. Others are optional text. Export always includes the singleton, including its original timestamp. A blank sheet retains current shop details. If any imported field differs, the preview displays current and imported details and requires **Replace the current shop details** confirmation, including on a fresh installation with seeded defaults. This is the only explicitly confirmed replacement; customer/order/item/measurement/payment records are always add-only.

## Metadata

```text
key,value
```

Both columns are text. Exactly one row for each key; unknown or duplicate keys are rejected:

| key | value |
| --- | --- |
| workbook_schema_version | 1 |
| source_database_schema_version | 1 |
| exported_at | Valid UTC ISO timestamp |
| currency | INR |
| measurement_unit | inches |
| next_bill_number | Digit-only text, 1 through 1000000000000 |

The bill counter becomes the maximum of the existing counter, imported counter and the next number above imported/local historic numeric bills in the supported range, skipping occupied exact numeric labels. It never decreases. Larger historic bill labels remain text and do not advance the bounded counter. An identical repeated backup does not update counters or timestamps.

## Preview, conflicts and commit

Preview performs no writes. It shows new/existing candidate record counts by sheet, row/field diagnostics and possible duplicate customers. Identical IDs and persisted values, independent of row order, are unchanged. Changed content for an existing ID or a different ID using an occupied normalized bill blocks the whole file. Existing orders also compare their entire set of items, measurement values and payment records; omissions or additions are conflicts. Imports cannot append payments/items to an existing bill. Use the normal order/payment UI for edits and corrections.

Commit opens one database transaction, reads the live records and repeats validation in a worker isolate. If local records or the bill counter changed since preview, it asks for a new preview instead of applying an unreviewed decision. Reviewed similar customers require explicit confirmation. Shop replacement requires its separate confirmation. All new rows, replacement links, confirmed shop settings and counter changes commit together or roll back together. Cancelling, invalid data, conflicts and late database failures never partially import records.

## Template and examples

Settings → **Blank Excel template** prepares all seven sheets with correct headers. Business sheets, including ShopSettings, are empty. Metadata uses current schema constants, current export time and counter `1`. The separate **Examples** sheet contains linked customer/order/item/measurement/advance rows, cell-format instructions and stable identifiers. It is always ignored on import. Copy only intended rows into their matching sheets, replace example details, use fresh UUIDs and retain references. A blank template imports zero business records.

## Resource limits and files

Files are at most **8 MiB**, ZIP expansion at most **32 MiB**, each member at most **8 MiB**, at most 128 archive members and eight worksheets. Each sheet has at most 20,000 data rows and 32 physical columns; total nonheader rows across worksheets are capped at 100,000. ZIP64/multidisk/encrypted archives, macros/external-link members, duplicate archive names, XML DTD/entity declarations, duplicate/out-of-range cell positions and invalid checksums are rejected. Streaming decompression enforces actual expanded-byte limits even when an archive lies about its size. Validation rejects oversized sparse row/column addresses before Excel allocates a grid. Export uses the same bounds; it fails explicitly instead of silently omitting records. Split larger sets into complete orders and their related rows, or request a future larger-backup format.

Encoding, archive parsing and import policy run in worker isolates. SQLite uses its existing background connection. Android's document picker/save dialog and share sheet handle user destinations without broad storage permissions. Saving is separate from preparing a file; a prepared file discarded without saving/sharing is not a backup. Recent app-private share copies expire after seven days and are cleaned on the next share. An exported workbook contains personal data: use trusted destinations and keep regular copies outside the phone. XLSX is a portable record backup, not an automatic cloud sync.
