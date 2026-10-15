import 'package:flutter/material.dart';

import '../../../core/models/device.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/platform_icon.dart';

/// One row in the trusted-device list.
class DeviceTile extends StatelessWidget {
  const DeviceTile({
    super.key,
    required this.name,
    required this.platform,
    required this.meta,
    required this.selected,
    required this.online,
    this.onTap,
    this.onRemove,
  });

  final String name;
  final DevicePlatform platform;
  final String meta;
  final bool selected;
  final bool online;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFF6FBF7) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? const Color(0xFF6DB79C) : NearlinkColors.line,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: platformTint(platform),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(platformIcon(platform),
                    size: 19, color: NearlinkColors.ink),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      style: const TextStyle(
                        fontSize: 12,
                        color: NearlinkColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (online)
                const Row(
                  children: [
                    Icon(Icons.circle, size: 8, color: NearlinkColors.online),
                    SizedBox(width: 6),
                    Text(
                      'Nearby',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: NearlinkColors.online,
                      ),
                    ),
                  ],
                ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  tooltip: 'Remove $name',
                  iconSize: 18,
                  color: NearlinkColors.muted,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
