import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../crypto/device_identity.dart';
import '../crypto/pairing_payload.dart';
import '../crypto/secure_channel.dart';
import '../models/device.dart';
import '../models/intro.dart';
import '../protocol/protocol.dart';
import '../utils/bytes.dart';

/// Callbacks the server raises when something arrives from a peer.
abstract class NearlinkServerDelegate {
  /// A peer completed pairing and should be persisted as trusted.
  Future<void> onPaired(TrustedDevice device);

  /// A file finished arriving and was written to [path].
  Future<void> onFileReceived({
    required String fromDeviceId,
    required String fromName,
    required String transferId,
    required String fileName,
    required int size,
    required String path,
  });

  /// A clipboard payload arrived.
  Future<void> onClipboardReceived({
    required String fromDeviceId,
    required String fromName,
    required String text,
  });

  /// A chat message arrived. [group] is set when it was addressed to a group.
  Future<void> onMessageReceived({
    required String fromDeviceId,
    required String fromName,
    required String text,
    String? group,
  });

  /// A peer tapped "Pair" on us and offered its own pairing payload. The app
  /// should ask the person to accept; accepting completes pairing with nothing
  /// typed by hand.
  Future<void> onPairRequest(PairingPayload requester);

  /// A peer told us it removed us; drop it from our trust list too.
  Future<void> onUnpaired(String deviceId);

  /// A trusted device vouched for us and another of its devices. Ask the
  /// person whether they want to connect.
  Future<void> onIntroOffer(IntroOffer offer);

  /// The other device in an introduction consented.
  Future<void> onIntroAccepted({
    required String introId,
    required IntroPeer from,
  });

  /// The other device in an introduction refused, which cancels it here too.
  Future<void> onIntroDeclined({
    required String introId,
    required IntroPeer from,
  });
}

/// The receiving half of Nearlink: an HTTP/1.1 server whose control and
/// payload bodies are always sealed with a per-session AES-GCM key.
///
/// The socket is bound to a random high port and advertised over mDNS; peers
/// that have not paired and completed a handshake are refused.
class NearlinkServer {
  NearlinkServer({
    required this.identity,
    required this.deviceName,
    required this.deviceModel,
    required this.platform,
    required this.delegate,
    required this.isTrusted,
    required this.downloadDirectory,
  });

  final DeviceIdentity identity;
  final String deviceName;
  final String deviceModel;
  final DevicePlatform platform;
  final NearlinkServerDelegate delegate;
  final bool Function(String deviceId) isTrusted;
  final Directory downloadDirectory;

  HttpServer? _server;

  /// Secrets offered recently. Keeping the last few means a race between
  /// two code paths cannot invalidate the one a peer is already holding.
  final List<PairingPayload> _pairings = <PairingPayload>[];

  /// Offer a fresh single-use secret to other devices.
  void offerPairing(PairingPayload payload) {
    _pairings.removeWhere((p) => p.isExpired());
    _pairings.add(payload);
    while (_pairings.length > 4) {
      _pairings.removeAt(0);
    }
  }

  final Map<String, SecureChannel> _sessions = <String, SecureChannel>{};

  int get port => _server?.port ?? 0;
  bool get isRunning => _server != null;

  Future<int> start() async {
    if (_server != null) return port;
    if (!downloadDirectory.existsSync()) {
      await downloadDirectory.create(recursive: true);
    }
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    server.listen(_handle, onError: (Object _) {});
    return server.port;
  }

