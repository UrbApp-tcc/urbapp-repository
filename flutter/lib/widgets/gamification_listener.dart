import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';

/// Envolve a tela principal e escuta, em tempo real, as notificações
/// do usuário logado na tabela `notifications`.
///
/// Quando chega uma notificação `level_up` (criada pela função SQL
/// `award_xp`), mostra um diálogo de "Você subiu de nível!".
class GamificationListener extends StatefulWidget {
  const GamificationListener({super.key, required this.child});

  final Widget child;

  @override
  State<GamificationListener> createState() => _GamificationListenerState();
}

class _GamificationListenerState extends State<GamificationListener> {
  final SupabaseClient _supabase = Supabase.instance.client;
  RealtimeChannel? _channel;
  bool _isShowingDialog = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) {
      _supabase.removeChannel(channel);
    }
    super.dispose();
  }

  void _subscribe() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    _channel = _supabase
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) => _handleNotification(payload.newRecord),
        )
        .subscribe();
  }

  void _handleNotification(Map<String, dynamic> row) {
    if (!mounted) return;
    if (row['type'] != 'level_up') return;

    final data = (row['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    _showLevelUpDialog(
      notificationId: (row['id'] as num?)?.toInt(),
      newLevel: (data['new_level'] as num?)?.toInt(),
      levelTitle: data['level_title'] as String?,
      body: (row['body'] as String?) ?? '',
    );
  }

  Future<void> _showLevelUpDialog({
    required int? notificationId,
    required int? newLevel,
    required String? levelTitle,
    required String body,
  }) async {
    // Evita empilhar dois diálogos se duas notificações chegarem juntas.
    if (_isShowingDialog) return;
    _isShowingDialog = true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.gradientViolet, AppColors.gradientBlue],
                ),
              ),
              child: Text(
                newLevel?.toString() ?? '↑',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Você subiu de nível!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (levelTitle != null && levelTitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                levelTitle,
                style: const TextStyle(
                  color: AppColors.accentPurple,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    _isShowingDialog = false;

    if (notificationId != null) {
      try {
        await _supabase
            .from('notifications')
            .update({'read_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', notificationId);
      } catch (_) {
        // Não bloqueia o usuário se falhar.
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
