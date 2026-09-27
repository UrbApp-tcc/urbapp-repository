import 'package:supabase_flutter/supabase_flutter.dart';

class ModerationService {
  ModerationService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<void> reportPost({
    required int postId,
    required String reason,
    String? details,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Entre na sua conta para denunciar um reporte.');
    }

    final normalizedReason = reason.trim();
    final normalizedDetails = details?.trim() ?? '';
    final description = normalizedDetails.isEmpty
        ? normalizedReason
        : '$normalizedReason: $normalizedDetails';

    try {
      await _supabase.from('moderation_reports').insert({
        'reporter_user_id': userId,
        'target_type': 'post',
        'target_id': postId,
        'reason': description,
      });
    } on PostgrestException catch (error) {
      if (error.code == '23505') {
        throw Exception('Você já denunciou este reporte.');
      }
      throw Exception('Não foi possível enviar a denúncia: ${error.message}');
    } catch (_) {
      throw Exception('Não foi possível enviar a denúncia agora.');
    }
  }
}
