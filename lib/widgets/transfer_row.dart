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
    if (item.groupName != null) {
      meta.write(' · ');
      meta.write(item.groupName);
    }
    meta.write(' · ');
    meta.write(relativeTime(item.timestamp));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isText
                          ? const Color(0xFFE4F6EF)
                          : const Color(0xFFFFF2DE),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      switch (kind) {
                        TransferKind.file => Icons.insert_drive_file,
                        TransferKind.clipboard => Icons.content_paste,
                        TransferKind.message => Icons.chat_bubble_outline,
                      },
                      size: 18,
                      color: NearlinkColors.ink,
                    ),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      child: Icon(
                        item.direction == TransferDirection.outgoing
                            ? Icons.arrow_outward
                            : Icons.arrow_downward,
                        size: 10,
                        color: item.direction == TransferDirection.outgoing
                            ? NearlinkColors.accent
                            : const Color(0xFF2B5B84),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta.toString(),
                      style: const TextStyle(
                        fontSize: 11.5,
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
    switch (item.status) {
      case TransferStatus.delivered:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: const Color(0xFFEBF6EC),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check, size: 12, color: NearlinkColors.accent),
              SizedBox(width: 4),
              Text(
                'Delivered',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: NearlinkColors.accent,
                ),
              ),
            ],
          ),
        );
      case TransferStatus.active:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: NearlinkColors.soft,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${(item.progress * 100).round()}%',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: NearlinkColors.accent,
            ),
          ),
        );
      case TransferStatus.queued:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: NearlinkColors.soft,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'Queued',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: NearlinkColors.muted,
            ),
          ),
        );
      case TransferStatus.failed:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: NearlinkColors.dangerSoft,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 12, color: NearlinkColors.danger),
              SizedBox(width: 4),
              Text(
                'Failed',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: NearlinkColors.danger,
                ),
              ),
            ],
          ),
        );
    }
  }
}
