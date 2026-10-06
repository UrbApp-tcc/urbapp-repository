import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'urb_icon.dart';

enum UrbTab { home, search, transparency, profile }

/// Navegação principal aprovada: Início · Buscar · Relatar · Transparência · Perfil.
class UrbBottomNav extends StatelessWidget {
  const UrbBottomNav({
    super.key,
    required this.current,
    required this.onSelect,
    required this.onCreate,
    this.createLabel = 'Relatar',
    this.createIcon,
  });

  final UrbTab current;
  final ValueChanged<UrbTab> onSelect;
  final VoidCallback onCreate;
  final String createLabel;
  final UrbIcons? createIcon;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: 74 + bottom,
      padding: EdgeInsets.fromLTRB(14, 8, 14, bottom),
      decoration: const BoxDecoration(
        color: Color(0xF0FFFFFF),
        border: Border(top: BorderSide(color: UrbColors.divider)),
        boxShadow: [BoxShadow(color: Color(0x0A11233D), blurRadius: 24, offset: Offset(0, -7))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _item(UrbTab.home, UrbIcons.home, 'Início'),
          _item(UrbTab.search, UrbIcons.search, 'Buscar'),
          Expanded(child: _CreateButton(onTap: onCreate, label: createLabel, icon: createIcon)),
          _item(UrbTab.transparency, UrbIcons.transparency, 'Transparência'),
          _item(UrbTab.profile, UrbIcons.profile, 'Perfil'),
        ],
      ),
    );
  }

  Widget _item(UrbTab tab, UrbIcons icon, String label) {
    final active = tab == current;
    final color = active ? UrbColors.blue : const Color(0xFF8B96A4);
    return Expanded(
      child: Semantics(
        selected: active,
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: () => onSelect(tab),
          radius: 32,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              UrbIcon(icon, size: 21, color: color),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: UrbText.caption.copyWith(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
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

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.onTap, required this.label, this.icon});

  final VoidCallback onTap;
  final String label;
  final UrbIcons? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: OverflowBox(
          maxHeight: 110,
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: UrbColors.blue,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(color: Color(0x524657EF), blurRadius: 21, offset: Offset(0, 8)),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: icon != null
                      ? UrbIcon(icon!, size: 20, color: UrbColors.lime)
                      : const UrbIcon(UrbIcons.plus, size: 24, color: UrbColors.lime, strokeWidth: 2),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: UrbText.caption.copyWith(
                    color: UrbColors.navy,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
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
