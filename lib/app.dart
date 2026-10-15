import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/models/device.dart';
import 'core/utils/bytes.dart';
import 'features/clipboard/clipboard_screen.dart';
import 'features/control_center/control_center_screen.dart';
import 'features/messaging/messaging_screen.dart';
import 'features/security/security_screen.dart';
import 'features/transfers/transfers_screen.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/format.dart';
import 'widgets/input.dart';

class NearlinkApp extends StatelessWidget {
  const NearlinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nearlink',
      debugShowCheckedModeBanner: false,
      theme: NearlinkTheme.light(),
      home: const HomeShell(),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, [this.shortLabel]);

  final String label;
  final IconData icon;

  /// Used in the bottom bar, where a long label throws the row off centre.
  final String? shortLabel;
}

const List<_NavItem> _navItems = <_NavItem>[
  _NavItem('Control center', Icons.dashboard_customize_outlined, 'Control'),
  _NavItem('Transfers', Icons.swap_vert),
  _NavItem('Messages', Icons.chat_bubble_outline),
  _NavItem('Clipboard', Icons.content_paste),
  _NavItem('Security', Icons.shield_outlined),
];

/// The responsive frame: a sidebar on wide windows, an app bar plus bottom
/// navigation on phones and narrow windows. The account is reachable in both
/// layouts, so it is never hidden just because the window is small.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final GlobalKey<ScaffoldMessengerState> _messenger =
      GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<String>? _messageSub;
  bool _pairDialogShowing = false;
  bool _unpairDialogShowing = false;
  bool _introDialogShowing = false;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _messageSub = context.read<AppState>().messages.listen((message) {
      _messenger.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Another device tapped "Pair" on us: put our code on screen for them.
    final appState = context.watch<AppState>();
    if (appState.pendingPairRequest != null && !_pairDialogShowing) {
      _pairDialogShowing = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showPairRequest(appState),
      );
    }
    if (appState.pendingUnpair != null && !_unpairDialogShowing) {
      _unpairDialogShowing = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showUnpairNotice(appState),
      );
    }
    if (appState.pendingIntro != null && !_introDialogShowing) {
      _introDialogShowing = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showIntro(appState),
      );
    }

    const screens = <Widget>[
      ControlCenterScreen(),
      TransfersScreen(),
      MessagingScreen(),
      ClipboardScreen(),
      SecurityScreen(),
    ];

    return ScaffoldMessenger(
      key: _messenger,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return Scaffold(
            appBar: wide
                ? null
                : AppBar(
                    backgroundColor: NearlinkColors.sidebar,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    titleSpacing: 16,
                    title: const Row(
                      children: [
                        _BrandMark(),
                        SizedBox(width: 10),
                        Text(
                          'nearlink',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      _AccountButton(onTap: () => _openAccount(context)),
                      const SizedBox(width: 8),
                    ],
                  ),
            body: wide
                ? Row(
                    children: [
                      _Sidebar(
                        index: _index,
                        onSelect: (i) => setState(() => _index = i),
                        onAccount: () => _openAccount(context),
                      ),
                      Expanded(child: screens[_index]),
                    ],
                  )
                : screens[_index],
            bottomNavigationBar: wide
                ? null
                : NavigationBarTheme(
                    data: NavigationBarThemeData(
                      labelTextStyle: WidgetStateProperty.all(
                        const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    child: NavigationBar(
                      selectedIndex: _index,
                      onDestinationSelected: (i) => setState(() => _index = i),
                      backgroundColor: NearlinkColors.panel,
                      indicatorColor: NearlinkColors.lime,
                      labelBehavior:
                          NavigationDestinationLabelBehavior.alwaysShow,
                      destinations: _navItems
                          .map(
                            (item) => NavigationDestination(
                              icon: Icon(item.icon),
                              label: item.shortLabel ?? item.label,
                            ),
                          )
                          .toList(),
                    ),
                  ),
          );
        },
      ),
    );
  }

  Future<void> _showPairRequest(AppState state) async {
    final requester = state.pendingPairRequest;
    if (requester == null) {
      _pairDialogShowing = false;
      return;
    }

    final descriptor = <String>[
      platformLabel(requester.platform),
      if (requester.model.isNotEmpty) requester.model,
    ].join(' · ');

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${requester.deviceName} wants to pair'),
        content: Text(
          'Accept to trust ${requester.deviceName} ($descriptor).\n\n'
          'Both devices will then be able to send files, messages and '
          'clipboard text to each other. Nothing is shared until you '
          'accept.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    _pairDialogShowing = false;
    if (accepted == true) {
      await state.acceptPairRequest();
    } else {
      state.declinePairRequest();
    }
  }

  /// One of our devices vouched for us and another of its devices. Both
  /// sides have to agree, so this is a genuine consent prompt.
  Future<void> _showIntro(AppState state) async {
    final session = state.pendingIntro;
    if (session == null) {
      _introDialogShowing = false;
      return;
    }
    final offer = session.offer;
    final descriptor = <String>[
      platformLabel(offer.counterpart.platform),
      if (offer.counterpart.model.isNotEmpty) offer.counterpart.model,
    ].join(' · ');

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${offer.introducer.name} suggests connecting'),
        content: Text(
          '${offer.introducer.name} trusts you both. Connect with '
          '${offer.counterpart.name} ($descriptor)?\n\n'
          'Both devices have to agree. If either declines, nothing is '
          'connected — so if you accept and they decline, it is called '
          'off and you will be told.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    _introDialogShowing = false;
    if (accepted == true) {
      await state.acceptIntro();
    } else {
      await state.declineIntro();
    }
  }

  /// Another device removed us. Announce it and only drop it on confirm.
  Future<void> _showUnpairNotice(AppState state) async {
    final device = state.pendingUnpair;
    if (device == null) {
      _unpairDialogShowing = false;
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('${device.name} removed this device'),
        content: Text(
          '${device.name} has removed this device from its trusted list.\n\n'
          'Confirm to drop it here too. After that, neither device can send '
          'to the other until you pair again.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    await state.acknowledgeUnpair();
    _unpairDialogShowing = false;
  }

  void _openAccount(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _DeviceSheet(),
    );
  }
}

/// Avatar button that opens the account / device sheet.
class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = context.watch<AppState>().deviceName;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            color: Color(0xFFF4CC7C),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            initialsOf(name),
            style: const TextStyle(
              color: Color(0xFF573B15),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

/// Device / account details: rename this device, and see its identity.
class _DeviceSheet extends StatefulWidget {
  const _DeviceSheet();

  @override
  State<_DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends State<_DeviceSheet> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: context.read<AppState>().deviceName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final trusted = state.trustedDevices.length;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF4CC7C),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initialsOf(state.deviceName),
                    style: const TextStyle(
                      color: Color(0xFF573B15),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.accountLabel,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$trusted trusted device${trusted == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: NearlinkColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _name,
              decoration: nearlinkInput(labelText: 'Device name'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () async {
                  final value = _name.text.trim();
                  await state.setDeviceName(
                    value.isEmpty ? state.deviceName : value,
                  );
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                },
                child: const Text('Save'),
              ),
            ),
            const SizedBox(height: 22),
            _SheetRow(
              label: 'Fingerprint',
              value: formatFingerprint(state.fingerprint),
            ),
            _SheetRow(label: 'Device ID', value: state.identity.deviceId),
            _SheetRow(label: 'Listening on port', value: '${state.serverPort}'),
            _SheetRow(
              label: 'Received files',
              value: state.downloadDirectory.path,
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: NearlinkColors.muted),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.index,
    required this.onSelect,
    required this.onAccount,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Container(
      width: 238,
      color: NearlinkColors.sidebar,
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                _BrandMark(),
                SizedBox(width: 10),
                Text(
                  'nearlink',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          for (var i = 0; i < _navItems.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _NavButton(
                item: _navItems[i],
                active: i == index,
                onTap: () => onSelect(i),
              ),
            ),
          const Spacer(),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onAccount,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.only(top: 18),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0x24FFFFFF))),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 31,
                      height: 31,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF4CC7C),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initialsOf(state.deviceName),
                        style: const TextStyle(
                          color: Color(0xFF573B15),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.deviceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            state.accountLabel,
                            style: const TextStyle(
                              color: Color(0xFFA9BDB3),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 27,
      height: 27,
      decoration: BoxDecoration(
        color: NearlinkColors.lime,
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Icon(Icons.near_me, size: 15, color: NearlinkColors.sidebar),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? NearlinkColors.lime : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 18,
                color:
                    active ? const Color(0xFF163A2F) : NearlinkColors.sidebarInk,
              ),
              const SizedBox(width: 12),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color:
                      active ? const Color(0xFF163A2F) : NearlinkColors.sidebarInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
