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
    this.icon,
  });

  final String label;
  final String value;
  final String foot;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final IconData effectiveIcon = icon ??
        (label.toLowerCase().contains('connect')
            ? Icons.wifi_tethering
            : Icons.swap_vert);

    return NearlinkCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: NearlinkColors.muted,
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: NearlinkColors.soft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  effectiveIcon,
                  size: 16,
                  color: NearlinkColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.9,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                label.toLowerCase().contains('connect')
                    ? Icons.lock_outline
                    : Icons.history,
                size: 13,
                color: NearlinkColors.accent,
              ),
              const SizedBox(width: 4),
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
        ],
      ),
    );
  }
}
