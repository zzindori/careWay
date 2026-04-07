import 'package:flutter/material.dart';

class AppTheme {
  // 브랜드 컬러 (따뜻하고 신뢰감 있는 톤)
  static const Color primary = Color(0xFF2E7D9B);      // 메인 블루
  static const Color primaryLight = Color(0xFF4FA8C8);
  static const Color secondary = Color(0xFF5AAF7A);    // 보조 그린 (복지/건강)
  static const Color surface = Color(0xFFF8FAFB);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1A2332);
  static const Color textSecondary = Color(0xFF6B7E8F);
  static const Color divider = Color(0xFFE8EDF2);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);

  // 카테고리 색상
  static const Map<String, Color> categoryColors = {
    'medical': Color(0xFFEF4444),     // 의료
    'care': Color(0xFF8B5CF6),        // 돌봄
    'living': Color(0xFF10B981),      // 생활지원
    'housing': Color(0xFFF59E0B),     // 주거
    'finance': Color(0xFF2E7D9B),     // 경제
    'mobility': Color(0xFFEC4899),    // 이동
  };

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: surface,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: textPrimary,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: const CardThemeData(
          color: cardBg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF1F5F9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
}
