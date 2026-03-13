import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Forma ondulada com gradiente para o topo da tela de login (laranja/amarelo → roxo/rosa).
class WaveHeader extends StatelessWidget {
  const WaveHeader({
    super.key,
    this.height = 200,
    this.child,
  });

  final double height;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        children: [
          CustomPaint(
            size: Size(MediaQuery.sizeOf(context).width, height),
            painter: _WaveGradientPainter(),
          ),
          if (child != null)
            Positioned.fill(
              child: SafeArea(
                bottom: false,
                child: child!,
              ),
            ),
        ],
      ),
    );
  }
}

class _WaveGradientPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.75)
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.95,
        size.width * 0.5,
        size.height * 0.8,
      )
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.65,
        0,
        size.height * 0.85,
      )
      ..lineTo(0, 0)
      ..close();

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.gradientViolet,
          AppColors.gradientBlue,
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
