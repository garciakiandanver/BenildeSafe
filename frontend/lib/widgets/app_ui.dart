import 'dart:convert';

import 'package:flutter/material.dart';

class SectionHeading extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final subtitleText = subtitle;
    final trailingWidget = trailing;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              if (subtitleText case final subtitleText?) ...[
                const SizedBox(height: 4),
                Text(
                  subtitleText,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailingWidget,
      ],
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String label;
  final Color? color;

  const StatusBadge({super.key, required this.label, this.color});

  Color _statusColor(BuildContext context) {
    if (color != null) return color!;
    switch (label.toLowerCase()) {
      case 'present':
      case 'inside campus':
      case 'active':
        return const Color(0xFF248A5A);
      case 'late':
      case 'checking location':
        return const Color(0xFFB7791F);
      case 'absent':
      case 'outside campus':
      case 'location permission required':
        return Theme.of(context).colorScheme.error;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: statusColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: scheme.primary, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            if (action case final action?) ...[
              const SizedBox(height: 16),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

class ProfileAvatar extends StatelessWidget {
  final String name;
  final double radius;

  /// Profile photo as a data URL ("data:image/jpeg;base64,..."). When it is
  /// null or cannot be read, the initials are shown instead.
  final String? photo;

  const ProfileAvatar({
    super.key,
    required this.name,
    this.radius = 25,
    this.photo,
  });

  // Decoding a photo on every rebuild would make it flicker, so keep the last one.
  static String? _cachedPhoto;
  static ImageProvider? _cachedImage;

  static ImageProvider? _imageFrom(String? photo) {
    if (photo == null || photo.isEmpty) return null;
    if (photo == _cachedPhoto) return _cachedImage;
    try {
      final comma = photo.indexOf(',');
      final bytes = base64Decode(
        comma >= 0 ? photo.substring(comma + 1) : photo,
      );
      _cachedPhoto = photo;
      _cachedImage = MemoryImage(bytes);
      return _cachedImage;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final image = _imageFrom(photo);
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      backgroundImage: image,
      child: image != null
          ? null
          : Text(
              initials.isEmpty ? '?' : initials,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}
