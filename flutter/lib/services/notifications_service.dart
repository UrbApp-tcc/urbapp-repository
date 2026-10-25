import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';
import '../utils/error_formatter.dart';

/// Alertas gerados pelo backend (spec §23). O cliente apenas lê e marca como lido.
class NotificationsService {
  NotificationsService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  /// Contador de não lidos compartilhado pelos sinos dos cabeçalhos.
  static final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  static const _visibleTypes = [
    'occurrence_event',
    'occurrence_support',
    'occurrence_comment',
    'comment_reply',
    'points_awarded',
    'level_up',
    'badge_awarded',
    'institutional_alert',
    'administration_contact',
  ];

  RealtimeChannel? _channel;

  Future<List<AppNotification>> fetch({int limit = 60}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return const [];
    try {
      final rows = await _supabase
          .from('notifications')
          .select('id, type, title, body, payload, read_at, created_at')
          .eq('user_id', userId)
          .inFilter('type', _visibleTypes)
          .order('created_at', ascending: false)
          .limit(limit);
      final items = (rows as List)
          .map(
            (row) =>
                AppNotification.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
      unreadCount.value = items.where((item) => !item.read).length;
      return items;
    } on PostgrestException catch (error) {
      throw Exception(
        friendlyBackendMessage(
          error.message,
          'Não foi possível carregar os alertas.',
        ),
      );
    }
  }

  Future<void> refreshUnreadCount() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      unreadCount.value = 0;
      return;
    }
    try {
      final response = await _supabase
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .inFilter('type', _visibleTypes)
          .isFilter('read_at', null)
          .count(CountOption.exact);
      unreadCount.value = response.count;
    } catch (_) {
      // O contador é auxiliar; falhas não bloqueiam a navegação.
    }
  }

  Future<void> markRead(int id) async {
    try {
      await _supabase
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', id)
          .isFilter('read_at', null);
      if (unreadCount.value > 0) unreadCount.value -= 1;
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _supabase
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', userId)
          .isFilter('read_at', null);
      unreadCount.value = 0;
    } on PostgrestException catch (error) {
      throw Exception(
        friendlyBackendMessage(
          error.message,
          'Não foi possível marcar os alertas como lidos.',
        ),
      );
    }
  }

  /// Mantém o badge atualizado quando novos alertas chegam.
  void listen() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || _channel != null) return;
    _channel = _supabase
        .channel('urbapp-alerts-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            if (_visibleTypes.contains(payload.newRecord['type'])) {
              unreadCount.value += 1;
            }
          },
        )
        .subscribe();
  }

  Future<void> dispose() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) await _supabase.removeChannel(channel);
  }
}
