import 'package:flutter/material.dart';

import '../core/models/transfer_item.dart';
import '../theme/app_theme.dart';
import 'format.dart';

/// One line in the transfer activity list.
class TransferRow extends StatelessWidget {
  const TransferRow({super.key, required this.item, this.onTap});

  final TransferItem item;

  /// Tapping an entry opens a file, or re-copies clipboard text and messages.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final kind = item.kind;
    final isText = kind != TransferKind.file;
    final meta = StringBuffer();
    meta.write(switch (kind) {
      TransferKind.file => formatBytes(item.bytes),
      TransferKind.clipboard => 'Clipboard',
      TransferKind.message => 'Message',
    });
    meta.write(' · ');
    meta.write(item.direction == TransferDirection.outgoing ? 'To ' : 'From ');
    meta.write(item.peerName);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: isText
                  ? const Color(0xFFE4F6EF)
                  : const Color(0xFFFFF2DE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              switch (kind) {
                TransferKind.file => Icons.insert_drive_file,
                TransferKind.clipboard => Icons.content_paste,
                TransferKind.message => Icons.chat_bubble_outline,
              },
              size: 17,
              color: NearlinkColors.ink,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  meta.toString(),
                  style: const TextStyle(
                    fontSize: 11,
                    color: NearlinkColors.muted,
                  ),
                ),
                if (item.status == TransferStatus.active) ...[
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: item.progress == 0 ? null : item.progress,
                      minHeight: 5,
                      backgroundColor: NearlinkColors.soft,
                      color: NearlinkColors.accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          _StateLabel(item: item),
        ],
          ),
        ),
      ),
    );
  }
}

class _StateLabel extends StatelessWidget {
  const _StateLabel({required this.item});

  final TransferItem item;

  @override
  Widget build(BuildContext context) {
    var label = '';
    var color = NearlinkColors.muted;
    switch (item.status) {
      case TransferStatus.delivered:
        label = 'Delivered';
        color = NearlinkColors.accent;
        break;
      case TransferStatus.active:
        label = '${(item.progress * 100).round()}%';
        color = NearlinkColors.accent;
        break;
      case TransferStatus.queued:
        label = 'Queued';
        color = NearlinkColors.muted;
        break;
      case TransferStatus.failed:
        label = 'Failed';
        color = NearlinkColors.danger;
        break;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
