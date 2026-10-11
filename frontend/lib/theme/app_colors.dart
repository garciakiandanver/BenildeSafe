import 'package:flutter/material.dart';

/// Central palette for BenildeSafe.
///
/// Every value here is lifted verbatim from the previous inline
/// `_buildTheme()` in main.dart so nothing shifts visually — the only
/// change is that these colors now have names.
class AppColors {
  AppColors._();

  // ── Brand ────────────────────────────────────────────────────────
  static const forestGreen = Color(0xFF005A23);
  static const deepForest = Color(0xFF003D19);
  static const warmGold = Color(0xFFD5A900);

  // ── Status ───────────────────────────────────────────────────────
  static const successGreen = Color(0xFF248A5A);
  static const accentGreen = Color(0xFF31824B);
  static const paleGreen = Color(0xFFE5F1E7);

  // ── Text ─────────────────────────────────────────────────────────
  static const darkTextOnLight = Color(0xFF193322);
  static const mutedText = Color(0xFF627487);

  // ── Surfaces / borders ───────────────────────────────────────────
  static const borderLight = Color(0xFFE3E9E0);
  static const scaffoldLight = Color(0xFFF5F7F2);

  // ── Dark mode ────────────────────────────────────────────────────
  static const darkScaffold = Color(0xFF111713);
  static const darkSurface = Color(0xFF171D18);
  static const darkCard = Color(0xFF1B231D);
  static const darkBorder = Color(0xFF303B32);
  static const darkOutline = Color(0xFF657168);

  /// Maps an attendance/registration/account status string to a
  /// display color. Replaces the four duplicated `_getStatusColor`
  /// methods that used to live in the admin/child screens.
  static Color status(String? value) {
    switch (value?.toLowerCase()) {
      case 'present':
      case 'approved':
      case 'active':
        return successGreen;
      case 'late':
      case 'pending':
        return Colors.orange;
      case 'absent':
      case 'timeout':
      case 'rejected':
      case 'inactive':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}