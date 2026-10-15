import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/device.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/format.dart';
import '../../widgets/input.dart';
import '../../widgets/nearlink_card.dart';
import '../../widgets/transfer_actions.dart';
import '../../widgets/transfer_row.dart';
import '../pairing/pairing_screen.dart';
import 'widgets/device_tile.dart';
import 'widgets/hero_card.dart';
import 'widgets/stat_card.dart';

class ControlCenterScreen extends StatefulWidget {
  const ControlCenterScreen({super.key});

  @override
  State<ControlCenterScreen> createState() => _ControlCenterScreenState();
}

class _ControlCenterScreenState extends State<ControlCenterScreen> {
  final TextEditingController _clipboard = TextEditingController();
  bool _dragging = false;

  @override
  void dispose() {
    _clipboard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 940;
        final leftColumn = <Widget>[
          _trustedDevices(state),
          const SizedBox(height: 18),
          _sendFile(state),
        ];
        final rightColumn = <Widget>[
          _clipboardCard(state),
          const SizedBox(height: 18),
          _activity(state),
          const SizedBox(height: 18),
          _nearby(state),
        ];

        return ListView(
          padding: EdgeInsets.fromLTRB(
            wide ? 44 : 20,
            26,
            wide ? 44 : 20,
            46,
          ),
          children: [
            _topbar(state),
            const SizedBox(height: 26),
            Text('Your devices, in reach.',
                style: NearlinkTheme.heading(context, size: wide ? 44 : 32)),
            const SizedBox(height: 11),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: const Text(
                'Nearlink is a universal, end-to-end encrypted space for the '
                'devices you trust. Drop a file, paste something useful, and it '
                'appears wherever you need it.',
                style: TextStyle(
                  fontSize: 15,
                  color: NearlinkColors.muted,
                  height: 1.55,
                ),
              ),
            ),
            const SizedBox(height: 28),
            _overview(state, wide),
            const SizedBox(height: 18),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 155,
                    child: Column(children: leftColumn),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    flex: 75,
                    child: Column(children: rightColumn),
                  ),
                ],
              )
            else
              Column(children: [...leftColumn, ...rightColumn]),
          ],
        );
      },
    );
  }

  Widget _topbar(AppState state) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Control center / My devices',
            style: TextStyle(fontSize: 14, color: NearlinkColors.muted),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: state.discoveryEnabled
                ? const Color(0xFFE5F3DB)
                : NearlinkColors.soft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              Icon(
                Icons.circle,
                size: 8,
                color: state.discoveryEnabled
                    ? const Color(0xFF60AD4E)
                    : NearlinkColors.muted,
              ),
              const SizedBox(width: 8),
              Text(
                state.discoveryEnabled
                    ? 'Nearby discovery on'
                    : 'Nearby discovery off',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _overview(AppState state, bool wide) {
    final hero = HeroCard(
      headline: state.trustedDevices.isEmpty
          ? 'No trusted devices yet.'
          : '${state.trustedDevices.length} trusted '
              'device${state.trustedDevices.length == 1 ? '' : 's'} ready to share.',
      body: 'Devices become available when they are near and paired with this '
          'device. Pairing proves both sides hold the same key — no password '
          'ever leaves your device.',
      actionLabel: 'Pair a nearby device',
      onAction: () => _openPairing(context),
    );

    final stats = Column(
      children: [
        StatCard(
          label: 'Connected now',
          value:
              '${state.onlineDevices.length} device${state.onlineDevices.length == 1 ? '' : 's'}',
          foot: 'All encrypted',
        ),
        const SizedBox(height: 18),
        StatCard(
          label: 'Shared recently',
          value: formatBytes(state.sharedThisWeekBytes),
          foot: '${formatBytes(state.totalSharedBytes)} all time',
        ),
      ],
    );

    if (!wide) {
      return Column(children: [hero, const SizedBox(height: 18), stats]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 155, child: hero),
        const SizedBox(width: 18),
        Expanded(flex: 75, child: stats),
      ],
    );
  }

  Widget _trustedDevices(AppState state) {
    final devices = state.trustedDevices;
    return NearlinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Trusted devices',
            subtitle: 'Ready for automatic sharing while nearby',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: devices.length < 2
                      ? null
                      : () => _openIntroduce(context, state),
                  icon: const Icon(Icons.hub_outlined, size: 16),
                  label: const Text('Connect devices'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _openPairing(context),
                  child: const Text('+ Add device'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 19),
          if (devices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No trusted devices yet — use Pair a nearby device to add one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: NearlinkColors.muted),
                ),
              ),
            )
          else
            ...devices.map(
              (d) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: DeviceTile(
                  name: d.name,
                  platform: d.platform,
                  meta: _deviceMeta(state, d),
                  selected: state.selectedDevice?.deviceId == d.deviceId,
                  online: state.isOnline(d.deviceId),
                  onTap: () => state.selectDevice(d.deviceId),
                  onRemove: () => state.removeDevice(d.deviceId),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _deviceMeta(AppState state, TrustedDevice device) {
    final parts = <String>[platformLabel(device.platform)];
    if (device.model.isNotEmpty) parts.add(device.model);
    if (state.isOnline(device.deviceId)) {
      parts.add('Nearby');
    } else {
      final lastSeen = device.lastSeen;
      parts.add(lastSeen == null
          ? 'Paired ${relativeTime(device.pairedAt)}'
          : 'Last seen ${relativeTime(lastSeen)}');
    }
    return parts.join(' · ');
  }

  Widget _sendFile(AppState state) {
    return NearlinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Send a file',
            subtitle: 'Drop anything here and choose a trusted device',
            trailing: Eyebrow('Encrypted'),
          ),
          const SizedBox(height: 19),
          DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (details) async {
              setState(() => _dragging = false);
              final files = details.files
                  .map((x) => PlatformFile(
                        path: x.path,
                        name: x.name,
                        size: File(x.path).lengthSync(),
                      ))
                  .toList();
              await state.sendFiles(files);
            },
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 154),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _dragging
                    ? const Color(0xFFE7F3E9)
                    : const Color(0xFFFAFCF9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _dragging
                      ? NearlinkColors.accent
                      : const Color(0xFF93AA9C),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 39,
                    height: 39,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDEF1E3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.upload_file,
                        size: 19, color: NearlinkColors.accent),
                  ),
                  const SizedBox(height: 9),
                  const Text('Drag and drop a file here',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  const Text('or choose a file from this device',
                      style: TextStyle(
                          fontSize: 12, color: NearlinkColors.muted)),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _pickFiles(state),
                    child: const Text('Browse files'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFiles(AppState state) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    await state.sendFiles(result.files);
  }

  Widget _clipboardCard(AppState state) {
    final target = state.selectedDevice;
    return NearlinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Universal clipboard',
            subtitle: 'Paste text to send it to the selected device',
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _clipboard,
            maxLines: 4,
            minLines: 4,
            decoration: nearlinkInput(
              hintText: 'Paste a note, link, or code snippet…',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'Sending to ',
                    style: const TextStyle(
                        fontSize: 12, color: NearlinkColors.muted),
                    children: [
                      TextSpan(
                        text: target?.name ?? 'no device',
                        style: const TextStyle(
                          color: NearlinkColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              FilledButton(
                onPressed: () async {
                  await state.sendClipboard(_clipboard.text);
                  _clipboard.clear();
                },
                child: const Text('Send clipboard'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _activity(AppState state) {
    final items = state.transfers.take(6).toList();
    return NearlinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Recent activity',
            subtitle: 'Always encrypted in transit',
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: Text(
                  'Nothing sent or received yet.',
                  style: TextStyle(fontSize: 13, color: NearlinkColors.muted),
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
    );
  }

  Widget _nearby(AppState state) {
    final peers = state.eligiblePeers;
    return NearlinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Nearby and eligible',
            subtitle: state.discoveryEnabled
                ? 'Discovery ${state.discoveryAdvertising ? 'advertising' : 'not advertising'}'
                    ' · ${state.discoveryServiceCount} mDNS service'
                    '${state.discoveryServiceCount == 1 ? '' : 's'} seen'
                : 'Discovery is off',
          ),
          const SizedBox(height: 8),
          if (peers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        state.discoveryEnabled
                            ? Icons.search_off
                            : Icons.wifi_off,
                        size: 18,
                        color: NearlinkColors.muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          !state.discoveryEnabled
                              ? 'Discovery is off'
                              : state.discoveryServiceCount == 0
                                  ? 'No devices found on this network'
                                  : 'Found '
                                      '${state.discoveryServiceCount} '
                                      'device${state.discoveryServiceCount == 1 ? '' : 's'}, '
                                      'none eligible',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    !state.discoveryEnabled
                        ? 'Turn Nearby discovery on under Security to look for '
                            'devices.'
                        : state.discoveryServiceCount == 0
                            ? 'Make sure the other device has Nearlink open, is '
                                'on the same Wi-Fi, and that discovery is '
                                'allowed. On macOS that means granting Local '
                                'Network access; on Android it needs the Wi-Fi '
                                'multicast permission.'
                            : 'Everything in range is already paired — look '
                                'under Trusted devices above.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: NearlinkColors.muted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            )
          else
            ...peers.map(
              (peer) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_tethering,
                        size: 18, color: NearlinkColors.online),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(peer.name,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            '${platformLabel(peer.platform)}'
                            '${peer.model.isEmpty ? '' : ' · ${peer.model}'}'
                            ' · ${peer.host}:${peer.port}',
                            maxLines: 2,
                            style: const TextStyle(
                                fontSize: 11, color: NearlinkColors.muted),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => _openPairing(context, peer: peer),
                      child: const Text('Pair'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Pick two or more trusted devices and vouch for them to each other.
  Future<void> _openIntroduce(BuildContext context, AppState state) async {
    final devices = state.trustedDevices;
    if (devices.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pair at least two devices first')),
      );
      return;
    }

    final selected = <String>{};
    final chosen = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setDialogState) => AlertDialog(
          title: const Text('Connect your devices to each other'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pick two or more trusted devices. Every pair is asked '
                  'separately, and a pair only connects when both sides '
                  'agree — if either declines, they stay apart.',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 14),
                for (final device in devices)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: selected.contains(device.deviceId),
                    onChanged: (on) => setDialogState(() {
                      if (on == true) {
                        selected.add(device.deviceId);
                      } else {
                        selected.remove(device.deviceId);
                      }
                    }),
                    title: Text(
                      device.name,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      '${platformLabel(device.platform)}'
                      '${device.model.isEmpty ? '' : ' · ${device.model}'}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: NearlinkColors.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.length < 2
                  ? null
                  : () => Navigator.of(dialogContext).pop(selected),
              child: Text(
                selected.length < 2
                    ? 'Connect'
                    : 'Connect ${selected.length}',
              ),
            ),
          ],
        ),
      ),
    );

    if (chosen == null || chosen.length < 2) return;
    await state.introduceDevices(chosen);
  }

  void _openPairing(BuildContext context, {NearbyPeer? peer}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PairingScreen(nearby: peer),
      ),
    );
  }
}
