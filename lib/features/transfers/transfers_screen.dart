import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/format.dart';
import '../../widgets/nearlink_card.dart';
import '../../widgets/transfer_actions.dart';
import '../../widgets/transfer_row.dart';

/// Full transfer history with a clear action.
class TransfersScreen extends StatelessWidget {
  const TransfersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final items = state.transfers;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Transfers', style: NearlinkTheme.heading(context, size: 34)),
        const SizedBox(height: 8),
        const Text(
          'Everything sent and received on this device, newest first.',
          style: TextStyle(fontSize: 15, color: NearlinkColors.muted),
        ),
        const SizedBox(height: 22),
        NearlinkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: '${items.length} item${items.length == 1 ? '' : 's'}',
                subtitle:
                    '${formatBytes(state.totalSharedBytes)} moved in total',
                trailing: TextButton(
                  onPressed: items.isEmpty
                      ? null
                      : () => _confirmClear(context, state),
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      'No transfers yet.',
                      style:
                          TextStyle(fontSize: 13, color: NearlinkColors.muted),
                    ),
                  ),
                )
              else
                ...items.map(
                  (item) => TransferRow(
                    item: item,
                    onTap: () => openTransferItem(context, item),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context, AppState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear transfer history?'),
        content: const Text(
          'This only clears the list on this device. Files already received '
          'stay in your downloads folder.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await state.clearHistory();
  }
}
