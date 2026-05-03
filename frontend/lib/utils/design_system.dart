import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color primaryBlue = Color(0xFF3B82F6);
  static const Color accentPurple = Color(0xFFA855F7);
  static const Color neonCyan = Color(0xFF00F2FF);
  static const Color neonPink = Color(0xFFFF00D4);
  static const Color background = Color(0xFF060910);
  static const Color cardBackground = Color(0xFF0F172A);
  static const Color glassBase = Color(0x0DFFFFFF);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF43F5E);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color divider = Color(0xFF1E293B);
  
  static const Gradient primaryGradient = LinearGradient(
    colors: [primaryBlue, accentPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient neonGradient = LinearGradient(
    colors: [neonCyan, primaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppDecorations {
  static BoxDecoration glass = BoxDecoration(
    color: AppColors.glassBase,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
  );

  static List<BoxShadow> primaryGlow = [
    BoxShadow(
      color: AppColors.primaryBlue.withValues(alpha: 0.3),
      blurRadius: 20,
      spreadRadius: 2,
    ),
  ];
}

class AppDesign {
  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: AppColors.primaryBlue,
    scaffoldBackgroundColor: AppColors.background,
    cardTheme: CardThemeData(
      color: AppColors.cardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
    ),
    textTheme: GoogleFonts.outfitTextTheme(
      ThemeData.dark().textTheme.copyWith(
        displayLarge: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -1),
        displayMedium: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -0.5),
        titleLarge: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        bodyLarge: const TextStyle(fontSize: 18, color: AppColors.textPrimary, height: 1.6),
        bodyMedium: const TextStyle(fontSize: 16, color: AppColors.textSecondary, height: 1.5),
      ),
    ),
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primaryBlue,
      secondary: AppColors.accentPurple,
      surface: AppColors.cardBackground,
      error: AppColors.warning,
      onPrimary: Colors.white,
    ),
  );
}