  Future<void> stop() async {
    _sessions.clear();
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      switch (request.uri.path) {
        case NearlinkProtocol.epPing:
          await _text(request, 200, 'ok');
          break;
        case NearlinkProtocol.epInfo:
          await _handleInfo(request);
          break;
        case NearlinkProtocol.epHandshake:
          await _handleHandshake(request);
          break;
        case NearlinkProtocol.epPair:
          await _handlePair(request);
          break;
        case NearlinkProtocol.epUpload:
          await _handleUpload(request);
          break;
        case NearlinkProtocol.epClipboard:
          await _handleClipboard(request);
          break;
        case NearlinkProtocol.epMessage:
          await _handleMessage(request);
          break;
        case NearlinkProtocol.epPairRequest:
          await _handlePairRequest(request);
          break;
        case NearlinkProtocol.epUnpair:
          await _handleUnpair(request);
          break;
        case NearlinkProtocol.epIntroOffer:
          await _handleIntroOffer(request);
          break;
        case NearlinkProtocol.epIntroAccept:
          await _handleIntroOutcome(request, accepted: true);
          break;
        case NearlinkProtocol.epIntroDecline:
          await _handleIntroOutcome(request, accepted: false);
          break;
        default:
          await _json(request, 404, {'error': 'not_found'});
      }
    } catch (error) {
      try {
        await _json(request, 500, {'error': error.toString()});
      } catch (_) {
        // response already closed
      }
    }
  }

  // --- endpoints ---------------------------------------------------------

  Future<void> _handleInfo(HttpRequest request) async {
    await _json(request, 200, {
      'deviceId': identity.deviceId,
      'name': deviceName,
      'model': deviceModel,
      'platform': platform.name,
      'version': NearlinkProtocol.version,
      'fingerprint': identity.fingerprint,
      'agreementKey': identity.agreementPublicKeyBase64,
      'identityKey': identity.signingPublicKeyBase64,
    });
  }

  Future<void> _handleHandshake(HttpRequest request) async {
    final body = await _readJson(request);
    final peerId = body['deviceId'] as String;
    final peerAgreementKey = base64Decode(body['agreementKey'] as String);
    final peerNonce = base64Decode(body['nonce'] as String);

    // Our nonce; the salt is initiatorNonce || responderNonce.
    final localNonce = SecureChannel.randomBytes(32);
    final salt = concatBytes([peerNonce, localNonce]);

    final sessionKey = await SecureChannel.deriveSessionKey(
      localKeyPair: identity.agreementKeyPair,
      remotePublicKey: SimplePublicKey(peerAgreementKey, type: KeyPairType.x25519),
      salt: salt,
      info: NearlinkProtocol.sessionInfo,
    );
    final channel = SecureChannel.create(
      sessionKey: sessionKey,
      peerFingerprint: (body['fingerprint'] as String?) ?? '',
    );
    final mac = await channel.confirmationMac(
      localDeviceId: peerId,
      remoteDeviceId: identity.deviceId,
      localNonce: peerNonce,
      remoteNonce: localNonce,
    );
    _sessions[peerId] = channel;

    await _json(request, 200, {
      'deviceId': identity.deviceId,
      'name': deviceName,
      'model': deviceModel,
      'fingerprint': identity.fingerprint,
      'agreementKey': identity.agreementPublicKeyBase64,
      'nonce': base64Encode(localNonce),
      'mac': mac,
    });
  }

  Future<void> _handlePair(HttpRequest request) async {
    final body = await _readJson(request);
    final secret = body['secret'] as String? ?? '';

    _pairings.removeWhere((p) => p.isExpired());
    PairingPayload? matched;
    for (final candidate in _pairings) {
      if (secret == candidate.token || secret == candidate.pin) {
        matched = candidate;
        break;
      }
    }
    if (matched == null) {
      await _json(request, 403, {'error': 'bad_pairing_secret'});
      return;
    }

    final device = TrustedDevice(
      deviceId: body['deviceId'] as String,
      name: body['name'] as String,
      platform: platformFromString(body['platform'] as String?),
      model: body['model'] as String? ?? '',
      identityKey: body['identityKey'] as String,
      agreementKey: body['agreementKey'] as String,
      fingerprint: body['fingerprint'] as String,
      pairedAt: DateTime.now(),
      lastSeen: DateTime.now(),
    );
    await delegate.onPaired(device);
    _pairings.remove(matched);

    await _json(request, 200, {
      'ok': true,
      'deviceId': identity.deviceId,
      'name': deviceName,
      'model': deviceModel,
      'platform': platform.name,
      'fingerprint': identity.fingerprint,
      'identityKey': identity.signingPublicKeyBase64,
      'agreementKey': identity.agreementPublicKeyBase64,
    });
  }

  Future<void> _handleUpload(HttpRequest request) async {
    final peerId = request.headers.value(NearlinkProtocol.hDeviceId);
    final transferId = request.headers.value(NearlinkProtocol.hTransferId) ?? '';
    final channel = peerId == null ? null : _sessions[peerId];
    if (peerId == null || channel == null) {
      await _json(request, 401, {'error': 'no_session'});
      return;
    }
    if (!isTrusted(peerId)) {
      await _json(request, 403, {'error': 'untrusted'});
      return;
    }

    final rawName = request.headers.value(NearlinkProtocol.hItemName) ?? '';
    final fileName = _safeName(
      rawName.isEmpty ? 'nearlink-file' : utf8.decode(base64Decode(rawName)),
    );
    final declaredSize =
        int.tryParse(request.headers.value(NearlinkProtocol.hItemSize) ?? '') ?? 0;

    if (declaredSize > NearlinkProtocol.maxFileBytes) {
      await _json(request, 413, {'error': 'too_large'});
      return;
    }

    final target = _uniqueTarget(fileName);
    final sink = target.openWrite();
    final reader = FrameCodec.reader();
    var received = 0;

    try {
      await for (final chunk in request) {
        reader.add(chunk);
        List<int>? frame = reader.next();
        while (frame != null) {
          final plain = await channel.open(frame);
          received += plain.length;
          if (received > NearlinkProtocol.maxFileBytes) {
            throw const FormatException('declared size exceeded');
          }
          sink.add(plain);
          frame = reader.next();
        }
      }
      if (declaredSize > 0 && received != declaredSize) {
        throw FormatException(
          'size mismatch: declared $declaredSize, received $received',
        );
      }
      await sink.flush();
      await sink.close();
    } catch (error) {
      await sink.close();
      if (target.existsSync()) await target.delete();
      await _json(request, 400, {'error': 'bad_payload'});
      return;
    }

    await delegate.onFileReceived(
      fromDeviceId: peerId,
      fromName: request.headers.value(NearlinkProtocol.hFingerprint) ?? peerId,
      transferId: transferId,
      fileName: fileName,
      size: received,
      path: target.path,
    );

    await _json(request, 200, {'ok': true, 'bytes': received});
  }

  Future<void> _handleClipboard(HttpRequest request) async {
    final peerId = request.headers.value(NearlinkProtocol.hDeviceId);
    final channel = peerId == null ? null : _sessions[peerId];
    if (peerId == null || channel == null) {
      await _json(request, 401, {'error': 'no_session'});
      return;
    }
    if (!isTrusted(peerId)) {
      await _json(request, 403, {'error': 'untrusted'});
      return;
    }

    final raw = await utf8.decoder.bind(request).join();
    if (raw.length > NearlinkProtocol.maxClipboardBytes * 2) {
      await _json(request, 413, {'error': 'too_large'});
      return;
    }

    final text = await channel.openString(raw.trim());
    await delegate.onClipboardReceived(
      fromDeviceId: peerId,
      fromName: request.headers.value(NearlinkProtocol.hFingerprint) ?? peerId,
      text: text,
    );
    await _json(request, 200, {'ok': true});
  }

  Future<void> _handleMessage(HttpRequest request) async {
    final peerId = request.headers.value(NearlinkProtocol.hDeviceId);
    final channel = peerId == null ? null : _sessions[peerId];
    if (peerId == null || channel == null) {
      await _json(request, 401, {'error': 'no_session'});
      return;
    }
    if (!isTrusted(peerId)) {
      await _json(request, 403, {'error': 'untrusted'});
      return;
    }

    final raw = await utf8.decoder.bind(request).join();
    if (raw.length > NearlinkProtocol.maxMessageBytes * 2) {
      await _json(request, 413, {'error': 'too_large'});
      return;
    }

    final opened = await channel.openString(raw.trim());
    final json = jsonDecode(opened) as Map<String, dynamic>;
    final text = (json['text'] as String? ?? '').trim();
    if (text.isEmpty) {
      await _json(request, 400, {'error': 'empty'});
      return;
    }

    await delegate.onMessageReceived(
      fromDeviceId: peerId,
      fromName: request.headers.value(NearlinkProtocol.hFingerprint) ?? peerId,
      text: text,
      group: json['group'] as String?,
    );
    await _json(request, 200, {'ok': true});
  }

  /// A peer asked to pair, offering its own single-use secret. We hand the
  /// whole payload to the app, which prompts the person to accept. Accepting
  /// calls back into that payload's `/pair`, so both sides end up trusted with
  /// nothing typed by hand.
  Future<void> _handlePairRequest(HttpRequest request) async {
    final body = await _readJson(request);

    PairingPayload requester;
    try {
      requester = PairingPayload.fromJson(body);
    } catch (_) {
      await _json(request, 400, {'error': 'bad_request'});
      return;
    }

    if (requester.deviceId == identity.deviceId) {
      await _json(request, 400, {'error': 'self'});
      return;
    }
    if (requester.isExpired()) {
      await _json(request, 410, {'error': 'expired'});
      return;
    }

    // Trust the address the request actually came from over the one the
    // requester advertised, which can be the wrong interface on a
    // multi-homed machine.
    final observed = request.connectionInfo?.remoteAddress.address;
    if (observed != null && observed.isNotEmpty) {
      requester = requester.copyWith(host: observed);
    }

    await delegate.onPairRequest(requester);
    await _json(request, 200, {'ok': true});
  }

  /// A trusted device is telling us it removed us. Only a currently trusted
  /// device may do this, so it cannot be used to revoke someone else.
  Future<void> _handleUnpair(HttpRequest request) async {
    final peerId = request.headers.value(NearlinkProtocol.hDeviceId);
    if (peerId == null) {
      await _json(request, 400, {'error': 'missing_device'});
      return;
    }
    if (!isTrusted(peerId)) {
      await _json(request, 403, {'error': 'untrusted'});
      return;
    }
    _sessions.remove(peerId);
    await delegate.onUnpaired(peerId);
    await _json(request, 200, {'ok': true});
  }

  /// A trusted device is introducing us to another of its devices. Only a
  /// device we already trust may introduce anyone.
  Future<void> _handleIntroOffer(HttpRequest request) async {
    final peerId = request.headers.value(NearlinkProtocol.hDeviceId);
    if (peerId == null || !isTrusted(peerId)) {
      await _json(request, 403, {'error': 'untrusted'});
      return;
    }
    final body = await _readJson(request);
    IntroOffer offer;
    try {
      offer = IntroOffer.fromJson(body);
    } catch (_) {
      await _json(request, 400, {'error': 'bad_request'});
      return;
    }
    if (offer.introId.isEmpty || offer.secret.isEmpty) {
      await _json(request, 400, {'error': 'missing_intro'});
      return;
    }
    await delegate.onIntroOffer(offer);
    await _json(request, 200, {'ok': true});
  }

  /// A consent decision from one of the two devices being introduced. They
  /// do not trust each other yet, so this cannot require a session — the app
  /// checks that the sender is actually part of the introduction.
  Future<void> _handleIntroOutcome(
    HttpRequest request, {
    required bool accepted,
  }) async {
    final body = await _readJson(request);
    final introId = body['introId'] as String? ?? '';
    if (introId.isEmpty) {
      await _json(request, 400, {'error': 'missing_intro'});
      return;
    }
    var from = IntroPeer.fromJson(
      (body['from'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
    );
    // Believe the address we saw it come from over the advertised one.
    final observed = request.connectionInfo?.remoteAddress.address;
    if (observed != null && observed.isNotEmpty) {
      from = from.copyWith(host: observed);
    }
    if (accepted) {
      await delegate.onIntroAccepted(introId: introId, from: from);
    } else {
      await delegate.onIntroDeclined(introId: introId, from: from);
    }
    await _json(request, 200, {'ok': true});
  }

  // --- helpers -----------------------------------------------------------

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    if (body.isEmpty) return <String, dynamic>{};
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// Avoid overwriting an earlier file of the same name.
  File _uniqueTarget(String fileName) {
    var candidate = File('${downloadDirectory.path}/$fileName');
    if (!candidate.existsSync()) return candidate;
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    var n = 2;
    while (candidate.existsSync() && n < 1000) {
      candidate = File('${downloadDirectory.path}/$stem ($n)$ext');
      n++;
    }
    return candidate;
  }

  String _safeName(String name) {
    final base = name.split(RegExp(r'[/\\]')).last.trim();
    final cleaned = base.replaceAll(RegExp(r'[^\w\-. ]'), '_');
    if (cleaned.isEmpty) return 'nearlink-file';
    return cleaned.length > 180 ? cleaned.substring(cleaned.length - 180) : cleaned;
  }

  Future<void> _json(HttpRequest request, int status, Object data) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(data));
    await request.response.close();
  }

  Future<void> _text(HttpRequest request, int status, String body) async {
    request.response.statusCode = status;
    request.response.write(body);
    await request.response.close();
  }
}
