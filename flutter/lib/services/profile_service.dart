import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';
import '../logic/app_rules.dart';
import '../utils/error_formatter.dart';

class ProfileBadge {
  const ProfileBadge({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    this.minLevel,
    this.awardedAt,
  });

  final int id;
  final String name;
  final String slug;
  final String description;
  final int? minLevel;
  final DateTime? awardedAt;

  bool get earned => awardedAt != null;
}

class ParticipationSummary {
  const ParticipationSummary({this.reports = 0, this.supports = 0, this.validations = 0, this.following = 0});

  final int reports;
  final int supports;
  final int validations;
  final int following;
}

class ProfileContribution {
  const ProfileContribution({
    required this.occurrence,
    required this.isAnonymous,
    required this.isInitiator,
    required this.contributedAt,
  });

  final Occurrence occurrence;
  final bool isAnonymous;
  final bool isInitiator;
  final DateTime contributedAt;
}

class ValidationHistoryItem {
  const ValidationHistoryItem({
    required this.occurrence,
    required this.confirmed,
    required this.votedAt,
    required this.cycleStatus,
  });

  final Occurrence occurrence;
  final bool confirmed;
  final DateTime votedAt;
  final String cycleStatus;
}

class NotificationPreferences {
  const NotificationPreferences({
    this.occurrenceUpdates = true,
    this.comments = true,
    this.officialUpdates = true,
    this.validations = true,
    this.councilorActivity = true,
  });

  final bool occurrenceUpdates;
  final bool comments;
  final bool officialUpdates;
  final bool validations;
  final bool councilorActivity;

  Map<String, bool> toJson() => {
        'occurrence_updates': occurrenceUpdates,
        'comments': comments,
        'official_updates': officialUpdates,
        'validations': validations,
        'councilor_activity': councilorActivity,
      };

  NotificationPreferences copyWithKey(String key, bool value) => NotificationPreferences(
        occurrenceUpdates: key == 'occurrence_updates' ? value : occurrenceUpdates,
        comments: key == 'comments' ? value : comments,
        officialUpdates: key == 'official_updates' ? value : officialUpdates,
        validations: key == 'validations' ? value : validations,
        councilorActivity: key == 'councilor_activity' ? value : councilorActivity,
      );
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.username,
    this.biography,
    this.avatarUrl,
    this.cityId,
    this.cityName,
    this.cityState,
    required this.isPublic,
    required this.currentXp,
    required this.currentPoints,
    required this.levelProgress,
    this.featuredBadgeId,
    this.createdAt,
    required this.followersCount,
    required this.isFollowedByMe,
  });

  final String id;
  final String fullName;
  final String username;
  final String? biography;
  final String? avatarUrl;
  final int? cityId;
  final String? cityName;
  final String? cityState;
  final bool isPublic;
  final int currentXp;
  final int currentPoints;
  final LevelProgress levelProgress;
  final int? featuredBadgeId;
  final DateTime? createdAt;
  final int followersCount;
  final bool isFollowedByMe;

  String get cityLabel {
    if (cityName == null) return 'Cidade não informada';
    return cityState == null ? cityName! : '$cityName, ${cityState!.toUpperCase()}';
  }
}

class ProfileService {
  ProfileService({SupabaseClient? supabase}) : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const _profileImagesBucket = 'profile-images';

  String? get currentUserId => _supabase.auth.currentUser?.id;
  String? get currentEmail => _supabase.auth.currentUser?.email;

  Future<T> _guard<T>(Future<T> Function() run, String fallback) async {
    try {
      return await run();
    } on PostgrestException catch (error) {
      throw Exception(friendlyBackendMessage(error.message, fallback));
    } on StorageException catch (error) {
      throw Exception('$fallback (${error.message})');
    }
  }

