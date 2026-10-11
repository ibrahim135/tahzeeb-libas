import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/presentation/common.dart';
import '../domain/workbook.dart';

class ImportPreviewScreen extends ConsumerStatefulWidget {
  final ImportPreview preview;
  const ImportPreviewScreen({super.key, required this.preview});
  @override
  ConsumerState<ImportPreviewScreen> createState() =>
      _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends ConsumerState<ImportPreviewScreen> {
  bool busy = false,
      acceptDuplicates = false,
      replaceSettings = false,
      finished = false;
  String? message, error;
  Future<void> _commit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await ref
          .read(workbookRepositoryProvider)
          .commit(
            widget.preview,
            acceptSimilarCustomers: acceptDuplicates,
            replaceShopSettings: replaceSettings,
          );
      if (!mounted) return;
      ref.invalidate(orderProvider);
      ref.invalidate(customerProvider);
      setState(() {
        finished = true;
        message =
            '${result.addedRecords} records added. Existing records stayed unchanged.${result.settingsUpdated ? ' Shop details replaced as confirmed.' : ''}${result.counterUpdated ? ' Bill counter advanced.' : ''}';
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = e is StateError ? e.message : friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final ready =
        preview.valid &&
        (preview.duplicateWarnings.isEmpty || acceptDuplicates) &&
        (!preview.settingsDiffer || replaceSettings);
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Excel import preview')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
            children: [
              Text(
                preview.valid
                    ? '${preview.newRecords} new · ${preview.existingRecords} existing records'
                    : '${preview.errors.length} errors or conflicts',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                'No records change until you apply the import. Any invalid or conflicting row blocks the entire file. Existing bills must include their complete original history.',
              ),
              const SizedBox(height: 16),
              for (final name in preview.newCounts.keys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '$name: ${preview.newCounts[name]} new, ${preview.existingCounts[name]} existing',
                  ),
                ),
              if (preview.errors.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Correct these rows in Excel and import again:'),
                for (final issue in preview.errors.take(200))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ErrorNotice(issue.toString()),
                  ),
                if (preview.errors.length > 200)
                  const Text(
                    'Showing the first 200 errors. Fix these and preview again to see remaining issues.',
                  ),
              ],
              if (preview.duplicateWarnings.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  '${preview.duplicateWarnings.length} possible duplicate customers',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final issue in preview.duplicateWarnings.take(200))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_customerLabel(issue)),
                    subtitle: Text(issue.toString()),
                  ),
                if (preview.duplicateWarnings.length > 200)
                  const Text(
                    'Review all indicated Customers rows in Excel before confirming. Showing the first 200 matches.',
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: acceptDuplicates,
                  onChanged: busy || finished
                      ? null
                      : (value) => setState(() => acceptDuplicates = value!),
                  title: const Text(
                    'I reviewed the matching customers. These new rows represent separate customers.',
                  ),
                ),
              ],
              if (preview.settingsDiffer) ...[
                const SizedBox(height: 16),
                Text(
                  'Current shop details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final field in [
                  'name',
                  'address',
                  'contact',
                  'receipt_notes',
                  'updated_at',
                ])
                  Text(
                    '$field: ${preview.currentShopSettings?.values[field] ?? '—'}',
                  ),
                const SizedBox(height: 12),
                Text(
                  'Imported shop details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final field in [
                  'name',
                  'address',
                  'contact',
                  'receipt_notes',
                  'updated_at',
                ])
                  Text(
                    '$field: ${preview.workbook.rows('ShopSettings').single.values[field] ?? '—'}',
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: replaceSettings,
                  onChanged: busy || finished
                      ? null
                      : (value) => setState(() => replaceSettings = value!),
                  title: const Text(
                    'Replace the current shop details with these imported details.',
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (!finished)
                FilledButton(
                  onPressed: ready && !busy ? _commit : null,
                  child: const Text('Apply import'),
                ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: busy ? null : () => Navigator.of(context).pop(),
                child: Text(finished ? 'Done' : 'Cancel without changes'),
              ),
              if (busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text('Importing all records safely…'),
              ],
              if (message != null) ...[
                const SizedBox(height: 16),
                Text(message!),
              ],
              if (error != null) ...[
                const SizedBox(height: 16),
                ErrorNotice(error!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _customerLabel(WorkbookIssue issue) {
    final row = widget.preview.workbook
        .rows('Customers')
        .where((r) => r.line == issue.row)
        .firstOrNull;
    return row == null
        ? 'Customers row ${issue.row}'
        : 'Row ${issue.row}: ${row.text('name')} · ${row.optional('mobile') ?? 'No phone'}';
  }
}
