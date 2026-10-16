import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nearlink/core/crypto/device_identity.dart';
import 'package:nearlink/core/crypto/pairing_payload.dart';
import 'package:nearlink/core/models/device.dart';
import 'package:nearlink/core/models/intro.dart';
import 'package:nearlink/core/net/nearlink_client.dart';
import 'package:nearlink/core/net/nearlink_server.dart';

class RecordingDelegate implements NearlinkServerDelegate {
  final List<TrustedDevice> paired = <TrustedDevice>[];
  final List<String> messages = <String>[];
  final List<String> clipboards = <String>[];
  final List<String> files = <String>[];
  final List<PairingPayload> pairRequests = <PairingPayload>[];
  final List<String> unpairs = <String>[];
  final List<IntroOffer> introOffers = <IntroOffer>[];
  final List<String> introAccepts = <String>[];
  final List<String> introDeclines = <String>[];

  @override
  Future<void> onPaired(TrustedDevice device) async => paired.add(device);

  @override
  Future<void> onFileReceived({
    required String fromDeviceId,
    required String fromName,
    required String transferId,
    required String fileName,
    required int size,
    required String path,
  }) async =>
      files.add(fileName);

  @override
  Future<void> onClipboardReceived({
    required String fromDeviceId,
    required String fromName,
    required String text,
  }) async =>
      clipboards.add(text);

  @override
  Future<void> onMessageReceived({
    required String fromDeviceId,
    required String fromName,
    required String text,
    String? group,
  }) async =>
      messages.add(text);

  @override
  Future<void> onPairRequest(PairingPayload requester) async =>
      pairRequests.add(requester);

  @override
  Future<void> onUnpaired(String deviceId) async => unpairs.add(deviceId);

  @override
  Future<void> onIntroOffer(IntroOffer offer) async => introOffers.add(offer);

  @override
  Future<void> onIntroAccepted({
    required String introId,
    required IntroPeer from,
  }) async =>
      introAccepts.add(introId);

  @override
  Future<void> onIntroDeclined({
    required String introId,
    required IntroPeer from,
  }) async =>
      introDeclines.add(introId);
}

Future<NearlinkServer> startServer(
  DeviceIdentity identity,
  RecordingDelegate delegate,
  Set<String> trusted,
  Directory dir,
) async {
  final server = NearlinkServer(
    identity: identity,
    deviceName: identity.deviceId,
    deviceModel: 'test',
    platform: DevicePlatform.linux,
    delegate: delegate,
    isTrusted: trusted.contains,
    downloadDirectory: dir,
  );
  await server.start();
  return server;
}

IntroPeer peerOf(DeviceIdentity id, NearlinkServer server) => IntroPeer(
      deviceId: id.deviceId,
      name: id.deviceId,
      platform: DevicePlatform.linux,
      model: 'test',
      host: '127.0.0.1',
      port: server.port,
      fingerprint: id.fingerprint,
    );

/// Stand in for the consenting device registering the introducer's secret.
void registerSecret(NearlinkServer server, IntroPeer other, String secret) {
  server.offerPairing(PairingPayload(
    deviceId: other.deviceId,
    deviceName: other.name,
    platform: other.platform,
    model: other.model,
    agreementKey: other.fingerprint,
    identityKey: '',
    fingerprint: other.fingerprint,
    host: other.host,
    port: other.port,
    token: secret,
    pin: secret,
    createdAt: DateTime.now(),
  ));
}

