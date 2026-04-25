// lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  // FIX: uses google_fonts — no local font files needed
  static String get _cairo => GoogleFonts.cairo().fontFamily!;

  static ThemeData get dark => ThemeData(
    useMaterial3:            true,
    brightness:              Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily:              _cairo,
    colorScheme: const ColorScheme.dark(
      primary:   AppColors.primary,
      secondary: AppColors.primaryLight,
      surface:   AppColors.surface,
      error:     AppColors.error,
      onPrimary: Colors.white,
      onSurface: AppColors.textPrimary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor:  AppColors.surface,
      foregroundColor:  AppColors.textPrimary,
      elevation:        0,
      titleTextStyle: GoogleFonts.cairo(
        fontSize:   18,
        fontWeight: FontWeight.bold,
        color:      AppColors.textPrimary,
      ),
    ),
    textTheme: GoogleFonts.cairoTextTheme(
      const TextTheme(
        bodyLarge:   TextStyle(color: AppColors.textPrimary,   fontSize: 15),
        bodyMedium:  TextStyle(color: AppColors.textSecondary, fontSize: 13),
        labelSmall:  TextStyle(color: AppColors.textHint,      fontSize: 11),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled:    true,
      fillColor: AppColors.inputBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      labelStyle: GoogleFonts.cairo(color: AppColors.textSecondary),
      hintStyle:  GoogleFonts.cairo(color: AppColors.textHint),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: GoogleFonts.cairo(fontSize: 14),
      ),
    ),
    cardTheme: CardTheme(
      color:     AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.inputBorder, width: 0.5),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.inputBorder, thickness: 0.5,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor:      AppColors.surface,
      selectedItemColor:    AppColors.primary,
      unselectedItemColor:  AppColors.textSecondary,
      type:                 BottomNavigationBarType.fixed,
      selectedLabelStyle:   GoogleFonts.cairo(fontSize: 11),
      unselectedLabelStyle: GoogleFonts.cairo(fontSize: 11),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceVariant,
      contentTextStyle: GoogleFonts.cairo(color: AppColors.textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
