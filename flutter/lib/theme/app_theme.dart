import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tokens visuais do UrbApp, derivados do protótipo aprovado no Figma
/// (`src/index.css` do Figma Make). Toda tela deve usar estes valores.
class UrbColors {
  UrbColors._();

  static const Color blue = Color(0xFF4657EF);
  static const Color navy = Color(0xFF11233D);
  static const Color ink = Color(0xFF0A1930);
  static const Color blueSoft = Color(0xFFF2F3FF);
  static const Color blueSoftBorder = Color(0x2E4657EF);
  static const Color lime = Color(0xFFC7FF4D);
  static const Color limeText = Color(0xFF5A7A10);
  static const Color canvas = Color(0xFFF9FAF5);
  static const Color canvasAlt = Color(0xFFF5F7F3);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color muted = Color(0xFF728093);
  static const Color textSecondary = Color(0xFF667489);
  static const Color textBody = Color(0xFF526277);
  static const Color hint = Color(0xFF9AA6B7);
  static const Color line = Color(0xFFDCE2E8);
  static const Color divider = Color(0xFFE3E7E8);
  static const Color inputBorder = Color(0xFFD4DBE3);

  static const Color support = Color(0xFFD72F40);
  static const Color supportSoft = Color(0xFFFFF0F1);
  static const Color badge = Color(0xFFE03E3E);
  static const Color danger = Color(0xFFB83232);
  static const Color dangerSoft = Color(0xFFFDE8E8);

  static const Color success = Color(0xFF1E7D3B);
  static const Color successSoft = Color(0xFFE8F5EC);
  static const Color warning = Color(0xFFB35C00);
  static const Color warningSoft = Color(0xFFFFF2E8);
  static const Color amber = Color(0xFF856A00);
  static const Color amberSoft = Color(0xFFFFFAE8);
  static const Color validationNote = Color(0xFFB58A00);
  static const Color violet = Color(0xFF7B5CF5);
  static const Color orange = Color(0xFFE07B2A);
  static const Color gold = Color(0xFFC49A0A);
  static const Color green = Color(0xFF22A55A);
  static const Color teal = Color(0xFF2D9E6B);
  static const Color slate = Color(0xFF8492A4);
}

/// Escala tipográfica. O protótipo usa tamanhos de 7–10px em várias telas;
/// aqui eles foram normalizados para o mínimo legível em dispositivos reais
/// mantendo a mesma hierarquia (eyebrow < meta < corpo < título).
class UrbText {
  UrbText._();

  static TextStyle get _base => GoogleFonts.manrope(color: UrbColors.navy);

  static TextStyle get display => _base.copyWith(
        fontSize: 44,
        fontWeight: FontWeight.w800,
        letterSpacing: -2.6,
        height: 0.98,
        color: const Color(0xFF08172D),
      );

  static TextStyle get hero => _base.copyWith(
        fontSize: 64,
        fontWeight: FontWeight.w800,
        letterSpacing: -3.8,
        height: 0.9,
      );

  static TextStyle get screenTitle => _base.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        height: 1.08,
      );

  static TextStyle get h1 => _base.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.1,
        height: 1.06,
      );

  static TextStyle get h2 => _base.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.9,
        height: 1.15,
        color: UrbColors.ink,
      );

  static TextStyle get h3 => _base.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        height: 1.2,
      );

  static TextStyle get title => _base.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        height: 1.25,
      );

  static TextStyle get titleSmall => _base.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        height: 1.3,
      );

  static TextStyle get body => _base.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.6,
        color: UrbColors.textSecondary,
      );

  static TextStyle get bodySmall => _base.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.5,
        color: UrbColors.textSecondary,
      );

  static TextStyle get label => _base.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF11213A),
      );

  static TextStyle get meta => _base.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: UrbColors.muted,
      );

  static TextStyle get caption => _base.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: UrbColors.muted,
      );

  static TextStyle get eyebrow => _base.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
        color: UrbColors.blue,
      );

  static TextStyle get button => _base.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      );

  static TextStyle get stat => _base.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.1,
        height: 1.1,
      );
}

