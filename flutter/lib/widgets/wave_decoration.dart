import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Formas onduladas para cantos das telas (estilo das referências de login/cadastro).
class WaveDecoration extends StatelessWidget {
  const WaveDecoration({
    super.key,
    this.position = WavePosition.topRight,
    this.height = 140,
    this.widthFactor = 1.0,
    this.useGradient = true,
  });

  final WavePosition position;
  final double height;
  final double widthFactor;
  final bool useGradient;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width * widthFactor;
    return Positioned(
      left: position == WavePosition.topLeft || position == WavePosition.bottomLeft ? 0 : null,
      right: position == WavePosition.topRight || position == WavePosition.bottomRight ? 0 : null,
      top: position == WavePosition.topLeft || position == WavePosition.topRight ? 0 : null,
      bottom: position == WavePosition.bottomLeft || position == WavePosition.bottomRight ? 0 : null,
      child: SizedBox(
        width: w,
        height: height,
        child: CustomPaint(
          painter: _WavePainter(
            position: position,
            gradient: useGradient,
          ),
        ),
      ),
    );
  }
}

enum WavePosition {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.position, required this.gradient});

  final WavePosition position;
  final bool gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final w = size.width;
    final h = size.height;

    switch (position) {
      case WavePosition.topRight:
        path.moveTo(w, 0);
        path.lineTo(0, 0);
        path.lineTo(0, h * 0.7);
        path.quadraticBezierTo(w * 0.25, h * 0.5, w * 0.5, h * 0.65);
        path.quadraticBezierTo(w * 0.75, h * 0.85, w, h * 0.55);
        path.close();
        break;
      case WavePosition.topLeft:
        path.moveTo(0, 0);
        path.lineTo(w, 0);
        path.lineTo(w, h * 0.65);
        path.quadraticBezierTo(w * 0.6, h * 0.5, w * 0.3, h * 0.7);
        path.quadraticBezierTo(0, h * 0.9, 0, h * 0.6);
        path.close();
        break;
      case WavePosition.bottomLeft:
        path.moveTo(0, h);
        path.lineTo(0, h * 0.35);
        path.quadraticBezierTo(w * 0.35, h * 0.55, w * 0.6, h * 0.4);
        path.quadraticBezierTo(w, h * 0.2, w, h);
        path.close();
        break;
      case WavePosition.bottomRight:
        path.moveTo(w, h);
        path.lineTo(w, h * 0.4);
        path.quadraticBezierTo(w * 0.6, h * 0.6, w * 0.25, h * 0.45);
        path.quadraticBezierTo(0, h * 0.25, 0, h);
        path.close();
        break;
    }

    if (gradient) {
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.gradientViolet,
            AppColors.gradientBlue,
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h));
      canvas.drawPath(path, paint);
    } else {
      final paint = Paint()
        ..color = AppColors.gradientViolet.withValues(alpha: 0.4)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