void main() {
  test('an introduction is delivered and the shared secret pairs both sides',
      () async {
    final dir = Directory.systemTemp.createTempSync('nl-intro');
    final idA = await DeviceIdentity.generate('intro-a');
    final idB = await DeviceIdentity.generate('intro-b');
    final idC = await DeviceIdentity.generate('intro-c');

    final delA = RecordingDelegate();
    final delB = RecordingDelegate();
    final delC = RecordingDelegate();
    final trustedA = <String>{};
    final trustedB = <String>{'intro-a'};
    final trustedC = <String>{'intro-a'};

    final serverA = await startServer(idA, delA, trustedA, dir);
    final serverB = await startServer(idB, delB, trustedB, dir);
    final serverC = await startServer(idC, delC, trustedC, dir);

    final clientA = NearlinkClient(identity: idA);
    final clientB = NearlinkClient(identity: idB);
    final clientC = NearlinkClient(identity: idC);

    final aPeer = peerOf(idA, serverA);
    final bPeer = peerOf(idB, serverB);
    final cPeer = peerOf(idC, serverC);

    const introId = 'intro-1';
    const secret = 'shared-one-time-secret';

    // A vouches for B and C to each other.
    await clientA.offerIntro(
      host: '127.0.0.1',
      port: serverB.port,
      offer: IntroOffer(
        introId: introId,
        secret: secret,
        introducer: aPeer,
        counterpart: cPeer,
      ),
    );
    await clientA.offerIntro(
      host: '127.0.0.1',
      port: serverC.port,
      offer: IntroOffer(
        introId: introId,
        secret: secret,
        introducer: aPeer,
        counterpart: bPeer,
      ),
    );

    expect(delB.introOffers, hasLength(1));
    expect(delB.introOffers.first.counterpart.deviceId, 'intro-c');
    expect(delC.introOffers, hasLength(1));
    expect(delC.introOffers.first.counterpart.deviceId, 'intro-b');

    // Both consent, so both register the secret.
    registerSecret(serverB, cPeer, secret);
    registerSecret(serverC, bPeer, secret);

    // The lower id makes the call; either way the pairing is mutual.
    final initiator = 'intro-b'.compareTo('intro-c') < 0 ? clientB : clientC;
    final targetPort = 'intro-b'.compareTo('intro-c') < 0
        ? serverC.port
        : serverB.port;
    final targetId = 'intro-b'.compareTo('intro-c') < 0 ? idC : idB;

    final other = await initiator.pairWith(
      host: '127.0.0.1',
      port: targetPort,
      secret: secret,
      name: 'initiator',
      platform: 'linux',
      model: 'test',
    );
    expect(other.deviceId, targetId.deviceId);

    // The target recorded the initiator as trusted.
    final targetDelegate = targetId.deviceId == 'intro-c' ? delC : delB;
    final initiatorId = targetId.deviceId == 'intro-c' ? 'intro-b' : 'intro-c';
    expect(
      targetDelegate.paired.map((d) => d.deviceId),
      contains(initiatorId),
    );

    await serverA.stop();
    await serverB.stop();
    await serverC.stop();
    clientA.dispose();
    clientB.dispose();
    clientC.dispose();
  });

  test('a decline is delivered, and without both secrets no pairing happens',
      () async {
    final dir = Directory.systemTemp.createTempSync('nl-intro-decline');
    final idA = await DeviceIdentity.generate('d-a');
    final idB = await DeviceIdentity.generate('d-b');
    final idC = await DeviceIdentity.generate('d-c');

    final delA = RecordingDelegate();
    final delB = RecordingDelegate();
    final delC = RecordingDelegate();
    final serverA = await startServer(idA, delA, <String>{}, dir);
    final serverB = await startServer(idB, delB, <String>{'d-a'}, dir);
    final serverC = await startServer(idC, delC, <String>{'d-a'}, dir);

    final clientB = NearlinkClient(identity: idB);
    final clientC = NearlinkClient(identity: idC);

    final cPeer = peerOf(idC, serverC);

    const introId = 'intro-2';
    const secret = 'secret-two';

    // Only B consents.
    registerSecret(serverB, cPeer, secret);

    // C declines and tells B.
    await clientC.sendIntroOutcome(
      host: '127.0.0.1',
      port: serverB.port,
      introId: introId,
      from: cPeer,
      accepted: false,
    );
    expect(delB.introDeclines, <String>[introId]);

    // B never registered anything for C, so a pairing with the shared secret
    // cannot succeed — a one-sided pairing is impossible.
    await expectLater(
      clientB.pairWith(
        host: '127.0.0.1',
        port: serverC.port,
        secret: secret,
        name: 'B',
        platform: 'linux',
        model: 'test',
      ),
      throwsA(anything),
    );

    await serverA.stop();
    await serverB.stop();
    await serverC.stop();
    clientB.dispose();
    clientC.dispose();
  });

  test('an untrusted device cannot offer an introduction', () async {
    final dir = Directory.systemTemp.createTempSync('nl-intro-untrusted');
    final idA = await DeviceIdentity.generate('u-a');
    final idB = await DeviceIdentity.generate('u-b');
    final delB = RecordingDelegate();
    final serverB = await startServer(idB, delB, <String>{}, dir);
    final clientA = NearlinkClient(identity: idA);
    final serverA = await startServer(idA, RecordingDelegate(), <String>{}, dir);

    await expectLater(
      clientA.offerIntro(
        host: '127.0.0.1',
        port: serverB.port,
        offer: IntroOffer(
          introId: 'x',
          secret: 'y',
          introducer: peerOf(idA, serverA),
          counterpart: peerOf(idB, serverB),
        ),
      ),
      throwsA(anything),
    );
    expect(delB.introOffers, isEmpty);

    await serverA.stop();
    await serverB.stop();
    clientA.dispose();
  });
}
