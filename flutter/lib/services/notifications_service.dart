import 'package:supabase_flutter/supabase_flutter.dart';

enum AppNotificationType {
  newFollower,
  postSupport,
  commentSupport,
  postComment,
  commentReply,
}

class AppNotificationItem {
  const AppNotificationItem({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.actorDisplayName,
    this.actorAvatarUrl,
    required this.title,
    required this.description,
  });

  final String id;
  final AppNotificationType type;
  final DateTime createdAt;
  final String actorDisplayName;
  final String? actorAvatarUrl;
  final String title;
  final String description;
}

class NotificationsService {
  NotificationsService({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<List<AppNotificationItem>> fetchNotifications({
    required String userId,
  }) async {
    try {
      final initialResults = await Future.wait<dynamic>([
        _supabase
            .from('posts')
            .select('id, title')
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(100),
        _supabase
            .from('comments')
            .select('id, post_id, body')
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(100),
      ]);

      final ownPosts = {
        for (final item in initialResults[0] as List<dynamic>)
          (item['id'] as num).toInt(): (item['title'] as String?) ?? 'seu post',
      };
      final ownPostIds = ownPosts.keys.toList();

      final ownComments = {
        for (final item in initialResults[1] as List<dynamic>)
          (item['id'] as num).toInt(): _CommentReference(
            id: (item['id'] as num).toInt(),
            postId: (item['post_id'] as num).toInt(),
            body: (item['body'] as String?) ?? '',
          ),
      };
      final ownCommentIds = ownComments.keys.toList();

      final activityResults = await Future.wait<dynamic>([
        _fetchFollowerRows(userId),
        _fetchPostSupportRows(userId, ownPostIds),
        _fetchCommentLikeRows(userId, ownCommentIds),
        _fetchCommentsOnOwnPosts(
          userId: userId,
          ownPostIds: ownPostIds,
          ownCommentIds: ownCommentIds.toSet(),
        ),
        _fetchRepliesToOwnComments(
          userId: userId,
          ownCommentIds: ownCommentIds,
        ),
      ]);

      final followerRows = activityResults[0] as List<_ActivityRow>;
      final postSupportRows = activityResults[1] as List<_ActivityRow>;
      final commentLikeRows = activityResults[2] as List<_ActivityRow>;
      final postCommentRows = activityResults[3] as List<_CommentActivityRow>;
      final commentReplyRows = activityResults[4] as List<_CommentActivityRow>;

      final actorIds = <String>{
        ...followerRows.map((row) => row.actorId),
        ...postSupportRows.map((row) => row.actorId),
        ...commentLikeRows.map((row) => row.actorId),
        ...postCommentRows.map((row) => row.actorId),
        ...commentReplyRows.map((row) => row.actorId),
      }.toList();

      final profilesById = await _fetchProfiles(actorIds);

      final items = <AppNotificationItem>[
        ...followerRows.map(
          (row) => AppNotificationItem(
            id: 'follower-${row.actorId}-${row.createdAt.toIso8601String()}',
            type: AppNotificationType.newFollower,
            createdAt: row.createdAt,
            actorDisplayName: _profileLabel(profilesById[row.actorId]),
            actorAvatarUrl: profilesById[row.actorId]?.avatarUrl,
            title: 'Novo seguidor',
            description: '${_profileLabel(profilesById[row.actorId])} começou a seguir você.',
          ),
        ),
        ...postSupportRows.map(
          (row) => AppNotificationItem(
            id: 'post-support-${row.targetId}-${row.actorId}-${row.createdAt.toIso8601String()}',
            type: AppNotificationType.postSupport,
            createdAt: row.createdAt,
            actorDisplayName: _profileLabel(profilesById[row.actorId]),
            actorAvatarUrl: profilesById[row.actorId]?.avatarUrl,
            title: 'Novo apoio em post',
            description:
                '${_profileLabel(profilesById[row.actorId])} apoiou seu post "${ownPosts[row.targetId] ?? 'seu post'}".',
          ),
        ),
        ...commentLikeRows.map(
          (row) {
            final comment = ownComments[row.targetId];
            final preview = _truncate(comment?.body ?? 'seu comentário');
            return AppNotificationItem(
              id: 'comment-support-${row.targetId}-${row.actorId}-${row.createdAt.toIso8601String()}',
              type: AppNotificationType.commentSupport,
              createdAt: row.createdAt,
              actorDisplayName: _profileLabel(profilesById[row.actorId]),
              actorAvatarUrl: profilesById[row.actorId]?.avatarUrl,
              title: 'Curtida em comentário',
              description:
                  '${_profileLabel(profilesById[row.actorId])} curtiu seu comentário "$preview".',
            );
          },
        ),
        ...postCommentRows.map(
          (row) => AppNotificationItem(
            id: 'post-comment-${row.id}-${row.actorId}',
            type: AppNotificationType.postComment,
            createdAt: row.createdAt,
            actorDisplayName: _profileLabel(profilesById[row.actorId]),
            actorAvatarUrl: profilesById[row.actorId]?.avatarUrl,
            title: row.isReply ? 'Nova resposta no seu post' : 'Novo comentário no seu post',
            description:
                '${_profileLabel(profilesById[row.actorId])} ${row.isReply ? 'respondeu em um comentário' : 'comentou'} no seu post "${ownPosts[row.postId] ?? 'seu post'}".',
          ),
        ),
        ...commentReplyRows.map(
          (row) {
            final comment = ownComments[row.parentCommentId];
            final preview = _truncate(comment?.body ?? 'seu comentário');
            return AppNotificationItem(
              id: 'comment-reply-${row.id}-${row.actorId}',
              type: AppNotificationType.commentReply,
              createdAt: row.createdAt,
              actorDisplayName: _profileLabel(profilesById[row.actorId]),
              actorAvatarUrl: profilesById[row.actorId]?.avatarUrl,
              title: 'Nova resposta no seu comentário',
              description:
                  '${_profileLabel(profilesById[row.actorId])} respondeu seu comentário "$preview".',
            );
          },
        ),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return items;
    } on PostgrestException catch (error) {
      throw Exception('Erro ao carregar notificações: ${error.message}');
    } catch (error) {
      throw Exception('Erro inesperado ao carregar notificações: $error');
    }
  }

  Future<List<_ActivityRow>> _fetchFollowerRows(String userId) async {
    final response = await _supabase
        .from('profile_followers')
        .select('follower_id, created_at')
        .eq('followed_id', userId)
        .order('created_at', ascending: false)
        .limit(20);

    return (response as List<dynamic>)
        .map(
          (item) => _ActivityRow(
            actorId: item['follower_id'] as String,
            targetId: null,
            createdAt: DateTime.parse(item['created_at'] as String),
          ),
        )
        .toList();
  }

  Future<List<_ActivityRow>> _fetchPostSupportRows(String userId, List<int> ownPostIds) async {
    if (ownPostIds.isEmpty) return const <_ActivityRow>[];

    final response = await _supabase
        .from('post_supports')
        .select('post_id, user_id, created_at')
        .inFilter('post_id', ownPostIds)
        .neq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(20);

    return (response as List<dynamic>)
        .map(
          (item) => _ActivityRow(
            actorId: item['user_id'] as String,
            targetId: (item['post_id'] as num).toInt(),
            createdAt: DateTime.parse(item['created_at'] as String),
          ),
        )
        .toList();
  }

  Future<List<_ActivityRow>> _fetchCommentLikeRows(String userId, List<int> ownCommentIds) async {
    if (ownCommentIds.isEmpty) return const <_ActivityRow>[];

    final response = await _supabase
        .from('comment_likes')
        .select('comment_id, user_id, created_at')
        .inFilter('comment_id', ownCommentIds)
        .neq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(20);

    return (response as List<dynamic>)
        .map(
          (item) => _ActivityRow(
            actorId: item['user_id'] as String,
            targetId: (item['comment_id'] as num).toInt(),
            createdAt: DateTime.parse(item['created_at'] as String),
          ),
        )
        .toList();
  }

  Future<List<_CommentActivityRow>> _fetchCommentsOnOwnPosts({
    required String userId,
    required List<int> ownPostIds,
    required Set<int> ownCommentIds,
  }) async {
    if (ownPostIds.isEmpty) return const <_CommentActivityRow>[];

    final response = await _supabase
        .from('comments')
        .select('id, post_id, user_id, created_at, parent_comment_id')
        .inFilter('post_id', ownPostIds)
        .neq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(30);

    return (response as List<dynamic>)
        .map(
          (item) => _CommentActivityRow(
            id: (item['id'] as num).toInt(),
            actorId: item['user_id'] as String,
            postId: (item['post_id'] as num).toInt(),
            parentCommentId: (item['parent_comment_id'] as num?)?.toInt(),
            createdAt: DateTime.parse(item['created_at'] as String),
          ),
        )
        .where((row) => row.parentCommentId == null || !ownCommentIds.contains(row.parentCommentId))
        .toList();
  }

  Future<List<_CommentActivityRow>> _fetchRepliesToOwnComments({
    required String userId,
    required List<int> ownCommentIds,
  }) async {
    if (ownCommentIds.isEmpty) return const <_CommentActivityRow>[];

    final response = await _supabase
        .from('comments')
        .select('id, post_id, user_id, created_at, parent_comment_id')
        .inFilter('parent_comment_id', ownCommentIds)
        .neq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(30);

    return (response as List<dynamic>)
        .map(
          (item) => _CommentActivityRow(
            id: (item['id'] as num).toInt(),
            actorId: item['user_id'] as String,
            postId: (item['post_id'] as num).toInt(),
            parentCommentId: (item['parent_comment_id'] as num?)?.toInt(),
            createdAt: DateTime.parse(item['created_at'] as String),
          ),
        )
        .where((row) => row.parentCommentId != null)
        .toList();
  }

  Future<Map<String, _ProfileRef>> _fetchProfiles(List<String> actorIds) async {
    if (actorIds.isEmpty) return const <String, _ProfileRef>{};

    final response = await _supabase
        .from('profiles')
        .select('id, full_name, username, avatar_url')
        .inFilter('id', actorIds);

    return {
      for (final item in response as List<dynamic>)
        item['id'] as String: _ProfileRef(
          id: item['id'] as String,
          fullName: item['full_name'] as String?,
          username: item['username'] as String?,
          avatarUrl: item['avatar_url'] as String?,
        ),
    };
  }

  String _profileLabel(_ProfileRef? profile) {
    final fullName = profile?.fullName?.trim();
    if (fullName != null && fullName.isNotEmpty) return fullName;
    final username = profile?.username?.trim();
    if (username != null && username.isNotEmpty) return username;
    return 'Alguém';
  }

  String _truncate(String value, {int maxLength = 42}) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength - 1)}…';
  }
}

class _ProfileRef {
  const _ProfileRef({
    required this.id,
    this.fullName,
    this.username,
    this.avatarUrl,
  });

  final String id;
  final String? fullName;
  final String? username;
  final String? avatarUrl;
}

class _CommentReference {
  const _CommentReference({
    required this.id,
    required this.postId,
    required this.body,
  });

  final int id;
  final int postId;
  final String body;
}

class _ActivityRow {
  const _ActivityRow({
    required this.actorId,
    required this.createdAt,
    this.targetId,
  });

  final String actorId;
  final int? targetId;
  final DateTime createdAt;
}

class _CommentActivityRow {
  const _CommentActivityRow({
    required this.id,
    required this.actorId,
    required this.postId,
    required this.createdAt,
    this.parentCommentId,
  });

  final int id;
  final String actorId;
  final int postId;
  final DateTime createdAt;
  final int? parentCommentId;

  bool get isReply => parentCommentId != null;
}
