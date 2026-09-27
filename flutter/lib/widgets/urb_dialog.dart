import 'package:flutter/material.dart';

import '../theme/urbapp_design.dart';

/// Abre uma janela flutuante no meio da tela, com o fundo escurecido.
/// A janela "cresce" de leve ao aparecer.
Future<T?> showUrbDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final duration = UrbMotion.of(context, const Duration(milliseconds: 260));

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Fechar',
    barrierColor: const Color(0x940D1520),
    transitionDuration: duration,
    pageBuilder: (context, _, _) => SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              elevation: 0,
              child: builder(context),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Cabeçalho centralizado das janelas: ícone, título, subtítulo e o "x".
class UrbDialogHeader extends StatelessWidget {
  const UrbDialogHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: UrbColors.lavender,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Icon(icon, color: UrbColors.violetDeep, size: 24),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: UrbText.display(size: 22, weight: FontWeight.w700),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: UrbText.body(size: 14, height: 1.4),
                ),
              ],
            ],
          ),
        ),
        if (onClose != null)
          Positioned(
            right: 0,
            top: 0,
            child: Material(
              color: UrbColors.surface,
              borderRadius: BorderRadius.circular(13),
              child: InkWell(
                onTap: onClose,
                borderRadius: BorderRadius.circular(13),
                child: const SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Color(0xFF374151),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Botão secundário (contorno), usado ao lado do botão principal.
class UrbSecondaryButton extends StatelessWidget {
  const UrbSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: UrbColors.ink,
          side: const BorderSide(color: UrbColors.border, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          label,
          style: UrbText.body(
            size: 16,
            weight: FontWeight.w700,
            color: UrbColors.ink,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// Aviso flutuante no rodapé (sucesso ou erro).
void showUrbSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF18222E),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              color: error ? const Color(0xFFF87171) : const Color(0xFF34D399),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: UrbText.body(
                  size: 14,
                  color: Colors.white,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}
