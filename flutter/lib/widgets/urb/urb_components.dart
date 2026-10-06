import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'urb_icon.dart';

/// Marca UrbApp: quadrado azul com "U" e ponto lime.
class UrbBrandMark extends StatelessWidget {
  const UrbBrandMark({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    final dot = size * 0.16;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: UrbColors.blue,
        borderRadius: BorderRadius.circular(size * 0.27),
        boxShadow: const [
          BoxShadow(color: Color(0x2E4657EF), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Transform.translate(
              offset: const Offset(0, -1),
              child: Text(
                'U',
                style: UrbText.title.copyWith(
                  color: Colors.white,
                  fontSize: size * 0.57,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          Positioned(
            top: size * 0.18,
            right: size * 0.18,
            child: Container(
              width: dot,
              height: dot,
              decoration: const BoxDecoration(color: UrbColors.lime, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}

class UrbBrand extends StatelessWidget {
  const UrbBrand({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'UrbApp',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          UrbBrandMark(size: compact ? 36 : 44),
          SizedBox(width: compact ? 9 : 12),
          Text(
            'UrbApp',
            style: UrbText.h3.copyWith(
              color: UrbColors.ink,
              fontSize: compact ? 18 : 21,
              letterSpacing: -0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// Geometria abstrata da marca usada no topo do login e da home.
class UrbBrandGeometry extends StatelessWidget {
  const UrbBrandGeometry({super.key, this.large = true});

  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 270.0 : 210.0;
    return IgnorePointer(
      child: Transform.rotate(
        angle: 0.29,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * 0.4),
                  border: Border.all(
                    color: UrbColors.blue.withValues(alpha: large ? 0.05 : 0.04),
                    width: large ? 42 : 34,
                  ),
                ),
              ),
              Positioned(
                top: -32,
                left: size * 0.23,
                child: Container(
                  width: 34,
                  height: size * 0.53,
                  color: UrbColors.blue.withValues(alpha: 0.06),
                ),
              ),
              if (large)
                Positioned(
                  right: -11,
                  bottom: 25,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: UrbColors.lime,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: UrbColors.lime.withValues(alpha: 0.18),
                          spreadRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class UrbEyebrow extends StatelessWidget {
  const UrbEyebrow(this.text, {super.key, this.color, this.muted = false});

  final String text;
  final Color? color;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: UrbText.eyebrow.copyWith(
        color: color ?? (muted ? UrbColors.muted : UrbColors.blue),
      ),
    );
  }
}

/// Botão primário: rótulo à esquerda e círculo lime com seta à direita.
class UrbPrimaryButton extends StatelessWidget {
  const UrbPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = UrbIcons.arrow,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final UrbIcons icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled || loading ? 1 : 0.38,
        child: Material(
          color: UrbColors.blue,
          borderRadius: BorderRadius.circular(UrbRadius.md),
          shadowColor: const Color(0x334657EF),
          elevation: enabled ? 6 : 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(UrbRadius.md),
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              height: 54,
              width: expand ? double.infinity : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 14, 0),
                child: Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: UrbText.button,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!expand) const SizedBox(width: 14),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        color: UrbColors.lime,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: loading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: UrbColors.navy,
                              ),
                            )
                          : UrbIcon(icon, size: 17, color: UrbColors.navy),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum UrbButtonTone { blue, soft, outline, outlineBlue, lime, danger, ghost }

/// Botão de ação compacto usado em sheets, estados vazios e cards.
class UrbButton extends StatelessWidget {
  const UrbButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = UrbButtonTone.blue,
    this.icon,
    this.height = 48,
    this.expand = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final UrbButtonTone tone;
  final UrbIcons? icon;
  final double height;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (tone) {
      UrbButtonTone.blue => (UrbColors.blue, Colors.white, UrbColors.blue),
      UrbButtonTone.soft => (UrbColors.blueSoft, UrbColors.blue, UrbColors.blueSoft),
      UrbButtonTone.outline => (Colors.white, UrbColors.navy, UrbColors.line),
      UrbButtonTone.outlineBlue => (Colors.white, UrbColors.blue, const Color(0xFFD9DFE2)),
      UrbButtonTone.lime => (UrbColors.lime, UrbColors.navy, UrbColors.lime),
      UrbButtonTone.danger => (UrbColors.dangerSoft, UrbColors.danger, UrbColors.dangerSoft),
      UrbButtonTone.ghost => (Colors.transparent, UrbColors.blue, Colors.transparent),
    };
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled || loading ? 1 : 0.45,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onPressed : null,
          child: Container(
            constraints: BoxConstraints(minHeight: height),
            width: expand ? double.infinity : null,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                else if (icon != null)
                  UrbIcon(icon!, size: 18, color: fg),
                if (loading || icon != null) const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: UrbText.label.copyWith(color: fg, fontWeight: FontWeight.w800, height: 1.2),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class UrbTextButton extends StatelessWidget {
  const UrbTextButton(this.label, {super.key, required this.onPressed, this.color});

  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Text(
          label,
          style: UrbText.label.copyWith(
            color: color ?? UrbColors.blue,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Campo de formulário com rótulo acima, como no login do Figma.
class UrbTextField extends StatelessWidget {
  const UrbTextField({
    super.key,
    this.label,
    this.trailingLabel,
    this.controller,
    this.hint,
    this.obscure = false,
    this.suffix,
    this.prefix,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.autofillHints,
    this.enabled = true,
    this.focusNode,
    this.textCapitalization = TextCapitalization.none,
  });

  final String? label;
  final Widget? trailingLabel;
  final TextEditingController? controller;
  final String? hint;
  final bool obscure;
  final Widget? suffix;
  final Widget? prefix;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final FocusNode? focusNode;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Row(
            children: [
              Expanded(child: Text(label!, style: UrbText.label)),
              ?trailingLabel,
            ],
          ),
          const SizedBox(height: 8),
        ],
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscure,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          validator: validator,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          maxLines: obscure ? 1 : maxLines,
          minLines: minLines,
          maxLength: maxLength,
          enabled: enabled,
          autofillHints: autofillHints,
          textCapitalization: textCapitalization,
          style: UrbText.bodySmall.copyWith(
            color: const Color(0xFF14223A),
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: suffix,
            prefixIcon: prefix,
            counterText: maxLength == null ? null : '',
          ),
        ),
      ],
    );
  }
}

/// Botão quadrado com borda fina (voltar, configurações, fechar).
class UrbSquareButton extends StatelessWidget {
  const UrbSquareButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 38,
    this.iconSize = 20,
    this.badge,
  });

  final UrbIcons icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final double iconSize;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: badge != null && badge! > 0 ? '$tooltip, $badge não lidos' : tooltip,
      excludeSemantics: true,
      onTap: onPressed,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: SizedBox(
          width: size + 6,
          height: size + 6,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(size * 0.3),
                  side: const BorderSide(color: UrbColors.line),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(size * 0.3),
                  onTap: onPressed,
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: Center(
                      child: UrbIcon(icon, size: iconSize, color: UrbColors.navy),
                    ),
                  ),
                ),
              ),
              if (badge != null && badge! > 0)
                Positioned(
                  top: -1,
                  right: -1,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: UrbColors.badge,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: UrbColors.canvas, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badge! > 99 ? '99+' : '$badge',
                      style: UrbText.caption.copyWith(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cabeçalho de subtela: botão voltar à esquerda e título centralizado.
class UrbSubscreenHeader extends StatelessWidget implements PreferredSizeWidget {
  const UrbSubscreenHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.closeIcon = false,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final bool closeIcon;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF0F9FAF5),
        border: Border(bottom: BorderSide(color: UrbColors.divider)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: UrbSquareButton(
                    icon: closeIcon ? UrbIcons.close : UrbIcons.chevronLeft,
                    tooltip: closeIcon ? 'Fechar' : 'Voltar',
                    size: 36,
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  ),
                ),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                SizedBox(width: 48, child: trailing),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cabeçalho das abas principais: título grande e ações à direita.
class UrbScreenHeader extends StatelessWidget {
  const UrbScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.bordered = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: bordered
            ? const Border(bottom: BorderSide(color: UrbColors.divider))
            : null,
      ),
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 18, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: UrbText.screenTitle),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: UrbText.caption),
                ],
              ],
            ),
          ),
          for (final action in actions) ...[const SizedBox(width: 8), action],
        ],
      ),
    );
  }
}

