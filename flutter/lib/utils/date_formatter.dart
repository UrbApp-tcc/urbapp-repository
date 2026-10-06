const _months = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

String _two(int value) => value.toString().padLeft(2, '0');

/// "Agora", "Há 5 min", "Há 3 h", "Ontem", "Há 4 dias", "12/03".
String formatRelativeTime(DateTime value, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final local = value.toLocal();
  final difference = reference.difference(local);
  if (difference.inMinutes < 1) return 'Agora';
  if (difference.inHours < 1) return 'Há ${difference.inMinutes} min';
  if (difference.inDays < 1 && local.day == reference.day) return 'Há ${difference.inHours} h';
  final yesterday = DateTime(reference.year, reference.month, reference.day - 1);
  if (local.year == yesterday.year && local.month == yesterday.month && local.day == yesterday.day) {
    return 'Ontem';
  }
  if (difference.inDays < 7) {
    final days = difference.inDays.clamp(1, 6);
    return days == 1 ? 'Há 1 dia' : 'Há $days dias';
  }
  if (difference.inDays < 14) return 'Há 1 semana';
  if (difference.inDays < 31) return 'Há ${difference.inDays ~/ 7} semanas';
  return '${_two(local.day)}/${_two(local.month)}${local.year == reference.year ? '' : '/${local.year}'}';
}

/// "Hoje, 09:42", "Ontem, 18:20", "03/10, 14:10" (linha do tempo e relatos).
String formatTimelineDate(DateTime value, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final local = value.toLocal();
  final time = '${_two(local.hour)}:${_two(local.minute)}';
  final today = DateTime(reference.year, reference.month, reference.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  if (days == 0) return 'Hoje, $time';
  if (days == 1) return 'Ontem, $time';
  return '${_two(local.day)}/${_two(local.month)}${local.year == reference.year ? '' : '/${local.year}'}, $time';
}

String formatDate(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.day)}/${_two(local.month)}/${local.year}';
}

String formatMonthYear(DateTime value) {
  final local = value.toLocal();
  return '${_months[local.month - 1]} de ${local.year}';
}

/// "Gestão 2025–2028".
String formatPeriod(DateTime start, DateTime? end) {
  final endText = end == null ? 'atual' : '${end.year}';
  return '${start.year}–$endText';
}

/// Grupo de alertas: hoje, ontem, esta semana, anteriores.
String alertGroupOf(DateTime value, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final local = value.toLocal();
  final today = DateTime(reference.year, reference.month, reference.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'Hoje';
  if (days == 1) return 'Ontem';
  if (days < 7) return 'Esta semana';
  return 'Anteriores';
}

String formatRemaining(Duration remaining) {
  if (remaining.inMinutes < 1) return 'menos de um minuto';
  if (remaining.inHours < 1) return '${remaining.inMinutes} minutos';
  if (remaining.inHours < 48) return remaining.inHours == 1 ? '1 hora' : '${remaining.inHours} horas';
  return '${remaining.inDays} dias';
}
