import 'package:flutter/material.dart';

import '../theme/urbapp_design.dart';

/// Foto do reporte com cantos arredondados. Aparece suavemente quando
/// termina de carregar e mostra um fundo escuro se não houver foto.
class UrbPostImage extends StatelessWidget {
  const UrbPostImage({
    super.key,
    required this.url,
    required this.height,
    this.width,
    this.radius = 16,
  });

  final String? url;
  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;
    final fallback = DecoratedBox(
      decoration: const BoxDecoration(gradient: UrbGradients.photo),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: const Color(0xFF9FB0C6),
          size: height > 100 ? 32 : 20,
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        width: width ?? double.infinity,
        child: imageUrl == null || imageUrl.isEmpty
            ? fallback
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                frameBuilder: (context, child, frame, loadedSync) {
                  if (loadedSync) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: UrbMotion.of(context, UrbMotion.medium),
                    child: child,
                  );
                },
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

/// Ilustração + título + texto para listas vazias.
class UrbEmptyState extends StatelessWidget {
  const UrbEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 150,
          height: 150,
          decoration: const BoxDecoration(
            color: UrbColors.lavender,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 64, color: UrbColors.violetDeep),
        ),
        const SizedBox(height: 22),
        Text(
          title,
          textAlign: TextAlign.center,
          style: UrbText.display(size: 22, weight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(text, textAlign: TextAlign.center, style: UrbText.body(size: 15)),
      ],
    );
  }
}

/// Bloco cinza usado enquanto a tela carrega.
class UrbSkeleton extends StatelessWidget {
  const UrbSkeleton({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          colors: [Color(0xFFE6E8EE), Color(0xFFF3F4F8), Color(0xFFE6E8EE)],
        ),
      ),
    );
  }
}

/// Número em pílula lilás (ex.: quantidade de resultados).
class UrbCountBadge extends StatelessWidget {
  const UrbCountBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: UrbMotion.of(context, UrbMotion.fast),
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: Container(
        key: ValueKey(label),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: UrbColors.lavender,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: UrbText.body(
            size: 13,
            weight: FontWeight.w700,
            color: UrbColors.violetDeep,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