/// Cabeçalho de seção editorial: eyebrow + título + ação opcional.
class UrbSectionHeader extends StatelessWidget {
  const UrbSectionHeader({
    super.key,
    this.eyebrow,
    this.title,
    this.subtitle,
    this.trailing,
    this.mutedEyebrow = false,
  });

  final String? eyebrow;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final bool mutedEyebrow;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow != null) UrbEyebrow(eyebrow!, muted: mutedEyebrow),
              if (eyebrow != null && title != null) const SizedBox(height: 4),
              if (title != null) Text(title!, style: UrbText.h3),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!, style: UrbText.caption),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class UrbSeeAll extends StatelessWidget {
  const UrbSeeAll({super.key, required this.onPressed, this.label = 'Ver todas'});

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => UrbTextButton(label, onPressed: onPressed);
}

class UrbBellButton extends StatelessWidget {
  const UrbBellButton({super.key, required this.unreadCount, required this.onPressed});

  final int unreadCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return UrbSquareButton(
      icon: UrbIcons.bell,
      tooltip: 'Alertas',
      badge: unreadCount,
      onPressed: onPressed,
    );
  }
}

/// Sheet inferior padrão do protótipo (alça, eyebrow, título, fechar).
Future<T?> showUrbSheet<T>({
  required BuildContext context,
  required String title,
  String? eyebrow,
  String? intro,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: UrbColors.canvas,
    barrierColor: const Color(0x70071427),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 17),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4DADB),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (eyebrow != null) ...[
                        UrbEyebrow(eyebrow),
                        const SizedBox(height: 4),
                      ],
                      Text(title, style: UrbText.h2.copyWith(color: UrbColors.navy)),
                    ],
                  ),
                ),
                UrbTextButton(
                  'Fechar',
                  color: UrbColors.muted,
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
            if (intro != null) ...[
              const SizedBox(height: 10),
              Text(intro, style: UrbText.bodySmall),
            ],
            const SizedBox(height: 16),
            builder(sheetContext),
          ],
        ),
      ),
    ),
  );
}

