String formatRelativeTime(DateTime value) {
  final difference = DateTime.now().difference(value.toLocal());
  if (difference.inMinutes < 1) return 'Agora';
  if (difference.inHours < 1) return 'Há ${difference.inMinutes} min';
  if (difference.inDays < 1) return 'Há ${difference.inHours} h';
  return 'Há ${difference.inDays} d';
}
