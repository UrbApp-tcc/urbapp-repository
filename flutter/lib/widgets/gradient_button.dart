import 'package:flutter/material.dart';

/// Botão principal com gradiente roxo → rosa, bordas bem arredondadas (25).
/// Cores: Color(0xFF7F5AF0) e Color(0xFFFF4D8D).
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.height = 50,
    this.borderRadius = 25,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final double height;
  final double borderRadius;

  static const Color _startColor = Color(0xFF7F5AF0);
  static const Color _endColor = Color(0xFFFF4D8D);

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        onTap: loading ? null : onPressed,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          width: double.infinity,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: loading
                ? null
                : const LinearGradient(
                    colors: [_startColor, _endColor],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
            color: loading ? Colors.grey.shade300 : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF7F5AF0)),
                    ),
                  )
                else ...[
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _startColor.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
