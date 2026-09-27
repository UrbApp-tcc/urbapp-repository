import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/urbapp_design.dart';

/// Barra de navegação flutuante de "vidro fosco", com o "+" em destaque.
class UrbBottomBar extends StatelessWidget {
  const UrbBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.onCreate,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                  child: Row(
                    children: [
                      _item(
                        context,
                        0,
                        Icons.home_outlined,
                        Icons.home_rounded,
                        'Início',
                      ),
                      _item(
                        context,
                        1,
                        Icons.search_rounded,
                        Icons.search_rounded,
                        'Buscar',
                      ),
                      const Expanded(child: SizedBox()),
                      _item(
                        context,
                        2,
                        Icons.notifications_none_rounded,
                        Icons.notifications_rounded,
                        'Notificações',
                      ),
                      _item(
                        context,
                        3,
                        Icons.person_outline_rounded,
                        Icons.person_rounded,
                        'Perfil',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(bottom: 34, child: _CreateButton(onPressed: onCreate)),
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context,
    int index,
    IconData icon,
    IconData activeIcon,
    String label,
  ) {
    final selected = index == selectedIndex;
    return Expanded(
      child: Center(
        child: Tooltip(
          message: label,
          child: Semantics(
            selected: selected,
            button: true,
            label: label,
            child: InkWell(
              onTap: () => onSelect(index),
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: UrbMotion.of(context, UrbMotion.fast),
                curve: Curves.easeOutCubic,
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected ? UrbColors.lavender : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: AnimatedScale(
                  duration: UrbMotion.of(context, UrbMotion.fast),
                  scale: selected ? 1.08 : 1,
                  child: Icon(
                    selected ? activeIcon : icon,
                    size: 25,
                    color: selected
                        ? UrbColors.violetDeep
                        : UrbColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateButton extends StatefulWidget {
  const _CreateButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_CreateButton> createState() => _CreateButtonState();
}

class _CreateButtonState extends State<_CreateButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Novo reporte',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          duration: UrbMotion.of(context, const Duration(milliseconds: 120)),
          scale: _pressed ? 0.9 : 1,
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              gradient: UrbGradients.primary,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.9),
                width: 4,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x663B3FA0),
                  blurRadius: 22,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
          ),
        ),
      ),
    );
  }
}
