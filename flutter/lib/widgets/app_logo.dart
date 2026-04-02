import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'urbapp_logo.dart';

/// Logo do UrbApp: usa imagem de asset quando [useAsset] é true, senão o widget UrbappLogo.
/// Centralizado, com [height] 90 e espaçamento consistente (16px abaixo para o título).
/// Para usar arquivo: coloque `logo.png` em `assets/images/` e defina [useAsset] = true.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.height = 115,
    this.assetPath = 'assets/images/logo.png',
    this.useAsset = true,
  });

  final double height;
  final String assetPath;
  /// Se true, usa Image.asset(assetPath, height: height, fit: BoxFit.contain).
  /// Se false ou se o asset falhar, usa UrbappLogo.
  final bool useAsset;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: useAsset
          ? Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: Image.asset(
                assetPath,
                height: height,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _buildFallbackLogo(context),
              ),
            )
          : _buildFallbackLogo(context),
    );
  }

  Widget _buildFallbackLogo(BuildContext context) {
    return UrbappLogo(
      size: height,
      showLabel: true,
      labelStyle: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
    );
  }
}
