import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/presentation/common.dart';
import 'shop_editor.dart';
import '../../transfer/presentation/export_screen.dart';
import '../../transfer/presentation/import_preview_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? working, error;

  Future<void> _export({bool template = false}) async {
    setState(() {
      working = template ? 'Preparing template…' : 'Preparing complete backup…';
      error = null;
    });
    try {
      final transfer = ref.read(workbookTransferProvider);
      final bytes = await (template ? transfer.template() : transfer.export());
      if (!mounted) return;
      setState(() => working = null);
      final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        RegExp('[^0-9]'),
        '',
      );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ExportScreen(
            bytes: bytes,
            fileName: template
                ? 'tahzeeb_libas_template_v1.xlsx'
                : 'tahzeeb_libas_backup_$stamp.xlsx',
            template: template,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          working = null;
          error = e is FormatException ? e.message : friendlyError(e);
        });
      }
    }
  }

  Future<void> _import() async {
    setState(() {
      working = 'Choosing and checking workbook…';
      error = null;
    });
    try {
      final preview = await ref.read(workbookTransferProvider).pickAndPreview();
      if (!mounted) return;
      setState(() => working = null);
      if (preview != null) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ImportPreviewScreen(preview: preview),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          working = null;
          error = e is FormatException ? e.message : friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: working == null,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
      children: [
        ref
            .watch(shopSettingsProvider)
            .when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => ErrorNotice(
                friendlyError(e),
                onRetry: () => ref.invalidate(shopSettingsProvider),
              ),
              data: (shop) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(shop.name),
                subtitle: const Text('Shop details and receipt notes'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: working == null
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ShopEditor(initial: shop),
                        ),
                      )
                    : null,
              ),
            ),
        const SizedBox(height: 16),
        Text(
          'Offline storage',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Records stay on this device. Uninstalling the app, clearing app data or losing the phone can remove your records.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Export regularly and keep a copy outside this phone. An Excel backup includes customers, all bills, garment measurements, fitting notes and complete payment history. Keep it in a trusted location because it contains personal information.',
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: working == null ? _export : null,
          icon: const Icon(Icons.file_upload_outlined),
          label: const Text('Export Excel backup'),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: working == null ? _import : null,
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('Import Excel workbook'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: working == null ? () => _export(template: true) : null,
          icon: const Icon(Icons.table_chart_outlined),
          label: const Text('Blank Excel template'),
        ),
        if (working != null) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(working!),
        ],
        if (error != null) ...[const SizedBox(height: 16), ErrorNotice(error!)],
        const SizedBox(height: 20),
        const Text(
          'Restore: choose an exported .xlsx, review the preview, then apply the import. Matching records stay unchanged. Changed existing IDs or bill numbers block the whole import. Cancelling the preview changes nothing.',
        ),
        const SizedBox(height: 12),
        const Text(
          'For adding historic records, start with the blank template and follow the separate Examples sheet. The app ignores example rows. Supported files: up to 8 MiB, 20,000 data rows per sheet and 100,000 total. Split larger sets into complete orders with their related rows.',
        ),
        const SizedBox(height: 24),
        const Text('Development version · 0.5.0'),
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Tahzeeb Libas',
            applicationVersion: '0.5.0',
          ),
          child: const Text('Open-source licences'),
        ),
      ],
    ),
  );
}
