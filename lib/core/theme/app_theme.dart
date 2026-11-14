import 'package:flutter/material.dart';

class NasaColors {
  // Ana Renkler (Marka ve Temel Arayüz)
  static const Color deepSpaceBlue = Color(0xFF0B3D91);
  static const Color biometricCyan = Color(0xFF00E5FF);

  // Aksan ve Uyarı Renkleri (CTA ve Aksiyonlar)
  static const Color orbitRed = Color(0xFFFC3D21);
  static const Color capsuleGreen = Color(0xFF00D289);
  static const Color warningAmber = Color(0xFFFFB300);

  // Arka Plan ve Yüzey Renkleri (Derinlik ve Okunabilirlik)
  static const Color darkMatter = Color(0xFF0A1118);
  static const Color stationGrey = Color(0xFF1E2A38);
  static const Color starlightWhite = Color(0xFFF4F7FA);

  // Tipografi (Metin Hiyerarşisi)
  static const Color pureWhite = Color(0xFFFFFFFF);
  static const Color nebulaGrey = Color(0xFF8B9EB7);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: NasaColors.darkMatter,
      primaryColor: NasaColors.deepSpaceBlue,
      colorScheme: const ColorScheme.dark(
        primary: NasaColors.deepSpaceBlue,
        secondary: NasaColors.biometricCyan,
        error: NasaColors.orbitRed,
        surface: NasaColors.stationGrey,
        onPrimary: NasaColors.pureWhite,
        onSecondary: NasaColors.darkMatter,
        onSurface: NasaColors.starlightWhite,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: NasaColors.darkMatter,
        foregroundColor: NasaColors.pureWhite,
        elevation: 0,
        centerTitle: false,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: NasaColors.darkMatter,
      ),
      cardTheme: CardThemeData(
        color: NasaColors.stationGrey,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: NasaColors.biometricCyan.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: NasaColors.pureWhite,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
        titleLarge: TextStyle(
          color: NasaColors.pureWhite,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: NasaColors.starlightWhite),
        bodyMedium: TextStyle(color: NasaColors.nebulaGrey),
      ),
    );
  }
}