class UrbRadius {
  UrbRadius._();

  static const double xs = 7;
  static const double sm = 10;
  static const double md = 13;
  static const double lg = 17;
  static const double sheet = 22;
}

/// Aliases mantidos para compatibilidade com código ainda não migrado.
/// Apontam para a paleta nova; não use em código novo.
class AppColors {
  AppColors._();

  static const Color gradientViolet = UrbColors.blue;
  static const Color gradientBlue = UrbColors.blue;
  static const Color accentPurple = UrbColors.blue;
  static const Color accentPink = UrbColors.violet;
  static const Color accentOrange = UrbColors.orange;
  static const Color primary = UrbColors.blue;
  static const Color primaryLight = UrbColors.blueSoft;
  static const Color primaryDark = UrbColors.navy;
  static const Color background = UrbColors.canvas;
  static const Color surface = UrbColors.surface;
  static const Color textPrimary = UrbColors.navy;
  static const Color textSecondary = UrbColors.textSecondary;
  static const Color textHint = UrbColors.hint;
  static const Color border = UrbColors.line;
  static const Color error = UrbColors.support;
  static const Color pending = UrbColors.warning;
  static const Color inProgress = UrbColors.blue;
  static const Color resolved = UrbColors.success;
  static const Color divider = UrbColors.divider;
}

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(UrbRadius.md),
      borderSide: const BorderSide(color: UrbColors.inputBorder),
    );

    return ThemeData(
      useMaterial3: true,
      // A família Manrope é registrada pelo google_fonts ao usar os estilos UrbText.
      fontFamily: GoogleFonts.manrope().fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: UrbColors.blue,
        primary: UrbColors.blue,
        onPrimary: Colors.white,
        secondary: UrbColors.lime,
        onSecondary: UrbColors.navy,
        surface: UrbColors.surface,
        onSurface: UrbColors.navy,
        error: UrbColors.support,
      ),
      scaffoldBackgroundColor: UrbColors.canvas,
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: const DividerThemeData(
        color: UrbColors.divider,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: UrbColors.canvas,
        foregroundColor: UrbColors.navy,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: UrbColors.blue, width: 1.4),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: UrbColors.support),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: UrbColors.support, width: 1.4),
        ),
        hintStyle: UrbText.bodySmall.copyWith(color: UrbColors.hint),
        labelStyle: UrbText.bodySmall,
        prefixIconColor: UrbColors.muted,
        suffixIconColor: UrbColors.muted,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: UrbColors.blue,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(UrbRadius.md),
          ),
          textStyle: UrbText.button,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: UrbColors.blue,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: UrbText.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: UrbColors.blue,
          textStyle: UrbText.label.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: UrbColors.navy,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: UrbColors.line),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: UrbText.label.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: UrbColors.blue,
        linearTrackColor: UrbColors.line,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: UrbColors.navy,
        contentTextStyle: UrbText.label.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: UrbColors.canvas,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(UrbRadius.sheet)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: UrbColors.canvas,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titleTextStyle: UrbText.h3,
        contentTextStyle: UrbText.bodySmall,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? UrbColors.blue
              : const Color(0xFFD1D9E0),
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return UrbColors.blue;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: UrbColors.line, width: 1.5),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: UrbColors.blueSoft,
        side: const BorderSide(color: UrbColors.line),
        labelStyle: UrbText.caption.copyWith(color: UrbColors.navy),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: UrbColors.navy,
        unselectedLabelColor: UrbColors.muted,
        indicatorColor: UrbColors.blue,
        dividerColor: UrbColors.divider,
        labelStyle: UrbText.label.copyWith(fontWeight: FontWeight.w800),
        unselectedLabelStyle: UrbText.label,
      ),
    );
  }
}
