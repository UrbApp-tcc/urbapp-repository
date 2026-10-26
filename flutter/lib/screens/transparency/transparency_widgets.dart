import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';

/// Seção editorial com borda inferior (padrão das telas de Transparência).
class TransSection extends StatelessWidget {
  const TransSection({super.key, required this.child, this.white = false, this.last = false});

  final Widget child;
  final bool white;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
      decoration: BoxDecoration(
        color: white ? Colors.white : null,
        border: last ? null : const Border(bottom: BorderSide(color: UrbColors.line)),
      ),
      child: child,
    );
  }
}

class TransEyebrow extends StatelessWidget {
  const TransEyebrow(this.text, {super.key, this.trailing, this.subtitle});

  final String text;
  final Widget? trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text.toUpperCase(), style: UrbText.eyebrow.copyWith(color: UrbColors.muted, letterSpacing: 1.4)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: UrbText.caption.copyWith(fontWeight: FontWeight.w500)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Avatar de pessoa com gradiente (vereadores).
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, required this.seed, this.size = 54, this.highlighted = false});

  final String name;
  final int seed;
  final double size;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: highlighted
          ? BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                const BoxShadow(color: Colors.white, spreadRadius: 2.5),
                BoxShadow(color: UrbColors.blue, spreadRadius: 4.5),
              ],
            )
          : null,
      child: UrbAvatar(name: name, size: size, rounded: false, gradientSeed: seed),
    );
  }
}

class PublicProfileScaffold extends StatelessWidget {
  const PublicProfileScaffold({super.key, required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 14, 20, 14),
            child: Row(
              children: [
                UrbSquareButton(
                  icon: UrbIcons.chevronLeft,
                  tooltip: 'Voltar',
                  size: 36,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const Spacer(),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

