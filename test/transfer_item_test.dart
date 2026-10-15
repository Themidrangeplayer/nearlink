import 'package:flutter_test/flutter_test.dart';
import 'package:nearlink/core/models/transfer_item.dart';
import 'package:nearlink/widgets/format.dart';

void main() {
  test('progress and copyWith behave', () {
    final item = TransferItem(
      id: '1',
      kind: TransferKind.file,
      direction: TransferDirection.outgoing,
      peerId: 'peer',
      peerName: 'Peer',
      title: 'video.mp4',
      bytes: 1000,
      transferred: 250,
      timestamp: DateTime.now(),
      status: TransferStatus.active,
    );

    expect(item.progress, closeTo(0.25, 0.0001));

    final done = item.copyWith(
      transferred: 1000,
      status: TransferStatus.delivered,
    );
    expect(done.progress, 1.0);
    expect(done.status, TransferStatus.delivered);
  });

  test('JSON round-trips', () {
    final item = TransferItem(
      id: 'x',
      kind: TransferKind.clipboard,
      direction: TransferDirection.incoming,
      peerId: 'p',
      peerName: 'Peer',
      title: 'hello',
      bytes: 5,
      transferred: 5,
      timestamp: DateTime.now(),
      status: TransferStatus.delivered,
    );
    final restored = TransferItem.fromJson(item.toJson());
    expect(restored.id, item.id);
    expect(restored.kind, TransferKind.clipboard);
    expect(restored.direction, TransferDirection.incoming);
    expect(restored.title, 'hello');
  });

  _clipboardPayloadSuite();
  _messageSuite();

  test('formatBytes renders sensible units', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1024), '1.0 KB');
    expect(formatBytes(842 * 1024 * 1024), '842 MB');
  });
}

void _clipboardPayloadSuite() {
  test('clipboard payload survives JSON and copyWith', () {
    final item = TransferItem(
      id: 'c1',
      kind: TransferKind.clipboard,
      direction: TransferDirection.outgoing,
      peerId: 'p',
      peerName: 'Peer',
      title: 'hello',
      bytes: 5,
      transferred: 5,
      timestamp: DateTime.now(),
      status: TransferStatus.delivered,
      payload: 'hello world',
    );

    final restored = TransferItem.fromJson(item.toJson());
    expect(restored.payload, 'hello world');

    final updated = item.copyWith(status: TransferStatus.failed);
    expect(updated.payload, 'hello world');
  });

  test('file transfers carry no payload', () {
    final item = TransferItem(
      id: 'f1',
      kind: TransferKind.file,
      direction: TransferDirection.outgoing,
      peerId: 'p',
      peerName: 'Peer',
      title: 'a.zip',
      bytes: 10,
      timestamp: DateTime.now(),
    );
    expect(item.payload, isNull);
    expect(TransferItem.fromJson(item.toJson()).payload, isNull);
  });
}

void _messageSuite() {
  test('message kind round-trips with its group and payload', () {
    final item = TransferItem(
      id: 'm1',
      kind: TransferKind.message,
      direction: TransferDirection.outgoing,
      peerId: 'group',
      peerName: 'Group · A, B',
      title: 'hello team',
      bytes: 10,
      transferred: 10,
      timestamp: DateTime.now(),
      status: TransferStatus.delivered,
      payload: 'hello team',
      groupName: 'Group · A, B',
    );
    final restored = TransferItem.fromJson(item.toJson());
    expect(restored.kind, TransferKind.message);
    expect(restored.groupName, 'Group · A, B');
    expect(restored.payload, 'hello team');
  });

  test('file path survives a round-trip', () {
    final item = TransferItem(
      id: 'f2',
      kind: TransferKind.file,
      direction: TransferDirection.incoming,
      peerId: 'p',
      peerName: 'Peer',
      title: 'photo.jpg',
      bytes: 100,
      transferred: 100,
      timestamp: DateTime.now(),
      status: TransferStatus.delivered,
      filePath: '/tmp/photo.jpg',
    );
    expect(TransferItem.fromJson(item.toJson()).filePath, '/tmp/photo.jpg');
  });
}
