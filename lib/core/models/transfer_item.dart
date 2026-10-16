/// A single item in the transfer activity list: either a file or a clipboard
/// payload, moving in one direction between this device and a peer.
library;

enum TransferDirection { outgoing, incoming }

enum TransferKind { file, clipboard, message }

enum TransferStatus { queued, active, delivered, failed }

class TransferItem {
  const TransferItem({
    required this.id,
    required this.kind,
    required this.direction,
    required this.peerId,
    required this.peerName,
    required this.title,
    required this.bytes,
    required this.timestamp,
    this.transferred = 0,
    this.status = TransferStatus.queued,
    this.error,
    this.payload,
    this.filePath,
    this.groupName,
  });

  final String id;
  final TransferKind kind;
  final TransferDirection direction;
  final String peerId;
  final String peerName;

  /// File name, or a short preview for clipboard items.
  final String title;

  /// Total size in bytes (0 for clipboard text).
  final int bytes;

  /// Bytes transferred so far.
  final int transferred;

  final TransferStatus status;
  final DateTime timestamp;
  final String? error;

  /// The clipboard text itself, kept so a history entry can be re-copied.
  /// Capped in length; null for file transfers.
  final String? payload;

  /// Where the file lives on this device, so an activity entry can be opened.
  /// Null for clipboard and message items.
  final String? filePath;

  /// For messages sent to more than one device, the group label.
  final String? groupName;

  double get progress {
    if (status == TransferStatus.delivered) return 1;
    if (bytes <= 0) return 0;
    return (transferred / bytes).clamp(0, 1);
  }

  TransferItem copyWith({
    int? transferred,
    TransferStatus? status,
    String? error,
  }) =>
      TransferItem(
        id: id,
        kind: kind,
        direction: direction,
        peerId: peerId,
        peerName: peerName,
        title: title,
        bytes: bytes,
        transferred: transferred ?? this.transferred,
        status: status ?? this.status,
        timestamp: timestamp,
        error: error ?? this.error,
        payload: payload,
        filePath: filePath,
        groupName: groupName,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'direction': direction.name,
        'peerId': peerId,
        'peerName': peerName,
        'title': title,
        'bytes': bytes,
        'transferred': transferred,
        'status': status.name,
        'timestamp': timestamp.toIso8601String(),
        'error': error,
        'payload': payload,
        'filePath': filePath,
        'groupName': groupName,
      };

  factory TransferItem.fromJson(Map<String, dynamic> json) => TransferItem(
        id: json['id'] as String,
        kind: TransferKind.values.byName(json['kind'] as String),
        direction: TransferDirection.values.byName(json['direction'] as String),
        peerId: json['peerId'] as String,
        peerName: json['peerName'] as String,
        title: json['title'] as String,
        bytes: json['bytes'] as int,
        transferred: json['transferred'] as int? ?? 0,
        status: TransferStatus.values.byName(json['status'] as String),
        timestamp: DateTime.parse(json['timestamp'] as String),
        error: json['error'] as String?,
        payload: json['payload'] as String?,
        filePath: json['filePath'] as String?,
        groupName: json['groupName'] as String?,
      );
}
