import 'dart:typed_data';

/// Small byte helpers used across the crypto and transfer layers.

const String _hexAlphabet = '0123456789abcdef';

String hexEncode(List<int> bytes) {
  final buffer = StringBuffer();
  for (final b in bytes) {
    buffer.write(_hexAlphabet[(b >> 4) & 0x0f]);
    buffer.write(_hexAlphabet[b & 0x0f]);
  }
  return buffer.toString();
}

Uint8List hexDecode(String hex) {
  final clean = hex.trim();
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Groups a hex fingerprint into short, readable chunks, e.g. `a1b2 c3d4`.
String formatFingerprint(String hex, {int group = 4}) {
  final buffer = StringBuffer();
  for (var i = 0; i < hex.length; i += group) {
    if (i > 0) buffer.write(' ');
    buffer.write(hex.substring(i, (i + group).clamp(0, hex.length)));
  }
  return buffer.toString();
}

Uint8List concatBytes(List<List<int>> parts) {
  final total = parts.fold<int>(0, (sum, p) => sum + p.length);
  final out = Uint8List(total);
  var offset = 0;
  for (final p in parts) {
    out.setRange(offset, offset + p.length, p);
    offset += p.length;
  }
  return out;
}
