import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Logo do UrbApp: pin de localização com sugestão de cidade + texto "UrbApp" em branco.
/// Pensado para uso sobre fundo com gradiente violeta→azul.
class UrbappLogo extends StatelessWidget {
  const UrbappLogo({
    super.key,
    this.size = 56,
    this.showLabel = true,
    this.labelStyle,
  });

  final double size;
  final bool showLabel;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.gradientViolet, AppColors.gradientBlue],
            ),
            borderRadius: BorderRadius.circular(size * 0.22),
            boxShadow: [
              BoxShadow(
                color: AppColors.gradientViolet.withValues(alpha: 0.35),
                blurRadius: size * 0.2,
                offset: Offset(0, size * 0.07),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.location_on_rounded,
                color: Colors.white,
                size: size * 0.52,
              ),
              Positioned(
                bottom: size * 0.32,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildBuilding(size, 4),
                    SizedBox(width: size * 0.04),
                    _buildBuilding(size, 6),
                    SizedBox(width: size * 0.04),
                    _buildBuilding(size, 5),
                    SizedBox(width: size * 0.04),
                    _buildBuilding(size, 7),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showLabel) ...[
          SizedBox(height: size * 0.2),
          Text(
            'UrbApp',
            textAlign: TextAlign.center,
            style: labelStyle ??
                const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
          ),
        ],
      ],
    );
  }

  Widget _buildBuilding(double size, double heightFactor) {
    final w = size * 0.06;
    final h = size * 0.08 * heightFactor;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
