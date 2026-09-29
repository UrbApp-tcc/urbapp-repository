import 'package:flutter/material.dart';

import '../theme/urbapp_design.dart';

/// Etiqueta colorida do status do reporte (Aberto, Em análise...).
class UrbStatusChip extends StatelessWidget {
  const UrbStatusChip({super.key, required this.status});

  final String status;

  static ({String label, Color background, Color foreground}) styleOf(
    String status,
  ) {
    switch (status) {
      case 'open':
        return (
          label: 'Aberto',
          background: const Color(0xFFFEF3C7),
          foreground: const Color(0xFF92400E),
        );
      case 'in_analysis':
        return (
          label: 'Em análise',
          background: UrbColors.lavender,
          foreground: UrbColors.violetDeep,
        );
      case 'in_progress':
        return (
          label: 'Em andamento',
          background: const Color(0xFFDBEAFE),
          foreground: const Color(0xFF1E40AF),
        );
      case 'completed':
        return (
          label: 'Concluído',
          background: const Color(0xFFD1FAE5),
          foreground: const Color(0xFF065F46),
        );
      case 'closed':
        return (
          label: 'Encerrado',
          background: const Color(0xFFE5E7EB),
          foreground: const Color(0xFF374151),
        );
      case 'awaiting_validation':
        return (
          label: 'Aguardando validação',
          background: const Color(0xFFD1FAE5),
          foreground: const Color(0xFF065F46),
        );
      case 'expired':
        return (
          label: 'Expirado',
          background: const Color(0xFFE5E7EB),
          foreground: const Color(0xFF374151),
        );
      default:
        return (
          label: status,
          background: const Color(0xFFE5E7EB),
          foreground: const Color(0xFF374151),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = styleOf(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        style.label,
        maxLines: 1,
        style: UrbText.body(
          size: 12,
          weight: FontWeight.w700,
          color: style.foreground,
          height: 1.3,
        ),
      ),
    );
  }
}
