import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/nearlink_card.dart';

/// A single metric tile in the overview stack.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.foot,
  });

  final String label;
  final String value;
  final String foot;

  @override
  Widget build(BuildContext context) {
    return NearlinkCard(
      padding: const EdgeInsets.fromLTRB(21, 20, 21, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: NearlinkColors.muted),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            foot,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: NearlinkColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}
