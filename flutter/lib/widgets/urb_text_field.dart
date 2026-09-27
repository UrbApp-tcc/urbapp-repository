import 'package:flutter/material.dart';

import '../theme/urbapp_design.dart';

/// Campo de texto do novo visual: rótulo em cima, fundo cinza-claro,
/// ícone à esquerda e texto centralizado.
class UrbTextField extends StatelessWidget {
  const UrbTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.icon,
    this.hintText,
    this.helperText,
    this.validator,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
    this.suffix,
    this.autofillHints,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String? hintText;
  final String? helperText;
  final String? Function(String?)? validator;
  final bool obscureText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final void Function(String)? onFieldSubmitted;
  final Widget? suffix;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: UrbText.body(
            size: 13,
            weight: FontWeight.w700,
            color: const Color(0xFF374151),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: controller,
          validator: validator,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          autofillHints: autofillHints,
          textAlign: TextAlign.center,
          style: UrbText.body(size: 15, color: UrbColors.ink, height: 1.3),
          decoration: urbInputDecoration(
            hintText: hintText,
            helperText: helperText,
            icon: icon,
            suffix: suffix,
          ),
        ),
      ],
    );
  }
}

/// Decoração compartilhada pelos campos e listas de escolha do novo visual.
InputDecoration urbInputDecoration({
  String? hintText,
  String? helperText,
  IconData? icon,
  Widget? suffix,
}) {
  OutlineInputBorder border(Color color, [double width = 1.5]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return InputDecoration(
    hintText: hintText,
    hintStyle: UrbText.body(size: 15, color: UrbColors.textMuted, height: 1.3),
    helperText: helperText,
    helperStyle: UrbText.body(
      size: 12,
      color: UrbColors.textMuted,
      height: 1.3,
    ),
    errorStyle: UrbText.body(
      size: 12,
      color: const Color(0xFFDC2626),
      height: 1.3,
    ),
    filled: true,
    fillColor: UrbColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 19),
    prefixIcon: icon == null
        ? null
        : Icon(icon, color: UrbColors.textMuted, size: 20),
    // Espaço igual à direita, para o texto ficar realmente centralizado.
    suffixIcon: suffix ?? (icon == null ? null : const SizedBox(width: 48)),
    border: border(UrbColors.border),
    enabledBorder: border(UrbColors.border),
    focusedBorder: border(UrbColors.violet, 2),
    errorBorder: border(const Color(0xFFFCA5A5)),
    focusedErrorBorder: border(const Color(0xFFDC2626), 2),
  );
}

/// Botão de mostrar/ocultar senha, com troca animada do ícone.
class PasswordVisibilityToggle extends StatelessWidget {
  const PasswordVisibilityToggle({
    super.key,
    required this.visible,
    required this.onPressed,
  });

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: visible ? 'Ocultar senha' : 'Mostrar senha',
      onPressed: onPressed,
      icon: AnimatedSwitcher(
        duration: UrbMotion.of(context, UrbMotion.fast),
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: Icon(
          visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          key: ValueKey(visible),
          color: UrbColors.textMuted,
          size: 20,
        ),
      ),
    );
  }
}
