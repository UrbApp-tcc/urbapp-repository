import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';
import '../utils/error_formatter.dart';

class AdministrationContactMedia {
  const AdministrationContactMedia({
    required this.fileName,
    required this.mediaType,
    required this.mimeType,
    required this.sizeBytes,
    required this.url,
  });

  final String fileName;
  final String mediaType;
  final String mimeType;
  final int sizeBytes;
  final String url;

  bool get isImage => mediaType == 'image';
}

/// Alertas gerados pelo backend (spec §23). O cliente apenas lê e marca como lido.
class NotificationsService {
  NotificationsService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const _administrationContactMediaBucket =
      'administration-contact-media';

  /// Contador de não lidos compartilhado pelos sinos dos cabeçalhos.
  static final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  /// Tipos exibidos na central de Alertas; um tipo novo do backend precisa
  /// entrar aqui para aparecer.
  static const visibleTypes = [
    'occurrence_event',
    'occurrence_support',
    'occurrence_comment',
    'comment_reply',
    'points_awarded',
    'level_up',
    'badge_awarded',
    'institutional_alert',
    'administration_contact',
    'institutional_review',
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
          .inFilter('type', visibleTypes)
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
          .inFilter('type', visibleTypes)
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

  Future<List<AdministrationContactMedia>> fetchAdministrationContactMedia(
    int requestId,
  ) async {
    try {
      final rows = await _supabase
          .from('administration_contact_request_media')
          .select('storage_path, file_name, media_type, mime_type, size_bytes')
          .eq('request_id', requestId)
          .order('position');
      return await Future.wait([
        for (final raw in rows as List)
          () async {
            final path = raw['storage_path'] as String;
            final url = await _supabase.storage
                .from(_administrationContactMediaBucket)
                .createSignedUrl(path, 3600);
            return AdministrationContactMedia(
              fileName: raw['file_name'] as String? ?? 'Mídia anexada',
              mediaType: raw['media_type'] as String? ?? 'image',
              mimeType: raw['mime_type'] as String? ?? '',
              sizeBytes: (raw['size_bytes'] as num?)?.toInt() ?? 0,
              url: url,
            );
          }(),
      ]);
    } on PostgrestException catch (error) {
      throw Exception(
        friendlyBackendMessage(
          error.message,
          'Não foi possível carregar as mídias anexadas.',
        ),
      );
    } on StorageException catch (error) {
      throw Exception(
        friendlyBackendMessage(
          error.message,
          'Não foi possível abrir as mídias anexadas.',
        ),
      );
    }
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
            if (visibleTypes.contains(payload.newRecord['type'])) {
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
