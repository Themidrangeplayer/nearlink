import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/device.dart';
import '../../core/models/transfer_item.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/format.dart';
import '../../widgets/input.dart';
import '../../widgets/nearlink_card.dart';

/// Compose clipboard text and send it to one device, several, or all of them.
class ClipboardScreen extends StatefulWidget {
  const ClipboardScreen({super.key});

  @override
  State<ClipboardScreen> createState() => _ClipboardScreenState();
}

class _ClipboardScreenState extends State<ClipboardScreen> {
  final TextEditingController _controller = TextEditingController();
  final Set<String> _selected = <String>{};
  bool _initialised = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final devices = state.trustedDevices;

    // Drop selections for devices that no longer exist.
    _selected.removeWhere(
      (id) => !devices.any((d) => d.deviceId == id),
    );
    if (!_initialised && devices.isNotEmpty) {
      _initialised = true;
      _selected.add(
        state.selectedDevice?.deviceId ?? devices.first.deviceId,
      );
    }

    final clipboardItems = state.transfers
        .where((t) => t.kind == TransferKind.clipboard)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Clipboard', style: NearlinkTheme.heading(context, size: 34)),
        const SizedBox(height: 8),
        const Text(
          'Write something once, then send it to the devices you pick — or to '
          'all of them at once.',
          style: TextStyle(fontSize: 15, color: NearlinkColors.muted),
        ),
        const SizedBox(height: 22),
        if (state.hasPendingClipboard) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF2DB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: NearlinkColors.ink),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'An item arrived while the app was in the background. It is '
                    'applied to your clipboard automatically — or tap Copy on '
                    'it below.',
                    style: TextStyle(
                      fontSize: 12,
                      color: NearlinkColors.ink,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        NearlinkCard(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: state.autoSyncClipboard,
            onChanged: state.setAutoSyncClipboard,
            title: const Text(
              'Auto-sync clipboard',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: const Text(
              'Anything you copy is sent to every trusted device straight away',
              style: TextStyle(fontSize: 12, color: NearlinkColors.muted),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _composeCard(state, devices),
        const SizedBox(height: 18),
        _historyCard(state, clipboardItems),
      ],
    );
  }

  Widget _composeCard(AppState state, List<TrustedDevice> devices) {
    final onlineCount = devices.where((d) => state.isOnline(d.deviceId)).length;

    return NearlinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Compose',
            subtitle: devices.isEmpty
                ? 'Pair a device first, then you can send to one or many'
                : '${devices.length} trusted · $onlineCount online now',
          ),
          const SizedBox(height: 14),
          if (devices.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: devices
                  .map((d) => _deviceChip(state, d))
                  .toList(),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton(
                  onPressed: () => _selectAll(devices),
                  child: const Text('All devices'),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _selected.clear();
                  }),
                  child: const Text('Clear'),
                ),
                const Spacer(),
                Text(
                  '${_selected.length} selected',
                  style: const TextStyle(
                    fontSize: 12,
                    color: NearlinkColors.muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _controller,
            maxLines: 8,
            minLines: 6,
            decoration: nearlinkInput(
              hintText: 'Paste a note, link, or code snippet…',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      devices.isEmpty ? null : () => _sendToAll(state),
                  icon: const Icon(Icons.groups_outlined, size: 18),
                  label: const Text('Send to all'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => _sendToSelected(state),
                  icon: const Icon(Icons.send, size: 18),
                  label: Text(
                    _selected.isEmpty
                        ? 'Send'
                        : 'Send to ${_selected.length}',
                  ),
                ),
              ),
            ],
          ),
          if (devices.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Auto-sync sends every copy automatically — turn it on under '
              'Security.',
              style: TextStyle(
                fontSize: 11,
                color: NearlinkColors.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _deviceChip(AppState state, TrustedDevice device) {
    final online = state.isOnline(device.deviceId);
    final selected = _selected.contains(device.deviceId);
    return FilterChip(
      showCheckmark: false,
      selected: selected,
      onSelected: (on) => setState(() {
        if (on) {
          _selected.add(device.deviceId);
        } else {
          _selected.remove(device.deviceId);
        }
      }),
      avatar: Icon(
        Icons.circle,
        size: 10,
        color: online ? NearlinkColors.online : NearlinkColors.muted,
      ),
      label: Text(device.name),
    );
  }

  void _selectAll(List<TrustedDevice> devices) {
    setState(() {
      _selected
        ..clear()
        ..addAll(devices.map((d) => d.deviceId));
    });
  }

  Future<void> _sendToSelected(AppState state) async {
    final text = _controller.text;
    if (text.trim().isEmpty) {
      _controller.clear();
      return;
    }
    final sent = await state.sendClipboardToDevices(_selected.toList(), text);
    if (sent > 0) _controller.clear();
  }

  Future<void> _sendToAll(AppState state) async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    final sent = await state.sendClipboardToAllTrusted(text);
    if (sent > 0) _controller.clear();
  }

  Widget _historyCard(AppState state, List<TransferItem> items) {
    return NearlinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Clipboard history',
            subtitle: 'Both directions, most recent first',
            trailing: PopupMenuButton<String>(
              tooltip: 'Clipboard options',
              icon: const Icon(Icons.more_horiz, color: NearlinkColors.muted),
              onSelected: (value) {
                if (value == 'device') {
                  state.clearSystemClipboard();
                } else if (value == 'history') {
                  _confirmClearHistory(state);
                }
              },
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'device',
                  child: Text("Clear this device's clipboard"),
                ),
                PopupMenuItem<String>(
                  value: 'history',
                  enabled: items.isNotEmpty,
                  child: const Text('Clear clipboard history'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 26),
              child: Center(
                child: Text(
                  'No clipboard items yet.',
                  style: TextStyle(fontSize: 13, color: NearlinkColors.muted),
                ),
              ),
            )
          else
            ...items.map(_historyRow),
        ],
      ),
    );
  }

  Widget _historyRow(TransferItem item) {
    final outgoing = item.direction == TransferDirection.outgoing;
    final payload = item.payload;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            outgoing ? Icons.arrow_upward : Icons.arrow_downward,
            size: 16,
            color: NearlinkColors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${outgoing ? 'To' : 'From'} ${item.peerName} · '
                  '${relativeTime(item.timestamp)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: NearlinkColors.muted,
                  ),
                ),
              ],
            ),
          ),
          if (payload != null && payload.isNotEmpty)
            IconButton(
              tooltip: 'Copy to this device',
              iconSize: 18,
              color: NearlinkColors.muted,
              icon: const Icon(Icons.copy),
              onPressed: () => _copy(payload),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmClearHistory(AppState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear clipboard history?'),
        content: const Text(
          'This removes clipboard entries from the list on this device. Files '
          'and messages are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await state.clearClipboardHistory();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }
}
