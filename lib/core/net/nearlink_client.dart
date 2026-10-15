import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../crypto/device_identity.dart';
import '../crypto/pairing_payload.dart';
import '../models/intro.dart';
import '../crypto/secure_channel.dart';
import '../models/device.dart';
import '../protocol/protocol.dart';
import '../utils/bytes.dart';

/// A live, authenticated session with one peer.
class NearlinkSession {
  NearlinkSession({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.fingerprint,
    required this.channel,
    required this.host,
    required this.port,
  });

  final String deviceId;
  final String name;
  final DevicePlatform platform;
  final String fingerprint;
  final SecureChannel channel;
  final String host;
  final int port;
}

/// Public metadata a peer exposes over `/info`.
class PeerInfo {
  PeerInfo({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.fingerprint,
    required this.agreementKey,
    required this.identityKey,
  });

  final String deviceId;
  final String name;
  final DevicePlatform platform;
  final String fingerprint;
  final String agreementKey;
  final String identityKey;
}

/// The sending half of Nearlink.
class NearlinkClient {
  NearlinkClient({required this.identity});

  final DeviceIdentity identity;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12);
  final Uuid _uuid = const Uuid();
  final Map<String, NearlinkSession> _sessions = <String, NearlinkSession>{};

  /// Drop a cached session (e.g. after the peer restarted).
  void forget(String deviceId) => _sessions.remove(deviceId);

  void dispose() {
    _sessions.clear();
    _http.close(force: true);
  }

  Uri _uri(String host, int port, String path) =>
      Uri.parse('http://$host:$port$path');

  Future<PeerInfo> fetchInfo(String host, int port) async {
    final request = await _http.getUrl(_uri(host, port, NearlinkProtocol.epInfo));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) {
      throw HttpException('info failed: ${response.statusCode}');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    return PeerInfo(
      deviceId: json['deviceId'] as String,
      name: json['name'] as String,
      platform: platformFromString(json['platform'] as String?),
      fingerprint: json['fingerprint'] as String,
      agreementKey: json['agreementKey'] as String,
      identityKey: json['identityKey'] as String,
    );
  }

  /// Perform the X25519 handshake and return an authenticated session.
  ///
  /// If [expectedFingerprint] is supplied (from a pairing payload or the trust
  /// store), the peer's advertised fingerprint must match or the handshake is
  /// aborted — this is what defeats a man-in-the-middle on the LAN.
  Future<NearlinkSession> handshake({
    required String host,
    required int port,
    String? expectedFingerprint,
    bool useCache = true,
  }) async {
    if (useCache) {
      for (final cached in _sessions.values) {
        if (cached.host == host && cached.port == port) return cached;
      }
    }

    final localNonce = SecureChannel.randomBytes(32);
    final payload = jsonEncode({
      'deviceId': identity.deviceId,
      'agreementKey': identity.agreementPublicKeyBase64,
      'identityKey': identity.signingPublicKeyBase64,
      'fingerprint': identity.fingerprint,
      'nonce': base64Encode(localNonce),
    });

    final request =
        await _http.postUrl(_uri(host, port, NearlinkProtocol.epHandshake));
    request.headers.contentType = ContentType.json;
    request.write(payload);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) {
      throw HttpException('handshake failed: ${response.statusCode}');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;

    final peerFingerprint = json['fingerprint'] as String;
    if (expectedFingerprint != null &&
        expectedFingerprint.isNotEmpty &&
        peerFingerprint != expectedFingerprint) {
      throw HandshakeException(
        'Peer fingerprint does not match the trusted value',
      );
    }

    final peerNonce = base64Decode(json['nonce'] as String);
    final peerAgreementKey = base64Decode(json['agreementKey'] as String);
    final salt = concatBytes([localNonce, peerNonce]);

    final sessionKey = await SecureChannel.deriveSessionKey(
      localKeyPair: identity.agreementKeyPair,
      remotePublicKey:
          SimplePublicKey(peerAgreementKey, type: KeyPairType.x25519),
      salt: salt,
      info: NearlinkProtocol.sessionInfo,
    );
    final channel = SecureChannel.create(
      sessionKey: sessionKey,
      peerFingerprint: peerFingerprint,
    );

    final expectedMac = await channel.confirmationMac(
      localDeviceId: identity.deviceId,
      remoteDeviceId: json['deviceId'] as String,
      localNonce: localNonce,
      remoteNonce: peerNonce,
    );
    if (expectedMac != json['mac']) {
      throw HandshakeException('Session key confirmation failed');
    }

    final session = NearlinkSession(
      deviceId: json['deviceId'] as String,
      name: json['name'] as String,
      platform: platformFromString(json['platform'] as String?),
      fingerprint: peerFingerprint,
      channel: channel,
      host: host,
      port: port,
    );
    _sessions[session.deviceId] = session;
    return session;
  }

  /// Stream a file to a peer, sealing each 64 KiB chunk as it goes.
  Future<void> sendFile({
    required NearlinkSession session,
    required String filePath,
    required String fileName,
    required int size,
    String? mime,
    void Function(int sent)? onProgress,
  }) async {
    final request = await _http.postUrl(
      _uri(session.host, session.port, NearlinkProtocol.epUpload),
    );
    request.headers.set(NearlinkProtocol.hDeviceId, identity.deviceId);
    request.headers.set(NearlinkProtocol.hTransferId, _uuid.v4());
    request.headers.set(
      NearlinkProtocol.hItemName,
      base64Encode(utf8.encode(fileName)),
    );
    request.headers.set(NearlinkProtocol.hItemSize, '$size');
    request.headers.set(NearlinkProtocol.hItemMime, mime ?? 'application/octet-stream');
    request.headers.contentType = ContentType.binary;

    final file = File(filePath);
    var sent = 0;
    await for (final chunk in file.openRead()) {
      final sealed = await session.channel.seal(chunk);
      request.add(FrameCodec.frame(sealed));
      sent += chunk.length;
      onProgress?.call(sent);
    }

    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) {
      throw HttpException('upload failed: ${response.statusCode} $body');
    }
  }

  /// Send a clipboard payload to a peer.
  Future<void> sendClipboard({
    required NearlinkSession session,
    required String text,
  }) async {
    final sealed = await session.channel.sealString(text);
    final request = await _http.postUrl(
      _uri(session.host, session.port, NearlinkProtocol.epClipboard),
    );
    request.headers.set(NearlinkProtocol.hDeviceId, identity.deviceId);
    request.headers.contentType = ContentType.text;
    request.write(sealed);
    final response = await request.close();
    await response.drain();
    if (response.statusCode != 200) {
      throw HttpException('clipboard failed: ${response.statusCode}');
    }
  }

  /// Send a chat message. [group] labels a message addressed to several
  /// devices at once.
  Future<void> sendMessage({
    required NearlinkSession session,
    required String text,
    String? group,
  }) async {
    final sealed = await session.channel.sealString(
      jsonEncode({'text': text, 'group': group}),
    );
    final request = await _http.postUrl(
      _uri(session.host, session.port, NearlinkProtocol.epMessage),
    );
    request.headers.set(NearlinkProtocol.hDeviceId, identity.deviceId);
    request.headers.contentType = ContentType.text;
    request.write(sealed);
    final response = await request.close();
    await response.drain();
    if (response.statusCode != 200) {
      throw HttpException('message failed: ${response.statusCode}');
    }
  }

  /// Ask a peer to pair. We send our own pairing payload, so that device can
  /// offer the person an Accept prompt and finish pairing with no code.
  Future<void> requestPairing({
    required String host,
    required int port,
    required PairingPayload payload,
  }) async {
    final request = await _http.postUrl(
      _uri(host, port, NearlinkProtocol.epPairRequest),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(payload.toJson()));
    final response = await request.close();
    await response.drain();
    if (response.statusCode != 200) {
      throw HttpException('pair request failed: ${response.statusCode}');
    }
  }

  /// Hand a device an introduction: "my other device would like to connect
  /// with you". Only a device that already trusts us may do this.
  Future<void> offerIntro({
    required String host,
    required int port,
    required IntroOffer offer,
  }) async {
    final request = await _http.postUrl(
      _uri(host, port, NearlinkProtocol.epIntroOffer),
    );
    request.headers.set(NearlinkProtocol.hDeviceId, identity.deviceId);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(offer.toJson()));
    final response = await request.close();
    await response.drain();
    if (response.statusCode != 200) {
      throw HttpException('intro offer failed: ${response.statusCode}');
    }
  }

  /// Report a consent decision for an introduction, to the other device and
  /// to whoever introduced them.
  Future<void> sendIntroOutcome({
    required String host,
    required int port,
    required String introId,
    required IntroPeer from,
    required bool accepted,
  }) async {
    final request = await _http.postUrl(
      _uri(
        host,
        port,
        accepted
            ? NearlinkProtocol.epIntroAccept
            : NearlinkProtocol.epIntroDecline,
      ),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(<String, dynamic>{
      'introId': introId,
      'from': from.toJson(),
    }));
    final response = await request.close();
    await response.drain();
    if (response.statusCode != 200) {
      throw HttpException('intro outcome failed: ${response.statusCode}');
    }
  }

  /// Tell a peer we have removed it, so it stops listing us as trusted.
  Future<void> unpair({required String host, required int port}) async {
    final request = await _http.postUrl(
      _uri(host, port, NearlinkProtocol.epUnpair),
    );
    request.headers.set(NearlinkProtocol.hDeviceId, identity.deviceId);
    request.headers.contentType = ContentType.json;
    request.write('{}');
    final response = await request.close();
    await response.drain();
    if (response.statusCode != 200) {
      throw HttpException('unpair failed: ${response.statusCode}');
    }
  }

  /// Complete pairing with a peer that is currently offering a pairing secret.
  Future<TrustedDevice> pairWith({
    required String host,
    required int port,
    required String secret,
    required String name,
    required String platform,
    required String model,
  }) async {
    final request =
        await _http.postUrl(_uri(host, port, NearlinkProtocol.epPair));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'secret': secret,
      'deviceId': identity.deviceId,
      'name': name,
      'platform': platform,
      'model': model,
      'identityKey': identity.signingPublicKeyBase64,
      'agreementKey': identity.agreementPublicKeyBase64,
      'fingerprint': identity.fingerprint,
    }));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) {
      throw HttpException('pairing failed: ${response.statusCode} $body');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    return TrustedDevice(
      deviceId: json['deviceId'] as String,
      name: json['name'] as String,
      platform: platformFromString(json['platform'] as String?),
      model: json['model'] as String? ?? '',
      identityKey: json['identityKey'] as String,
      agreementKey: json['agreementKey'] as String,
      fingerprint: json['fingerprint'] as String,
      pairedAt: DateTime.now(),
      lastSeen: DateTime.now(),
      lastHost: host,
      lastPort: port,
    );
  }
}
