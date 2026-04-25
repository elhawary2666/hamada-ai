// lib/core/theme/app_colors.dart
import 'package:flutter/material.dart';

abstract class AppColors {
  // Primary
  static const primary        = Color(0xFF4F8EF7);
  static const primaryLight   = Color(0xFF82B1FF);
  static const primaryDark    = Color(0xFF1A4DB5);

  // Backgrounds
  static const background     = Color(0xFF0D1117);
  static const surface        = Color(0xFF161B22);
  static const surfaceVariant = Color(0xFF21262D);
  static const inputBg        = Color(0xFF1C2128);
  static const inputBorder    = Color(0xFF30363D);

  // Chat bubbles
  static const userBubble          = Color(0xFF1F4E8C);
  static const userBubbleText      = Color(0xFFE8F0FE);
  static const assistantBubble     = Color(0xFF1C2128);
  static const assistantBubbleText = Color(0xFFCDD9E5);

  // Privacy
  static const privacyBg   = Color(0xFF0D2B0D);
  static const privacyText = Color(0xFF3FB950);

  // Text
  static const textPrimary   = Color(0xFFCDD9E5);
  static const textSecondary = Color(0xFF768390);
  static const textHint      = Color(0xFF484F58);

  // Semantic
  static const success = Color(0xFF3FB950);
  static const warning = Color(0xFFD29922);
  static const error   = Color(0xFFF85149);

  // Finance
  static const income  = Color(0xFF3FB950);
  static const expense = Color(0xFFF85149);

  // Chart palette
  static const chartColors = [
    Color(0xFF4F8EF7), Color(0xFF3FB950), Color(0xFFD29922),
    Color(0xFFDB6D28), Color(0xFF8B949E), Color(0xFFBC8CFF),
    Color(0xFFF85149), Color(0xFF39D353),
  ];
}
