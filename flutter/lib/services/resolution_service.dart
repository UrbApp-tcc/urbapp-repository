import 'package:supabase_flutter/supabase_flutter.dart';

/// Situação do pedido de validação de um reporte.
class ResolutionStatus {
  const ResolutionStatus({
    required this.requestId,
    required this.note,
    required this.createdAt,
    required this.expiresAt,
    required this.confirmations,
    required this.rejections,
    required this.needed,
    required this.radiusMeters,
    this.myVote,
  });

  final int requestId;
  final String note;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int confirmations;
  final int rejections;
  final int needed;
  final int radiusMeters;

  /// true = confirmou, false = disse que não, null = ainda não votou.
  final bool? myVote;

  factory ResolutionStatus.fromMap(Map<String, dynamic> data) {
    return ResolutionStatus(
      requestId: (data['request_id'] as num).toInt(),
      note: (data['note'] as String?) ?? '',
      createdAt: DateTime.parse(data['created_at'] as String),
      expiresAt: DateTime.parse(data['expires_at'] as String),
      confirmations: (data['confirmations'] as num?)?.toInt() ?? 0,
      rejections: (data['rejections'] as num?)?.toInt() ?? 0,
      needed: (data['needed'] as num?)?.toInt() ?? 3,
      radiusMeters: (data['radius_m'] as num?)?.toInt() ?? 500,
      myVote: data['my_vote'] as bool?,
    );
  }
}

/// Resultado de um voto: 'pending', 'approved' ou 'rejected'.
class ResolutionVoteResult {
  const ResolutionVoteResult({
    required this.result,
    required this.confirmations,
    required this.needed,
  });

  final String result;
  final int confirmations;
  final int needed;
}

/// Validação comunitária da resolução dos reportes.
class ResolutionService {
  ResolutionService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  String _message(PostgrestException error) {
    final text = error.message.trim();
    return text.isEmpty ? 'Não foi possível concluir a ação agora.' : text;
  }

  Future<ResolutionStatus?> fetchStatus(int postId) async {
    try {
      final data = await _supabase.rpc(
        'get_post_resolution_status',
        params: {'p_post_id': postId},
      );
      if (data == null) return null;
      return ResolutionStatus.fromMap((data as Map).cast<String, dynamic>());
    } on PostgrestException catch (error) {
      throw Exception(_message(error));
    }
  }

  /// Quais destes reportes estão aguardando a validação da comunidade.
  Future<Set<int>> fetchAwaitingPostIds(List<int> postIds) async {
    if (postIds.isEmpty) return <int>{};
    try {
      final data = await _supabase.rpc(
        'get_awaiting_validation_post_ids',
        params: {'p_post_ids': postIds},
      );
      return (data as List<dynamic>)
          .map((value) => (value as num).toInt())
          .toSet();
    } catch (_) {
      // Sem essa informação os cartões só mostram o status normal.
      return <int>{};
    }
  }

  Future<void> requestResolution({
    required int postId,
    required String note,
  }) async {
    try {
      await _supabase.rpc(
        'request_post_resolution',
        params: {'p_post_id': postId, 'p_note': note.trim()},
      );
    } on PostgrestException catch (error) {
      throw Exception(_message(error));
    }
  }

  Future<ResolutionVoteResult> vote({
    required int postId,
    required bool confirmed,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final data = await _supabase.rpc(
        'vote_post_resolution',
        params: {
          'p_post_id': postId,
          'p_confirmed': confirmed,
          'p_latitude': latitude,
          'p_longitude': longitude,
        },
      );
      final map = (data as Map).cast<String, dynamic>();
      return ResolutionVoteResult(
        result: (map['result'] as String?) ?? 'pending',
        confirmations: (map['confirmations'] as num?)?.toInt() ?? 0,
        needed: (map['needed'] as num?)?.toInt() ?? 3,
      );
    } on PostgrestException catch (error) {
      throw Exception(_message(error));
    }
  }
}
