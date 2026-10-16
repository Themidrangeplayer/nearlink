import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nearlink/core/models/transfer_item.dart';
import 'package:nearlink/theme/app_theme.dart';
import 'package:nearlink/widgets/nearlink_card.dart';
import 'package:nearlink/widgets/transfer_row.dart';

void main() {
  testWidgets('NearlinkCard renders child with theme', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NearlinkTheme.light(),
        home: const Scaffold(
          body: NearlinkCard(
            child: Text('Card Content'),
          ),
        ),
      ),
    );

    expect(find.text('Card Content'), findsOneWidget);
    expect(find.byType(NearlinkCard), findsOneWidget);
  });

  testWidgets('SectionHeader renders title and subtitle', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NearlinkTheme.light(),
        home: const Scaffold(
          body: SectionHeader(
            title: 'Trusted devices',
            subtitle: 'Ready for automatic sharing',
          ),
        ),
      ),
    );

    expect(find.text('Trusted devices'), findsOneWidget);
    expect(find.text('Ready for automatic sharing'), findsOneWidget);
  });

  testWidgets('TransferRow renders chain groupName in metadata', (WidgetTester tester) async {
    final item = TransferItem(
      id: 'chain-1',
      kind: TransferKind.file,
      direction: TransferDirection.outgoing,
      peerId: 'peer-a',
      peerName: 'Pixel 8',
      title: 'archive.zip',
      bytes: 1048576,
      transferred: 1048576,
      timestamp: DateTime.now(),
      status: TransferStatus.delivered,
      filePath: '/tmp/archive.zip',
      groupName: 'Chain of 3',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: NearlinkTheme.light(),
        home: Scaffold(
          body: TransferRow(item: item),
        ),
      ),
    );

    expect(find.text('archive.zip'), findsOneWidget);
    expect(find.textContaining('Chain of 3'), findsOneWidget);
  });
}

