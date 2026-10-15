import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/nearlink_card.dart';

/// The large pale-green call to action at the top of the control centre.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.headline,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final String headline;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return NearlinkCard(
      color: NearlinkColors.heroBg,
      padding: const EdgeInsets.all(26),
      child: Stack(
        children: [
          Positioned(
            right: -70,
            top: -110,
            child: IgnorePointer(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.36),
                    width: 32,
                  ),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('Your secure space'),
              const SizedBox(height: 11),
              Text(
                headline,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.0,
                  height: 1.12,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Text(
                  body,
                  style: const TextStyle(
                    fontSize: 14,
                    color: NearlinkColors.heroInk,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ],
      ),
    );
  }
}