  Future<UserProfile> fetchProfile(String profileId) {
    return _guard(() async {
      final viewer = currentUserId;
      if (viewer == profileId) await _supabase.rpc('ensure_my_profile');
      final responses = await Future.wait<dynamic>([
        _supabase
            .from('profiles')
            .select('id, full_name, username, biography, avatar_url, city_id, is_public, current_xp, '
                'current_points, featured_badge_id, created_at, cities(name, state)')
            .eq('id', profileId)
            .maybeSingle(),
        _fetchLevels(),
        _supabase.from('profile_followers').select('follower_id').eq('followed_id', profileId).count(CountOption.exact),
        viewer == null || viewer == profileId
            ? Future<dynamic>.value(null)
            : _supabase
                .from('profile_followers')
                .select('follower_id')
                .eq('follower_id', viewer)
                .eq('followed_id', profileId)
                .maybeSingle(),
      ]);
      final levels = responses[1] as List<LevelThreshold>;
      final followersCount = (responses[2] as PostgrestResponse).count;
      final isFollowedByMe = responses[3] != null;
      if (responses[0] == null) {
        // Perfil privado de outra pessoa: o banco só entrega a identificação básica.
        final card = asJsonMap(await _supabase.rpc('get_profile_card', params: {'target_profile_id': profileId}));
        if (card == null) throw Exception('Perfil não encontrado.');
        final cardName = (card['full_name'] as String?)?.trim();
        final cardUsername = (card['username'] as String?)?.trim() ?? 'cidadao';
        return UserProfile(
          id: card['id'] as String,
          fullName: cardName == null || cardName.isEmpty ? cardUsername : cardName,
          username: cardUsername,
          biography: null,
          avatarUrl: card['avatar_url'] as String?,
          cityId: null,
          cityName: null,
          cityState: null,
          isPublic: false,
          currentXp: 0,
          currentPoints: 0,
          levelProgress: calculateLevelProgress(0, levels),
          featuredBadgeId: null,
          createdAt: null,
          followersCount: followersCount,
          isFollowedByMe: isFollowedByMe,
        );
      }
      final row = Map<String, dynamic>.from(responses[0] as Map);
      final city = asJsonMap(row['cities']);
      final xp = (row['current_xp'] as num?)?.toInt() ?? 0;
      final fullName = (row['full_name'] as String?)?.trim();
      final username = (row['username'] as String?)?.trim() ?? 'cidadao';
      return UserProfile(
        id: row['id'] as String,
        fullName: fullName == null || fullName.isEmpty ? username : fullName,
        username: username,
        biography: row['biography'] as String?,
        avatarUrl: row['avatar_url'] as String?,
        cityId: (row['city_id'] as num?)?.toInt(),
        cityName: city?['name'] as String?,
        cityState: city?['state'] as String?,
        isPublic: row['is_public'] != false,
        currentXp: xp,
        currentPoints: (row['current_points'] as num?)?.toInt() ?? 0,
        levelProgress: calculateLevelProgress(xp, levels),
        featuredBadgeId: (row['featured_badge_id'] as num?)?.toInt(),
        createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
        followersCount: followersCount,
        isFollowedByMe: isFollowedByMe,
      );
    }, 'Não foi possível carregar o perfil.');
  }

  Future<List<LevelThreshold>> _fetchLevels() async {
    try {
      final rows = await _supabase.from('levels').select('level, min_xp, title').order('min_xp', ascending: true);
      final levels = (rows as List)
          .map((row) => LevelThreshold(
                level: (row['level'] as num).toInt(),
                minXp: (row['min_xp'] as num).toInt(),
                title: row['title'] as String,
              ))
          .toList();
      return levels.isEmpty ? defaultLevels : levels;
    } catch (_) {
      return defaultLevels;
    }
  }

  Future<ParticipationSummary> fetchParticipation(String profileId) {
    return _guard(() async {
      final data = asJsonMap(await _supabase.rpc('get_participation_summary', params: {'target_profile_id': profileId}));
      int read(String key) => (data?[key] as num?)?.toInt() ?? 0;
      return ParticipationSummary(
        reports: read('reports'),
        supports: read('supports'),
        validations: read('validations'),
        following: read('following'),
      );
    }, 'Não foi possível carregar sua participação.');
  }

  /// Contribuições (relatos). Anônimas aparecem apenas para o próprio autor.
  Future<List<ProfileContribution>> fetchContributions(
    String profileId,
    Future<List<Occurrence>> Function(Iterable<int>) loadOccurrences,
  ) {
    return _guard(() async {
      final rows = await _supabase.rpc('get_profile_contributions', params: {'target_profile_id': profileId}) as List;
      final occurrences = {
        for (final occurrence in await loadOccurrences(rows.map((row) => (row['occurrence_id'] as num).toInt())))
          occurrence.id: occurrence,
      };
      final seen = <int>{};
      final result = <ProfileContribution>[];
      for (final row in rows) {
        final occurrenceId = (row['occurrence_id'] as num).toInt();
        final occurrence = occurrences[occurrenceId];
        if (occurrence == null || !seen.add(occurrenceId)) continue;
        result.add(ProfileContribution(
          occurrence: occurrence,
          isAnonymous: row['is_anonymous'] == true,
          isInitiator: row['is_initiator'] == true,
          contributedAt: DateTime.parse(row['contributed_at'] as String),
        ));
      }
      return result;
    }, 'Não foi possível carregar as contribuições.');
  }

  Future<List<ValidationHistoryItem>> fetchMyValidations(
    Future<List<Occurrence>> Function(Iterable<int>) loadOccurrences,
  ) {
    return _guard(() async {
      final rows = await _supabase.rpc('get_my_validation_votes') as List;
      final occurrences = {
        for (final occurrence in await loadOccurrences(rows.map((row) => (row['occurrence_id'] as num).toInt())))
          occurrence.id: occurrence,
      };
      return rows
          .map((row) {
            final occurrence = occurrences[(row['occurrence_id'] as num).toInt()];
            if (occurrence == null) return null;
            return ValidationHistoryItem(
              occurrence: occurrence,
              confirmed: row['decision'] == 'confirm',
              votedAt: DateTime.parse(row['voted_at'] as String),
              cycleStatus: row['cycle_status'] as String? ?? 'pending',
            );
          })
          .whereType<ValidationHistoryItem>()
          .toList();
    }, 'Não foi possível carregar suas validações.');
  }

