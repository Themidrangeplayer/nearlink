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
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE9F4DF), Color(0xFFDCEFE3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFC4E0CD), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0619231D),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
          BoxShadow(
            color: Color(0x0A19231D),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -60,
            top: -90,
            child: IgnorePointer(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.45),
                    width: 28,
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
                  height: 1.14,
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
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_link, size: 17),
                label: Text(actionLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
