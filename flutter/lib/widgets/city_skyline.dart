import 'package:flutter/material.dart';

/// Desenho da silhueta da cidade usado ao fundo do topo das telas.
class CitySkyline extends StatelessWidget {
  const CitySkyline({
    super.key,
    this.color = const Color(0x29FFFFFF),
    this.strokeWidth = 1.5,
  });

  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _CitySkylinePainter(color: color, strokeWidth: strokeWidth),
        size: Size.infinite,
      ),
    );
  }
}

class _CitySkylinePainter extends CustomPainter {
  _CitySkylinePainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  // Pontos do desenho original (largura 390, altura 200).
  static const List<Offset> _points = [
    Offset(0, 200),
    Offset(0, 114),
    Offset(30, 114),
    Offset(30, 84),
    Offset(58, 84),
    Offset(58, 124),
    Offset(84, 124),
    Offset(84, 60),
    Offset(104, 50),
    Offset(124, 60),
    Offset(124, 134),
    Offset(150, 134),
    Offset(150, 96),
    Offset(182, 96),
    Offset(182, 140),
    Offset(206, 140),
    Offset(206, 74),
    Offset(232, 74),
    Offset(232, 114),
    Offset(262, 114),
    Offset(262, 42),
    Offset(286, 42),
    Offset(286, 128),
    Offset(312, 128),
    Offset(312, 88),
    Offset(344, 88),
    Offset(344, 134),
    Offset(372, 134),
    Offset(372, 104),
    Offset(390, 104),
    Offset(390, 200),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 390;
    final scaleY = size.height / 200;
    final path = Path();

    for (var i = 0; i < _points.length; i++) {
      final p = Offset(_points[i].dx * scaleX, _points[i].dy * scaleY);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CitySkylinePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
