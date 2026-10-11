import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/presentation/common.dart';

class ExportScreen extends ConsumerStatefulWidget {
  final Uint8List bytes;
  final String fileName;
  final bool template;
  const ExportScreen({
    super.key,
    required this.bytes,
    required this.fileName,
    required this.template,
  });
  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  bool busy = false;
  String? message, error;
  Future<void> _send({required bool share}) async {
    setState(() {
      busy = true;
      message = null;
      error = null;
    });
    try {
      final files = ref.read(workbookFilesProvider);
      final done = await (share
          ? files.share(widget.bytes, widget.fileName)
          : files.save(widget.bytes, widget.fileName));
      if (mounted) {
        setState(
          () => message = done
              ? (share
                    ? 'Share sheet opened. Check the destination to confirm your copy.'
                    : 'Workbook saved. Keep a copy outside this phone.')
              : 'Cancelled. You can save or share again.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.template ? 'Blank Excel template' : 'Excel backup'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.description_outlined, size: 56),
            const SizedBox(height: 16),
            Text(
              widget.fileName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              widget.template
                  ? 'The data sheets are blank. Examples are on a separate sheet and are never imported. Fill related rows with valid IDs and review the import before saving records.'
                  : 'Your complete backup is ready. Save it to a chosen location or share it to trusted storage. Returning without saving or sharing does not keep a backup.',
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: busy ? null : () => _send(share: false),
              icon: const Icon(Icons.save_alt),
              label: const Text('Save file'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy ? null : () => _send(share: true),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share file'),
            ),
            if (busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
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
