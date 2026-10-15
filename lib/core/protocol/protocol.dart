/// Wire protocol constants for Nearlink v1.
///
/// Discovery rides on mDNS/DNS-SD (see [serviceType]). Transfer and control
/// messages ride on a small HTTP/1.1 API whose bodies are always sealed with
/// the session key negotiated in the handshake, so payloads are end-to-end
/// encrypted regardless of the transport.
class NearlinkProtocol {
  NearlinkProtocol._();

  static const String version = '1';
  static const String serviceType = '_nearlink._tcp';
  static const String qrScheme = 'nearlink';

  // --- mDNS TXT record keys ---------------------------------------------
  static const String txtId = 'id';
  static const String txtName = 'name';
  static const String txtPlatform = 'platform';
  static const String txtModel = 'model';
  static const String txtFingerprint = 'fp';
  static const String txtAgreementKey = 'key';
  static const String txtVersion = 'v';

  // --- HTTP endpoints ----------------------------------------------------
  static const String epPing = '/api/v1/ping';
  static const String epInfo = '/api/v1/info';
  static const String epHandshake = '/api/v1/handshake';
  static const String epPair = '/api/v1/pair';
  static const String epUpload = '/api/v1/upload';
  static const String epClipboard = '/api/v1/clipboard';
  static const String epMessage = '/api/v1/message';
  static const String epPairRequest = '/api/v1/pair/request';
  static const String epUnpair = '/api/v1/unpair';
  static const String epIntroOffer = '/api/v1/intro/offer';
  static const String epIntroAccept = '/api/v1/intro/accept';
  static const String epIntroDecline = '/api/v1/intro/decline';

  // --- HTTP headers ------------------------------------------------------
  static const String hDeviceId = 'x-nearlink-device';
  static const String hFingerprint = 'x-nearlink-fingerprint';
  static const String hTransferId = 'x-nearlink-transfer';
  static const String hItemName = 'x-nearlink-name';
  static const String hItemSize = 'x-nearlink-size';
  static const String hItemMime = 'x-nearlink-mime';

  /// HKDF `info` string binding derived keys to this protocol version.
  static const String sessionInfo = 'nearlink/v1/session';

  /// UDP port for the broadcast beacon used by the fallback discovery path.
  static const int broadcastPort = 47821;

  /// How often a device repeats its beacon, and how long a silent peer is kept.
  static const int beaconIntervalSeconds = 2;
  static const int peerTimeoutSeconds = 12;

  /// Chunk size for streamed file encryption.
  static const int chunkSize = 64 * 1024;

  /// Largest clipboard payload we will accept, in bytes of UTF-8.
  static const int maxClipboardBytes = 256 * 1024;

  /// Largest message we will accept, in bytes of UTF-8.
  static const int maxMessageBytes = 64 * 1024;

  /// Largest single file we will accept, in bytes.
  static const int maxFileBytes = 8 * 1024 * 1024 * 1024;
}
