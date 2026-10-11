import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../app/providers.dart';
import '../../../shared/presentation/common.dart';
import '../domain/document.dart';

class DocumentScreen extends ConsumerStatefulWidget {
  final String orderId;
  final DocumentKind kind;
  const DocumentScreen({super.key, required this.orderId, required this.kind});
  @override
  ConsumerState<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends ConsumerState<DocumentScreen> {
  BillDocumentSnapshot? snapshot;
  Uint8List? bytes;
  bool shopCopy = false, busy = false, generating = true;
  String? error, status;
  String get fileName =>
      'tahzeeb_${widget.kind.name}_${widget.orderId}_${shopCopy ? 'shop' : 'original'}.pdf';
  @override
  void initState() {
    super.initState();
    Future.microtask(generate);
  }

  Future<void> generate({bool refresh = false}) async {
    setState(() {
      generating = true;
      bytes = null;
      error = null;
      status = null;
    });
    try {
      if (refresh || snapshot == null) {
        snapshot = await ref
            .read(documentRepositoryProvider)
            .load(widget.orderId);
      }
      final pdf = await ref.read(documentPdfProvider.future);
      final result = await pdf.build(
        snapshot!.content(widget.kind),
        shopCopy: shopCopy,
      );
      if (mounted) {
        setState(() {
          bytes = result;
          generating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          generating = false;
          error = e is FormatException
              ? e.message
              : 'Could not generate the PDF. Retry from the saved bill.';
        });
      }
    }
  }

  Future<void> perform(String action) async {
    if (bytes == null || busy || generating) return;
    setState(() {
      busy = true;
      status = null;
      error = null;
    });
    try {
      final actions = ref.read(documentActionsProvider);
      final completed = await switch (action) {
        'Save' => actions.save(bytes!, fileName),
        'Share' => actions.share(bytes!, fileName),
        _ => actions.print(bytes!, fileName),
      };
      if (mounted) {
        setState(() {
          busy = false;
          status = !completed
              ? '$action cancelled.'
              : switch (action) {
                  'Save' => 'PDF saved.',
                  'Share' => 'Share sheet opened. Check the receiving app.',
                  _ => 'Print job sent. Check the printer.',
                };
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error =
              'Could not ${action.toLowerCase()} the PDF. Check the destination or print service, then retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && !generating,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.kind.label),
        actions: [
          IconButton(
            tooltip: 'Refresh from saved bill',
            onPressed: busy || generating
                ? null
                : () => generate(refresh: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('Shop copy'),
              value: shopCopy,
              onChanged: busy || generating
                  ? null
                  : (v) {
                      setState(() => shopCopy = v);
                      generate();
                    },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'A4 · Saved bill snapshot. Choose copies in the Android print dialog.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            if (error != null)
              ErrorNotice(
                error!,
                onRetry: generating || busy ? null : generate,
              ),
            if (status != null)
              Padding(padding: const EdgeInsets.all(8), child: Text(status!)),
            Expanded(
              child: generating
                  ? const Center(child: CircularProgressIndicator())
                  : bytes == null
                  ? const Center(child: Text('PDF unavailable.'))
                  : PdfPreview(
                      key: ValueKey(bytes),
                      build: (_) async => bytes!,
                      initialPageFormat: PdfPageFormat.a4,
                      pdfFileName: fileName,
                      useActions: false,
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      canDebug: false,
                      dynamicLayout: false,
                      onError: (_, _) => const Center(
                        child: Text(
                          'Preview unavailable. You can still save, share or print the PDF.',
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (label, icon) in [
                    ('Save', Icons.save_alt),
                    ('Share', Icons.share_outlined),
                    ('Print', Icons.print_outlined),
                  ])
                    FilledButton.tonalIcon(
                      onPressed: bytes == null || busy || generating
                          ? null
                          : () => perform(label),
                      icon: Icon(icon),
                      label: Text(label),
                    ),
                ],
              ),
            ),
            if (busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    ),
  );
}
