import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/crypto/pairing_payload.dart';
import '../../theme/app_theme.dart';

/// Full-screen QR scanner. Pops with the decoded [PairingPayload] on success.
///
/// `mobile_scanner` supports Android, iOS, macOS and web. On Windows and Linux
/// there is no camera plugin, so the screen explains the manual fallback.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  static bool get isSupported {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final payload = PairingPayload.tryDecode(raw);
      if (payload != null) {
        _handled = true;
        Navigator.of(context).pop(payload);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan a pairing code'),
        backgroundColor: NearlinkColors.sidebar,
        foregroundColor: Colors.white,
      ),
      body: !QrScanScreen.isSupported
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Camera scanning is not available on this platform. '
                  'Use the manual code instead: open Pair on the other device '
                  'and type its address and PIN here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: NearlinkColors.muted, height: 1.5),
                ),
              ),
            )
          : Stack(
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 40,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Point at the QR code shown on the other device',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
