import 'package:flutter/material.dart';

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

  static const Color _bg = Color(0xFF18222E);
  static const Color _bgLight = Color(0xFF2A3749);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        onTap: loading ? null : onPressed,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          width: double.infinity,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            color: loading ? const Color(0xFFE8EAED) : _bg,
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
                      valueColor: AlwaysStoppedAnimation<Color>(_bg),
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
                      color: _bgLight,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
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
