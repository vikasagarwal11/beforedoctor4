import 'package:flutter/material.dart';

/// Design tokens (Figma-style) encoded as code for consistent UI.
class AppTokens {
  // Spacing
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  // Radius
  static const double rSm = 10;
  static const double rMd = 14;
  static const double rLg = 20;
  static const double rPill = 999;

  // Typography
  static const double title = 22;
  static const double h2 = 18;
  static const double body = 16;
  static const double caption = 12;

  // Elevation
  static const double e1 = 1;
  static const double e2 = 2;
  static const double e3 = 3;

  // Sizes
  static const double fab = 64;
  static const double chipH = 32;

  // Durations
  static const Duration quick = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
}

class AppColors {
  // Brand-neutral, healthcare-friendly palette (adjust later).
  static const Color primary = Color(0xFF2563EB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF3F4F6);
  static const Color outline = Color(0xFFE5E7EB);
  static const Color danger = Color(0xFFDC2626);
  static const Color warning = Color(0xFFF59E0B);
  static const Color success = Color(0xFF16A34A);

  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);

  static const Color darkSurface = Color(0xFF0B1220);
  static const Color darkSurfaceMuted = Color(0xFF111A2E);
  static const Color darkOutline = Color(0xFF243047);
  static const Color darkTextPrimary = Color(0xFFE5E7EB);
  static const Color darkTextSecondary = Color(0xFF9CA3AF);
}
