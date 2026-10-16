import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/crypto/pairing_payload.dart';
import '../../core/models/device.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/input.dart';
import '../../widgets/nearlink_card.dart';
import 'qr_scan_screen.dart';

enum _PairMethod { show, scan, manual }

/// Pairing flow: show this device's code, scan another's, or type one in.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, this.nearby});

  /// When opened from the "nearby" list, its address is prefilled.
  final NearbyPeer? nearby;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  late _PairMethod _method;
  PairingPayload? _payload;
  bool _busy = false;

  /// Devices trusted when this screen opened, so we can spot the moment
  /// pairing completes and get out of the way.
  late final Set<String> _trustedAtStart;
  bool _closing = false;

  final TextEditingController _host = TextEditingController();
  final TextEditingController _port = TextEditingController();
  final TextEditingController _pin = TextEditingController();

  @override
  void initState() {
    super.initState();
    _trustedAtStart = context
        .read<AppState>()
        .trustedDevices
        .map((d) => d.deviceId)
        .toSet();
    _method = widget.nearby != null ? _PairMethod.manual : _PairMethod.show;
    if (widget.nearby != null) {
      _host.text = widget.nearby!.host;
      _port.text = '${widget.nearby!.port}';
      // Ask that device to confirm. Note: we deliberately do NOT mint a
      // local code here as well — doing both raced, and the secret the
      // other device held was not the one this device kept.
      WidgetsBinding.instance.addPostFrameCallback((_) => _askForCode());
    } else {
      _refreshPayload();
    }
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _refreshPayload() async {
    final state = context.read<AppState>();
    final payload = await state.beginPairing();
    if (mounted) setState(() => _payload = payload);
  }

  Future<void> _askForCode() async {
    final peer = widget.nearby;
    if (peer == null || !mounted) return;
    await context.read<AppState>().requestPairingWith(peer);
  }
    void _close() {
    if (_closing) return;
    _closing = true;
    if (mounted) Navigator.of(context).pop();
  }


  Future<void> _scan() async {
    final result = await Navigator.of(context).push<PairingPayload>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    final ok = await context.read<AppState>().pairWithPayload(result);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) _close();
  }

  Future<void> _manual() async {
    final port = int.tryParse(_port.text.trim());
    if (_host.text.trim().isEmpty || port == null || _pin.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the address, port and PIN')),
      );
      return;
    }
    setState(() => _busy = true);
    final ok = await context.read<AppState>().pairManually(
          host: _host.text.trim(),
          port: port,
          pin: _pin.text.trim(),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) _close();
  }

  @override
  Widget build(BuildContext context) {
    // Pairing can finish from the other device's side — they tap Accept —
    // so watch the trust list and close this screen the moment it does,
    // dropping the person back on the control panel.
    final state = context.watch<AppState>();
    final justPaired = state.trustedDevices
        .any((d) => !_trustedAtStart.contains(d.deviceId));
    if (justPaired && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair a device'),
        backgroundColor: NearlinkColors.sidebar,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<_PairMethod>(
                    segments: const [
                      ButtonSegment(
                          value: _PairMethod.show,
                          label: Text('Show'),
                          icon: Icon(Icons.qr_code_2)),
                      ButtonSegment(
                          value: _PairMethod.scan,
                          label: Text('Scan'),
                          icon: Icon(Icons.qr_code_scanner)),
                      ButtonSegment(
                          value: _PairMethod.manual,
                          label: Text('Manual'),
                          icon: Icon(Icons.keyboard)),
                    ],
                    selected: {_method},
                    onSelectionChanged: (s) => setState(() => _method = s.first),
                  ),
                  const SizedBox(height: 20),
                  switch (_method) {
                    _PairMethod.show => _showPanel(),
                    _PairMethod.scan => _scanPanel(),
                    _PairMethod.manual => _manualPanel(),
                  },
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _showPanel() {
    final payload = _payload;
    return NearlinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SectionHeader(
            title: 'Let the other device scan this',
            subtitle: 'Or read out the PIN and address below',
          ),
          const SizedBox(height: 18),
          if (payload == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NearlinkColors.line),
              ),
              child: QrImageView(
                data: payload.toQrData(),
                version: QrVersions.auto,
                size: 216,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              payload.pin,
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: 8,
              ),
            ),
            const SizedBox(height: 4),
            const Text('PIN',
                style: TextStyle(fontSize: 12, color: NearlinkColors.muted)),
            const SizedBox(height: 14),
            Text(
              '${payload.host}:${payload.port}',
              style: const TextStyle(
                fontSize: 13,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'This code is single-use and expires after five minutes.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: NearlinkColors.muted),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _refreshPayload,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('New code'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _scanPanel() {
    return NearlinkCard(
      child: Column(
        children: [
          const SectionHeader(
            title: 'Scan a pairing code',
            subtitle: 'Open Pair on the other device and scan its QR code',
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _scan,
            icon: const Icon(Icons.qr_code_scanner, size: 18),
            label: Text(_busy ? 'Pairing…' : 'Open camera'),
          ),
          const SizedBox(height: 14),
          const Text(
            'If the app quits when you tap this on macOS, the camera usage '
            'description is missing from macos/Runner/Info.plist — see '
            'platform_setup/README.md. Manual entry always works.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: NearlinkColors.muted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _manualPanel() {
    final peer = widget.nearby;
    if (peer != null) {
      return NearlinkCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Waiting for ${peer.name}',
              subtitle:
                  'It has been asked to confirm. Tap Accept on that device '
                  'and you are paired — there is no code to type.',
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _askForCode,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Ask again'),
            ),
          ],
        ),
      );
    }
    return NearlinkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            title: 'Enter a pairing code',
            subtitle:
                'The other device has been asked to show a code — read it '
                'there and type it here',
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _host,
                  decoration: nearlinkInput(labelText: 'Address'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  decoration: nearlinkInput(labelText: 'Port'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pin,
            keyboardType: TextInputType.number,
            decoration: nearlinkInput(labelText: 'Six-digit PIN'),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _manual,
              child: Text(_busy ? 'Pairing…' : 'Confirm pairing'),
            ),
          ),
        ],
      ),
    );
  }
}
