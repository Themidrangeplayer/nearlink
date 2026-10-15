import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

import '../core/models/transfer_item.dart';

/// Act on a transfer activity entry: open a received file, or put clipboard
/// text and messages back on the system clipboard.
Future<void> openTransferItem(BuildContext context, TransferItem item) async {
  final messenger = ScaffoldMessenger.of(context);

  if (item.kind == TransferKind.clipboard ||
      item.kind == TransferKind.message) {
    final text = item.payload;
    if (text == null || text.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nothing stored for this item')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
    return;
  }

  final path = item.filePath;
  if (path == null || path.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('File location unknown')),
    );
    return;
  }
  if (!File(path).existsSync()) {
    messenger.showSnackBar(
      SnackBar(content: Text('File is no longer at $path')),
    );
    return;
  }

  final result = await OpenFilex.open(path);
  if (result.type != ResultType.done) {
    messenger.showSnackBar(
      SnackBar(content: Text('Could not open it: ${result.message}')),
    );
  }
}
