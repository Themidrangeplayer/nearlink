import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/device.dart';
import '../../core/models/transfer_item.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/format.dart';
import '../../widgets/input.dart';
import '../../widgets/nearlink_card.dart';

/// Send messages to one device, to several at once (a group), or to everyone.
class MessagingScreen extends StatefulWidget {
  const MessagingScreen({super.key});

  @override
  State<MessagingScreen> createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> {
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

    _selected.removeWhere((id) => !devices.any((d) => d.deviceId == id));
    if (!_initialised && devices.isNotEmpty) {
      _initialised = true;
      _selected.add(
        state.selectedDevice?.deviceId ?? devices.first.deviceId,
      );
    }

    final messages = state.transfers
        .where((t) => t.kind == TransferKind.message)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Messages', style: NearlinkTheme.heading(context, size: 34)),
        const SizedBox(height: 8),
        const Text(
          'Message one device, pick several to start a group, or send to '
          'everyone at once.',
          style: TextStyle(fontSize: 15, color: NearlinkColors.muted),
        ),
        const SizedBox(height: 22),
        _composeCard(state, devices),
        const SizedBox(height: 18),
        _threadCard(messages),
      ],
    );
  }

  Widget _composeCard(AppState state, List<TrustedDevice> devices) {
    final isGroup = _selected.length > 1;
    final onlineCount = devices.where((d) => state.isOnline(d.deviceId)).length;

    return NearlinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: isGroup ? 'Group message' : 'New message',
            subtitle: devices.isEmpty
                ? 'Pair a device first, then you can message it'
                : '${devices.length} trusted · $onlineCount online now',
          ),
          const SizedBox(height: 14),
          if (devices.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: devices.map((d) => _chip(state, d)).toList(),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _selected
                      ..clear()
                      ..addAll(devices.map((d) => d.deviceId));
                  }),
                  child: const Text('Everyone'),
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
            if (isGroup) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5F0D9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.groups_outlined,
                      size: 16,
                      color: NearlinkColors.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sending as a group to ${_selected.length} devices — '
                        'each receives the same message.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: NearlinkColors.heroInk,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _controller,
            maxLines: 5,
            minLines: 3,
            decoration: nearlinkInput(hintText: 'Write a message…'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: devices.isEmpty ? null : () => _sendAll(state),
                  icon: const Icon(Icons.public, size: 18),
                  label: const Text('Universal'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      _selected.isEmpty ? null : () => _sendSelected(state),
                  icon: const Icon(Icons.send, size: 18),
                  label: Text(
                    isGroup
                        ? 'Send to group (${_selected.length})'
                        : 'Send',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(AppState state, TrustedDevice device) {
    final online = state.isOnline(device.deviceId);
    return FilterChip(
      showCheckmark: false,
      selected: _selected.contains(device.deviceId),
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

  Future<void> _sendSelected(AppState state) async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    final sent = await state.sendMessageToDevices(_selected.toList(), text);
    if (sent > 0) _controller.clear();
  }

  Future<void> _sendAll(AppState state) async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    final sent = await state.sendMessageToAllTrusted(text);
    if (sent > 0) _controller.clear();
  }

  Widget _threadCard(List<TransferItem> messages) {
    return NearlinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Message thread',
            subtitle: 'Everything sent and received, newest first',
          ),
          const SizedBox(height: 8),
          if (messages.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 26),
              child: Center(
                child: Text(
                  'No messages yet.',
                  style: TextStyle(fontSize: 13, color: NearlinkColors.muted),
                ),
              ),
            )
          else
            ...messages.map(_messageRow),
        ],
      ),
    );
  }

  Widget _messageRow(TransferItem item) {
    final outgoing = item.direction == TransferDirection.outgoing;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: outgoing
                ? NearlinkColors.accent.withValues(alpha: 0.12)
                : NearlinkColors.soft,
            child: Icon(
              outgoing ? Icons.arrow_upward : Icons.arrow_downward,
              size: 15,
              color: outgoing ? NearlinkColors.accent : NearlinkColors.ink,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.peerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      relativeTime(item.timestamp),
                      style: const TextStyle(
                        fontSize: 11,
                        color: NearlinkColors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.payload ?? item.title,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                if (item.groupName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.groupName!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: NearlinkColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