  /// Catálogo de insígnias com as conquistadas pelo usuário.
  Future<List<ProfileBadge>> fetchBadges(String profileId) {
    return _guard(() async {
      final responses = await Future.wait<dynamic>([
        _supabase.from('badges').select('id, name, slug, description, min_level').order('min_level', ascending: true),
        _supabase.from('user_badges').select('badge_id, awarded_at').eq('user_id', profileId),
      ]);
      final awarded = {
        for (final row in responses[1] as List) (row['badge_id'] as num).toInt(): DateTime.parse(row['awarded_at'] as String),
      };
      return (responses[0] as List)
          .map((row) => ProfileBadge(
                id: (row['id'] as num).toInt(),
                name: row['name'] as String,
                slug: row['slug'] as String,
                description: row['description'] as String? ?? '',
                minLevel: (row['min_level'] as num?)?.toInt(),
                awardedAt: awarded[(row['id'] as num).toInt()],
              ))
          .toList();
    }, 'Não foi possível carregar as conquistas.');
  }

  Future<void> updateProfile({
    required String fullName,
    required String username,
    String? biography,
    int? cityId,
    String? avatarUrl,
    int? featuredBadgeId,
    bool clearFeaturedBadge = false,
  }) {
    final userId = currentUserId;
    if (userId == null) throw Exception('Entre na sua conta para continuar.');
    return _guard(() async {
      await _supabase.from('profiles').update({
        'full_name': fullName.trim(),
        'username': username.trim(),
        'biography': (biography?.trim().isEmpty ?? true) ? null : biography!.trim(),
        'city_id': ?cityId,
        'avatar_url': ?avatarUrl,
        if (featuredBadgeId != null || clearFeaturedBadge) 'featured_badge_id': featuredBadgeId,
      }).eq('id', userId);
    }, 'Não foi possível salvar o perfil.');
  }

  Future<void> setPublicProfile(bool value) {
    final userId = currentUserId;
    if (userId == null) throw Exception('Entre na sua conta para continuar.');
    return _guard(() async {
      await _supabase.from('profiles').update({'is_public': value}).eq('id', userId);
    }, 'Não foi possível atualizar a privacidade.');
  }

  Future<String> uploadAvatar(XFile file) {
    final userId = currentUserId;
    if (userId == null) throw Exception('Entre na sua conta para continuar.');
    return _guard(() async {
      final dot = file.name.lastIndexOf('.');
      final extension = dot < 0 ? 'jpg' : file.name.substring(dot + 1).toLowerCase();
      final path = '$userId/avatar/avatar.$extension';
      await _supabase.storage.from(_profileImagesBucket).uploadBinary(
            path,
            await file.readAsBytes(),
            fileOptions: FileOptions(upsert: true, contentType: extension == 'png' ? 'image/png' : 'image/jpeg'),
          );
      final url = _supabase.storage.from(_profileImagesBucket).getPublicUrl(path);
      return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
    }, 'Não foi possível enviar a foto.');
  }

  Future<void> setFollowingProfile(String profileId, bool follow) {
    final userId = currentUserId;
    if (userId == null) throw Exception('Entre na sua conta para continuar.');
    return _guard(() async {
      if (follow) {
        await _supabase.from('profile_followers').insert({'follower_id': userId, 'followed_id': profileId});
      } else {
        await _supabase.from('profile_followers').delete().eq('follower_id', userId).eq('followed_id', profileId);
      }
    }, 'Não foi possível atualizar.');
  }

  Future<NotificationPreferences> fetchNotificationPreferences() {
    final userId = currentUserId;
    if (userId == null) return Future.value(const NotificationPreferences());
    return _guard(() async {
      final row = await _supabase.from('notification_preferences').select().eq('user_id', userId).maybeSingle();
      if (row == null) return const NotificationPreferences();
      return NotificationPreferences(
        occurrenceUpdates: row['occurrence_updates'] != false,
        comments: row['comments'] != false,
        officialUpdates: row['official_updates'] != false,
        validations: row['validations'] != false,
        councilorActivity: row['councilor_activity'] != false,
      );
    }, 'Não foi possível carregar as preferências.');
  }

  Future<void> saveNotificationPreferences(NotificationPreferences preferences) {
    final userId = currentUserId;
    if (userId == null) throw Exception('Entre na sua conta para continuar.');
    return _guard(() async {
      final existing = await _supabase.from('notification_preferences').select('user_id').eq('user_id', userId).maybeSingle();
      if (existing == null) {
        await _supabase.from('notification_preferences').insert({'user_id': userId, ...preferences.toJson()});
      } else {
        await _supabase.from('notification_preferences').update(preferences.toJson()).eq('user_id', userId);
      }
    }, 'Não foi possível salvar as preferências.');
  }
}