class UrbConfirmSheet extends StatelessWidget {
  const UrbConfirmSheet({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = 'Cancelar',
    this.destructive = false,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'Cancelar',
    bool destructive = false,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      useSafeArea: true,
      barrierColor: const Color(0x61000000),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => UrbConfirmSheet(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: UrbText.h3),
          const SizedBox(height: 6),
          Text(message, style: UrbText.bodySmall),
          const SizedBox(height: 18),
          UrbButton(
            label: confirmLabel,
            tone: destructive ? UrbButtonTone.danger : UrbButtonTone.blue,
            height: 50,
            expand: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: 8),
          UrbButton(
            label: cancelLabel,
            tone: UrbButtonTone.outline,
            height: 50,
            expand: true,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}

class UrbSwitch extends StatelessWidget {
  const UrbSwitch({super.key, required this.value, required this.onChanged, this.label});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: label,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 44,
          height: 26,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? UrbColors.blue : const Color(0xFFD1D9E0),
            borderRadius: BorderRadius.circular(13),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1))],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Linha de configuração/preferência com fundo branco e borda superior.
class UrbSettingsRow extends StatelessWidget {
  const UrbSettingsRow({
    super.key,
    required this.label,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.destructive = false,
    this.value,
  });

  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: UrbColors.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: UrbText.bodySmall.copyWith(
                        color: destructive ? UrbColors.danger : UrbColors.navy,
                        fontWeight: subtitle == null ? FontWeight.w500 : FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: UrbText.caption),
                    ],
                  ],
                ),
              ),
              if (value != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(value!, style: UrbText.meta),
                ),
              if (trailing != null)
                Padding(padding: const EdgeInsets.only(left: 12), child: trailing)
              else if (onTap != null)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: UrbIcon(UrbIcons.chevron, size: 16, color: UrbColors.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class UrbGroupLabel extends StatelessWidget {
  const UrbGroupLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 7),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: UrbColors.line)),
      ),
      child: UrbEyebrow(text, muted: true),
    );
  }
}

