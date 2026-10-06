import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import 'urb/urb_components.dart';

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
      builder: (dialogContext) => Dialog(
        backgroundColor: UrbColors.canvas,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: UrbColors.lime,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(color: UrbColors.lime.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 10))],
                ),
                child: Text(newLevel?.toString() ?? '↑', style: UrbText.h1.copyWith(fontSize: 34)),
              ),
              const SizedBox(height: 20),
              const UrbEyebrow('Novo nível'),
              const SizedBox(height: 6),
              Text('Você subiu de nível!', textAlign: TextAlign.center, style: UrbText.h2.copyWith(color: UrbColors.navy)),
              if (levelTitle != null && levelTitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(levelTitle, style: UrbText.title.copyWith(color: UrbColors.blue)),
              ],
              const SizedBox(height: 8),
              Text(body, textAlign: TextAlign.center, style: UrbText.bodySmall),
              const SizedBox(height: 20),
              UrbButton(label: 'Continuar', expand: true, onPressed: () => Navigator.of(dialogContext).pop()),
            ],
          ),
        ),
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
