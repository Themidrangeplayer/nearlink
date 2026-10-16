import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/device.dart';
import '../../core/utils/bytes.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/nearlink_card.dart';
import '../../widgets/platform_icon.dart';

/// Security centre: identity fingerprint, discovery/privacy toggles, the trust
/// list, and a plain-language account of how the crypto works.
class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Security', style: NearlinkTheme.heading(context, size: 34)),
        const SizedBox(height: 8),
        const Text(
          'Your identity, what you trust, and how your data is protected.',
          style: TextStyle(fontSize: 15, color: NearlinkColors.muted),
        ),
        const SizedBox(height: 22),
        NearlinkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                title: 'This device',
                subtitle: 'Its identity is a key pair generated here and never shared',
              ),
              const SizedBox(height: 18),
              _KeyRow(label: 'Device name', value: state.deviceName),
              const SizedBox(height: 12),
              _KeyRow(label: 'Device ID', value: state.identity.deviceId),
              const SizedBox(height: 12),
              _KeyRow(
                label: 'Fingerprint',
                value: formatFingerprint(state.fingerprint),
              ),
              const SizedBox(height: 12),
              _KeyRow(label: 'Listening on port', value: '${state.serverPort}'),
              const SizedBox(height: 12),
              _KeyRow(
                label: 'Received files land in',
                value: state.downloadDirectory.path,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        NearlinkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(title: 'Privacy'),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: state.discoveryEnabled,
                onChanged: state.setDiscoveryEnabled,
                title: const Text('Nearby discovery',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Advertise and look for devices on this network'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: state.autoAcceptTrusted,
                onChanged: state.setAutoAcceptTrusted,
                title: const Text('Accept from trusted devices',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Receive without a prompt from devices you have paired'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: state.notificationsEnabled,
                onChanged: state.setNotificationsEnabled,
                title: const Text('Notifications',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Tell me when a file, clipboard item, message or '
                    'pairing request arrives while Nearlink is in the '
                    'background'),
              ),
              if (state.canKeepAliveInBackground)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: state.keepAliveInBackground,
                  onChanged: state.setKeepAliveInBackground,
                  title: const Text('Keep receiving in the background',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'Shows a small notification so Android does not pause '
                      'Nearlink when it is minimised'),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: state.autoSyncClipboard,
                onChanged: state.setAutoSyncClipboard,
                title: const Text('Auto-sync clipboard',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Copies on this device are sent straight to every trusted '
                    'device, and arrive in your clipboard here'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        NearlinkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                title: 'Trusted devices',
                subtitle: 'Removing a device revokes its access immediately',
              ),
              const SizedBox(height: 8),
              if (state.trustedDevices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 22),
                  child: Center(
                    child: Text('No devices trusted yet.',
                        style: TextStyle(
                            fontSize: 13, color: NearlinkColors.muted)),
                  ),
                )
              else
                ...state.trustedDevices.map(
                  (d) => _TrustRow(
                    device: d,
                    onRemove: () => state.removeDevice(d.deviceId),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const NearlinkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(title: 'How Nearlink protects your data'),
              SizedBox(height: 14),
              _Bullet(
                'Each device generates an Ed25519 identity key and an X25519 '
                'agreement key on first launch. Private keys never leave the '
                'device and are held in platform secure storage.',
              ),
              _Bullet(
                'Pairing exchanges only public keys, verified against the '
                'fingerprint in the QR code or PIN — so nobody can sit in the '
                'middle of the connection.',
              ),
              _Bullet(
                'Every session derives a fresh AES-256-GCM key with X25519 '
                'ECDH and HKDF, then confirms it with a keyed MAC before any '
                'data moves.',
              ),
              _Bullet(
                'Files and clipboard payloads are sealed chunk by chunk, so '
                'confidentiality and integrity are enforced end to end, not '
                'just in transit.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 12, color: NearlinkColors.muted)),
        const SizedBox(height: 4),
        SelectableText(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _TrustRow extends StatelessWidget {
  const _TrustRow({required this.device, required this.onRemove});

  final TrustedDevice device;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: platformTint(device.platform),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(platformIcon(device.platform), size: 17),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${platformLabel(device.platform)}'
                  '${device.model.isEmpty ? '' : ' · ${device.model}'}'
                  ' · ${formatFingerprint(device.fingerprint).split(' ').take(2).join(' ')}…',
                  style: const TextStyle(
                      fontSize: 11, color: NearlinkColors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: 'Remove ${device.name}',
            iconSize: 18,
            color: NearlinkColors.muted,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 6, color: NearlinkColors.accent),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: NearlinkColors.muted,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
