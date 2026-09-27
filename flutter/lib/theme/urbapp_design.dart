import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tokens do novo visual do UrbApp (redesign "Vibrante").
///
/// Todas as telas novas devem usar estes valores, para o app ficar igual
/// ao quadro de design. O [AppColors] antigo continua valendo para as telas
/// que ainda não foram redesenhadas.
class UrbColors {
  UrbColors._();

  /// Fundo roxo escuro do topo das telas.
  static const Color hero = Color(0xFF3B2A86);

  /// Texto secundário sobre o [hero].
  static const Color heroText = Color(0xFFE4E0F7);

  static const Color violet = Color(0xFF5B3FB8);
  static const Color violetDeep = Color(0xFF4B33A8);
  static const Color blue = Color(0xFF1A6FB0);

  static const Color ink = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF4B5563);
  static const Color textMuted = Color(0xFF6B7280);

  static const Color surface = Color(0xFFF4F5FA);
  static const Color border = Color(0xFFE3E6EE);
  static const Color lavender = Color(0xFFEFEBFB);
  static const Color dotInactive = Color(0xFFD9D3F0);

  static const Color heart = Color(0xFFE0467C);
  static const Color commentBlue = Color(0xFF3C57C4);
}

class UrbGradients {
  UrbGradients._();

  /// Ação principal da tela (botões "Continuar", "Publicar", o "+").
  static const LinearGradient primary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [UrbColors.violet, UrbColors.blue],
  );

  /// Gamificação (nível, XP, insígnias).
  static const LinearGradient gamification = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9A80D9), Color(0xFF40B4F5)],
  );

  /// Fundo escuro usado no lugar de fotos que ainda não carregaram.
  static const LinearGradient photo = LinearGradient(
    begin: Alignment(-0.3, -1),
    end: Alignment(0.3, 1),
    colors: [Color(0xFF26324A), Color(0xFF0D1520)],
  );
}

class UrbText {
  UrbText._();

  /// Títulos (fonte Outfit).
  static TextStyle display({
    double size = 28,
    FontWeight weight = FontWeight.w800,
    Color color = UrbColors.ink,
  }) {
    return GoogleFonts.outfit(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: -0.4,
      height: 1.15,
    );
  }

  /// Textos corridos e botões (fonte DM Sans).
  static TextStyle body({
    double size = 16,
    FontWeight weight = FontWeight.w400,
    Color color = UrbColors.textSecondary,
    double height = 1.5,
  }) {
    return GoogleFonts.dmSans(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
  }
}

class UrbMotion {
  UrbMotion._();

  static const Duration fast = Duration(milliseconds: 220);
  static const Duration medium = Duration(milliseconds: 380);

  /// Respeita a opção "reduzir movimento" do aparelho.
  static Duration of(BuildContext context, Duration duration) {
    return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
  }
}