class UrbLoadingView extends StatelessWidget {
  const UrbLoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const UrbPulsingDots(),
            if (message != null) ...[
              const SizedBox(height: 18),
              Text(message!, style: UrbText.bodySmall, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

/// Três pontos pulsando (estado "Verificando ocorrências próximas…").
class UrbPulsingDots extends StatefulWidget {
  const UrbPulsingDots({super.key});

  @override
  State<UrbPulsingDots> createState() => _UrbPulsingDotsState();
}

class _UrbPulsingDotsState extends State<UrbPulsingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Carregando',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = (_controller.value - index * 0.166) % 1.0;
            final t = phase < 0.4 ? phase / 0.4 : (phase < 0.8 ? (0.8 - phase) / 0.4 : 0.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Transform.scale(
                scale: 0.85 + 0.15 * t,
                child: Opacity(
                  opacity: 0.25 + 0.75 * t,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: UrbColors.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class UrbEmptyState extends StatelessWidget {
  const UrbEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = UrbIcons.search,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.compact = false,
  });

  final String title;
  final String message;
  final UrbIcons icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: compact ? 24 : 44),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: UrbColors.blueSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: UrbIcon(icon, size: 25, color: UrbColors.blue),
          ),
          const SizedBox(height: 15),
          Text(title, style: UrbText.title.copyWith(fontSize: 17), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 290),
            child: Text(message, style: UrbText.bodySmall, textAlign: TextAlign.center),
          ),
          if (actionLabel != null || secondaryLabel != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (secondaryLabel != null)
                  UrbButton(
                    label: secondaryLabel!,
                    tone: UrbButtonTone.outline,
                    height: 40,
                    onPressed: onSecondary,
                  ),
                if (actionLabel != null)
                  UrbButton(
                    label: actionLabel!,
                    tone: UrbButtonTone.soft,
                    height: 40,
                    onPressed: onAction,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class UrbErrorState extends StatelessWidget {
  const UrbErrorState({super.key, required this.message, this.onRetry, this.title});

  final String message;
  final String? title;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return UrbEmptyState(
      icon: UrbIcons.close,
      title: title ?? 'Não foi possível carregar',
      message: message,
      actionLabel: onRetry == null ? null : 'Tentar novamente',
      onAction: onRetry,
    );
  }
}

/// Avatar com iniciais. `rounded` usa cantos de 10px (comentários/relatos).
class UrbAvatar extends StatelessWidget {
  const UrbAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 32,
    this.rounded = true,
    this.gradientSeed,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final bool rounded;
  final int? gradientSeed;

  static const _gradients = [
    [Color(0xFF4657EF), Color(0xFF7B5CF5)],
    [Color(0xFFE07B2A), Color(0xFFF5A642)],
    [Color(0xFF2D9E6B), Color(0xFF52C89A)],
    [Color(0xFFC49A0A), Color(0xFFE8C040)],
    [Color(0xFFE03E3E), Color(0xFFF57B7B)],
  ];

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final radius = rounded ? BorderRadius.circular(size * 0.31) : BorderRadius.circular(size);
    final gradient = gradientSeed == null
        ? null
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _gradients[gradientSeed! % _gradients.length],
          );
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: gradient == null ? UrbColors.blueSoft : null,
        gradient: gradient,
        borderRadius: radius,
      ),
      alignment: Alignment.center,
      child: Text(
        rounded ? initialsOf(name).characters.first : initialsOf(name),
        style: UrbText.label.copyWith(
          color: gradient == null ? UrbColors.blue : Colors.white,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (imageUrl == null || imageUrl!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

/// Selo "Verificado" / "Não reivindicado" dos perfis institucionais.
class UrbVerificationPill extends StatelessWidget {
  const UrbVerificationPill({super.key, required this.label, this.verified = true, this.large = false});

  final String label;
  final bool verified;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 11 : 8, vertical: large ? 6 : 5),
      decoration: BoxDecoration(
        color: verified ? UrbColors.blueSoft : const Color(0xFFEFF1EF),
        borderRadius: BorderRadius.circular(large ? 20 : 7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (verified) ...[
            Container(
              width: 13,
              height: 13,
              decoration: const BoxDecoration(color: UrbColors.blue, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const UrbIcon(UrbIcons.check, size: 9, color: Colors.white, strokeWidth: 3),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: UrbText.caption.copyWith(
              color: verified ? UrbColors.blue : const Color(0xFF6F7D8C),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bloco de números lado a lado, separados por linhas finas.
class UrbStatRow extends StatelessWidget {
  const UrbStatRow({super.key, required this.items, this.big = false});

  final List<UrbStatItem> items;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < items.length; index++)
            Expanded(
              child: Container(
                padding: EdgeInsets.only(
                  left: index == 0 ? 0 : 14,
                  right: index == items.length - 1 ? 0 : 14,
                ),
                decoration: BoxDecoration(
                  border: index == items.length - 1
                      ? null
                      : const Border(right: BorderSide(color: UrbColors.line)),
                ),
                child: Semantics(
                  label: '${items[index].value} ${items[index].label}',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[index].value,
                        style: UrbText.stat.copyWith(fontSize: big ? 24 : 20),
                      ),
                      const SizedBox(height: 4),
                      Text(items[index].label, style: UrbText.caption.copyWith(height: 1.3)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class UrbStatItem {
  const UrbStatItem(this.value, this.label);

  final String value;
  final String label;
}

/// Linha de lista editorial com ponto colorido, título, meta e chevron.
class UrbDotRow extends StatelessWidget {
  const UrbDotRow({
    super.key,
    required this.title,
    this.subtitle,
    this.note,
    this.noteColor,
    this.trailingText,
    this.dotColor = UrbColors.blue,
    this.onTap,
    this.showChevron = true,
    this.last = false,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final String? note;
  final Color? noteColor;
  final String? trailingText;
  final Color dotColor;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool last;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: UrbColors.line)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading ??
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                  ),
                ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: UrbText.titleSmall.copyWith(fontSize: 13.5)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: UrbText.meta.copyWith(fontWeight: FontWeight.w500)),
                  ],
                  if (note != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      note!,
                      style: UrbText.caption.copyWith(
                        color: noteColor ?? UrbColors.muted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailingText != null)
              Padding(
                padding: const EdgeInsets.only(left: 10, top: 2),
                child: Text(trailingText!, style: UrbText.caption.copyWith(fontWeight: FontWeight.w500)),
              ),
            if (showChevron && onTap != null)
              const Padding(
                padding: EdgeInsets.only(left: 6, top: 2),
                child: UrbIcon(UrbIcons.chevron, size: 15, color: UrbColors.muted),
              ),
          ],
        ),
      ),
    );
  }
}

/// Destaque informativo (ex.: "Encontrou o mesmo problema?").
class UrbCallout extends StatelessWidget {
  const UrbCallout({
    super.key,
    required this.title,
    required this.message,
    this.icon = UrbIcons.check,
    this.onTap,
    this.eyebrow,
  });

  final String title;
  final String message;
  final UrbIcons icon;
  final VoidCallback? onTap;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: UrbColors.blue.withValues(alpha: 0.13)),
            gradient: const LinearGradient(
              begin: Alignment(-1, -0.3),
              end: Alignment(1, 0.3),
              colors: [Color(0xFFF1F3FF), Color(0xFFF8FAF4)],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: UrbColors.lime,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: UrbIcon(icon, size: 20, color: UrbColors.navy),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null) ...[
                      Text(
                        eyebrow!.toUpperCase(),
                        style: UrbText.eyebrow.copyWith(fontSize: 10, letterSpacing: 0.9),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(title, style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(message, style: UrbText.caption.copyWith(color: const Color(0xFF778493))),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: const UrbIcon(UrbIcons.chevron, size: 17, color: UrbColors.blue),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

void showUrbToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 2400),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 96),
      ),
    );
}

/// Abas sublinhadas (Recentes / Em Alta, Contribuições / Acompanhando).
class UrbUnderlineTabs extends StatelessWidget {
  const UrbUnderlineTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.padding = EdgeInsets.zero,
    this.background,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final EdgeInsets padding;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        border: const Border(bottom: BorderSide(color: UrbColors.divider)),
      ),
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            if (index > 0) const SizedBox(width: 24),
            Semantics(
              selected: index == selected,
              button: true,
              child: InkWell(
                onTap: () => onChanged(index),
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: index == selected ? UrbColors.blue : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    labels[index],
                    style: UrbText.label.copyWith(
                      fontWeight: FontWeight.w800,
                      color: index == selected ? UrbColors.navy : const Color(0xFF86919E),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pílula pequena com fundo suave (filtros, chips de categoria).
class UrbChip extends StatelessWidget {
  const UrbChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.dotColor,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final UrbIcons? icon;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: onTap != null,
      child: Material(
        color: selected ? UrbColors.blueSoft : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(
            color: selected ? UrbColors.blue.withValues(alpha: 0.22) : UrbColors.line,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dotColor != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                ],
                if (icon != null) ...[
                  UrbIcon(icon!, size: 14, color: selected ? UrbColors.blue : UrbColors.muted),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: UrbText.caption.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? UrbColors.blue : const Color(0xFF758292),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
