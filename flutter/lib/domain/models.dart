import 'labels.dart';
import 'occurrence_status.dart';

int _int(dynamic value) => (value as num?)?.toInt() ?? 0;
int? _intOrNull(dynamic value) => (value as num?)?.toInt();
double _double(dynamic value) => (value as num?)?.toDouble() ?? 0;
DateTime? _date(dynamic value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;
String? _text(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Map<String, dynamic>? asJsonMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

/// Perfil institucional: não reivindicado, verificado ou participante (spec §19).
enum InstitutionalProfileStatus {
  unclaimed('Não reivindicado'),
  verified('Verificado'),
  participant('Participante');

  const InstitutionalProfileStatus(this.label);

  final String label;

  bool get isVerified => this != unclaimed;

  static InstitutionalProfileStatus fromCode(String? code) => switch (code) {
        'verified' => verified,
        'participant' => participant,
        _ => unclaimed,
      };
}

class OfficialActionSummary {
  const OfficialActionSummary({
    required this.actorKind,
    required this.actionType,
    required this.description,
    required this.createdAt,
    this.agencyName,
    this.agencyStatus = InstitutionalProfileStatus.unclaimed,
  });

  final String actorKind;
  final String actionType;
  final String description;
  final DateTime createdAt;
  final String? agencyName;
  final InstitutionalProfileStatus agencyStatus;

  String get actorLabel => actorKind == 'administration'
      ? 'Prefeitura'
      : (agencyName ?? 'Órgão responsável');

  static OfficialActionSummary? fromJson(dynamic raw) {
    final json = asJsonMap(raw);
    if (json == null) return null;
    return OfficialActionSummary(
      actorKind: json['actor_kind'] as String? ?? 'agency',
      actionType: json['action_type'] as String? ?? '',
      description: json['description'] as String? ?? '',
      createdAt: _date(json['created_at']) ?? DateTime.now(),
      agencyName: _text(json['agency_name']),
      agencyStatus: InstitutionalProfileStatus.fromCode(json['agency_profile_status'] as String?),
    );
  }
}

/// Ocorrência urbana única (entidade central, spec §29.2), lida de
/// `occurrence_feed_rows`. Contadores são derivados no backend.
class Occurrence {
  const Occurrence({
    required this.id,
    required this.title,
    this.summary,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    required this.latitude,
    required this.longitude,
    this.street,
    this.neighborhood,
    required this.cityId,
    required this.cityName,
    this.cityState,
    required this.categoryId,
    required this.categoryName,
    this.categorySlug,
    this.agencyId,
    this.agencyName,
    this.agencyType,
    this.agencyStatus = InstitutionalProfileStatus.unclaimed,
    required this.administrationId,
    this.jurisdictionType = 'municipal',
    this.externalResponsibleName,
    this.administrativePriority = false,
    this.reportsCount = 0,
    this.supportsCount = 0,
    this.recentSupportsCount = 0,
    this.commentsCount = 0,
    this.recentReportsCount = 0,
    this.imageCount = 0,
    this.primaryImageUrl,
    this.supportedByMe = false,
    this.followedByMe = false,
    this.contributedByMe = false,
    this.latestOfficialAction,
    this.lastActivityAt,
  });

  final int id;
  final String title;
  final String? summary;
  final OccurrenceStatus status;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final double latitude;
  final double longitude;
  final String? street;
  final String? neighborhood;
  final int cityId;
  final String cityName;
  final String? cityState;
  final int categoryId;
  final String categoryName;
  final String? categorySlug;
  final int? agencyId;
  final String? agencyName;
  final String? agencyType;
  final InstitutionalProfileStatus agencyStatus;
  final int administrationId;
  final String jurisdictionType;
  final String? externalResponsibleName;
  final bool administrativePriority;
  final int reportsCount;
  final int supportsCount;
  final int recentSupportsCount;
  final int commentsCount;
  final int recentReportsCount;
  final int imageCount;
  final String? primaryImageUrl;
  final bool supportedByMe;
  final bool followedByMe;
  final bool contributedByMe;
  final OfficialActionSummary? latestOfficialAction;
  final DateTime? lastActivityAt;

  bool get isMunicipal => jurisdictionType == 'municipal';

  String get locationLabel => neighborhood ?? street ?? cityName;

  String get fullAddress => [street, neighborhood, cityName]
      .whereType<String>()
      .where((part) => part.isNotEmpty)
      .join(', ');

  /// Motivo exibido no modo "Em alta" (spec §20: crescimento recente).
  String get trendLabel {
    if (recentSupportsCount > 0) {
      return '+$recentSupportsCount ${recentSupportsCount == 1 ? 'apoio' : 'apoios'} hoje';
    }
    if (recentReportsCount > 0) {
      return '$recentReportsCount ${recentReportsCount == 1 ? 'novo relato' : 'novos relatos'} hoje';
    }
    return '${plural(supportsCount, 'apoio', 'apoios')} · ${plural(reportsCount, 'relato', 'relatos')}';
  }

  Occurrence copyWith({
    bool? supportedByMe,
    int? supportsCount,
    bool? followedByMe,
    int? commentsCount,
    OccurrenceStatus? status,
  }) {
    return Occurrence(
      id: id,
      title: title,
      summary: summary,
      status: status ?? this.status,
      createdAt: createdAt,
      resolvedAt: resolvedAt,
      latitude: latitude,
      longitude: longitude,
      street: street,
      neighborhood: neighborhood,
      cityId: cityId,
      cityName: cityName,
      cityState: cityState,
      categoryId: categoryId,
      categoryName: categoryName,
      categorySlug: categorySlug,
      agencyId: agencyId,
      agencyName: agencyName,
      agencyType: agencyType,
      agencyStatus: agencyStatus,
      administrationId: administrationId,
      jurisdictionType: jurisdictionType,
      externalResponsibleName: externalResponsibleName,
      administrativePriority: administrativePriority,
      reportsCount: reportsCount,
      supportsCount: supportsCount ?? this.supportsCount,
      recentSupportsCount: recentSupportsCount,
      commentsCount: commentsCount ?? this.commentsCount,
      recentReportsCount: recentReportsCount,
      imageCount: imageCount,
      primaryImageUrl: primaryImageUrl,
      supportedByMe: supportedByMe ?? this.supportedByMe,
      followedByMe: followedByMe ?? this.followedByMe,
      contributedByMe: contributedByMe,
      latestOfficialAction: latestOfficialAction,
      lastActivityAt: lastActivityAt,
    );
  }

  factory Occurrence.fromJson(Map<String, dynamic> json, {String? Function(String?)? resolveImage}) {
    return Occurrence(
      id: _int(json['id']),
      title: (json['title'] as String?)?.trim() ?? 'Ocorrência urbana',
      summary: _text(json['summary']),
      status: OccurrenceStatus.fromCode(json['status'] as String?),
      createdAt: _date(json['created_at']) ?? DateTime.now(),
      resolvedAt: _date(json['resolved_at']),
      latitude: _double(json['latitude']),
      longitude: _double(json['longitude']),
      street: _text(json['street']),
      neighborhood: _text(json['neighborhood']),
      cityId: _int(json['city_id']),
      cityName: json['city_name'] as String? ?? '',
      cityState: _text(json['city_state']),
      categoryId: _int(json['category_id']),
      categoryName: json['category_name'] as String? ?? 'Outros',
      categorySlug: _text(json['category_slug']),
      agencyId: _intOrNull(json['agency_id']),
      agencyName: _text(json['agency_name']),
      agencyType: _text(json['agency_type']),
      agencyStatus: InstitutionalProfileStatus.fromCode(json['agency_profile_status'] as String?),
      administrationId: _int(json['administration_id']),
      jurisdictionType: json['jurisdiction_type'] as String? ?? 'municipal',
      externalResponsibleName: _text(json['external_responsible_name']),
      administrativePriority: json['administrative_priority'] == true,
      reportsCount: _int(json['reports_count']),
      supportsCount: _int(json['supports_count']),
      recentSupportsCount: _int(json['recent_supports_count']),
      commentsCount: _int(json['comments_count']),
      recentReportsCount: _int(json['recent_reports_count']),
      imageCount: _int(json['image_count']),
      primaryImageUrl: resolveImage?.call(json['primary_image_path'] as String?),
      supportedByMe: json['supported_by_me'] == true,
      followedByMe: json['followed_by_me'] == true,
      contributedByMe: json['contributed_by_me'] == true,
      latestOfficialAction: OfficialActionSummary.fromJson(json['latest_official_action']),
      lastActivityAt: _date(json['last_activity_at']),
    );
  }
}

class ReportImage {
  const ReportImage({required this.storagePath, required this.url, this.caption});

  final String storagePath;
  final String url;
  final String? caption;
}

/// Relato: contribuição estruturada de um cidadão sobre a ocorrência.
class OccurrenceReport {
  const OccurrenceReport({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.isAnonymous,
    this.authorId,
    required this.authorName,
    this.authorUsername,
    this.authorAvatarUrl,
    this.images = const [],
  });

  final int id;
  final String title;
  final String description;
  final DateTime createdAt;
  final bool isAnonymous;
  final String? authorId;
  final String authorName;
  final String? authorUsername;
  final String? authorAvatarUrl;
  final List<ReportImage> images;

  String get publicAuthor => isAnonymous && authorId == null ? 'Relato anônimo' : authorName;
}

class OccurrenceComment {
  OccurrenceComment({
    required this.id,
    required this.occurrenceId,
    this.parentId,
    required this.body,
    required this.createdAt,
    required this.authorId,
    required this.authorName,
    this.authorUsername,
    this.authorAvatarUrl,
    required this.likesCount,
    required this.likedByMe,
    List<OccurrenceComment>? replies,
  }) : replies = replies ?? [];

  final int id;
  final int occurrenceId;
  final int? parentId;
  final String body;
  final DateTime createdAt;
  final String authorId;
  final String authorName;
  final String? authorUsername;
  final String? authorAvatarUrl;
  int likesCount;
  bool likedByMe;
  final List<OccurrenceComment> replies;

  factory OccurrenceComment.fromJson(Map<String, dynamic> json) => OccurrenceComment(
        id: _int(json['id']),
        occurrenceId: _int(json['occurrence_id']),
        parentId: _intOrNull(json['parent_comment_id']),
        body: json['body'] as String? ?? '',
        createdAt: _date(json['created_at']) ?? DateTime.now(),
        authorId: json['author_id'] as String? ?? '',
        authorName: json['author_display_name'] as String? ?? 'Cidadão',
        authorUsername: _text(json['author_username']),
        authorAvatarUrl: _text(json['author_avatar_url']),
        likesCount: _int(json['likes_count']),
        likedByMe: json['liked_by_me'] == true,
      );
}

enum TimelineKind { community, official, councilor, platform, validation, moderation }

class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.actorKind,
    required this.eventType,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.kind,
    this.evidenceUrl,
    this.agencyId,
    this.councilorProfileId,
  });

  final int id;
  final String actorKind;
  final String eventType;
  final String title;
  final String description;
  final DateTime createdAt;
  final TimelineKind kind;
  final String? evidenceUrl;
  final int? agencyId;
  final int? councilorProfileId;
}

class ResolutionCycle {
  const ResolutionCycle({
    required this.id,
    required this.initiatorKind,
    required this.initiatedByMe,
    this.description,
    this.evidenceUrl,
    required this.openedAt,
    required this.expiresAt,
    required this.confirmations,
    required this.rejections,
    required this.confirmationsRequired,
    required this.rejectionsRequired,
    required this.radiusKm,
    this.myVote,
  });

  final int id;
  final String initiatorKind;
  final bool initiatedByMe;
  final String? description;
  final String? evidenceUrl;
  final DateTime openedAt;
  final DateTime expiresAt;
  final int confirmations;
  final int rejections;
  final int confirmationsRequired;
  final int rejectionsRequired;
  final double radiusKm;
  final String? myVote;

  Duration get remaining {
    final value = expiresAt.difference(DateTime.now());
    return value.isNegative ? Duration.zero : value;
  }

  String get initiatorLabel => switch (initiatorKind) {
        'agency' => 'O órgão responsável',
        'administration' => 'A Prefeitura',
        'councilor' => 'Um vereador que acompanha a demanda',
        _ => 'Um cidadão',
      };
}

/// Contexto de validação devolvido por `get_resolution_context` (backend decide).
class ResolutionContext {
  const ResolutionContext({
    required this.canStart,
    this.cooldownUntil,
    required this.evidenceRequired,
    required this.confirmationsRequired,
    required this.rejectionsRequired,
    required this.radiusKm,
    required this.durationHours,
    required this.cooldownHours,
    this.cycle,
  });

  final bool canStart;
  final DateTime? cooldownUntil;
  final bool evidenceRequired;
  final int confirmationsRequired;
  final int rejectionsRequired;
  final double radiusKm;
  final double durationHours;
  final double cooldownHours;
  final ResolutionCycle? cycle;

  factory ResolutionContext.fromJson(
    Map<String, dynamic> json, {
    String? Function(String?)? resolveImage,
  }) {
    final settings = asJsonMap(json['settings']) ?? const {};
    final cycle = asJsonMap(json['cycle']);
    return ResolutionContext(
      canStart: json['can_start'] == true,
      cooldownUntil: _date(json['cooldown_until']),
      evidenceRequired: json['evidence_required'] == true,
      confirmationsRequired: _int(settings['confirmations_required']),
      rejectionsRequired: _int(settings['rejections_required']),
      radiusKm: _double(settings['radius_km']),
      durationHours: _double(settings['duration_hours']),
      cooldownHours: _double(settings['cooldown_hours']),
      cycle: cycle == null
          ? null
          : ResolutionCycle(
              id: _int(cycle['id']),
              initiatorKind: cycle['initiator_kind'] as String? ?? 'citizen',
              initiatedByMe: cycle['initiated_by_me'] == true,
              description: _text(cycle['description']),
              evidenceUrl: resolveImage?.call(cycle['evidence_storage_path'] as String?),
              openedAt: _date(cycle['opened_at']) ?? DateTime.now(),
              expiresAt: _date(cycle['expires_at']) ?? DateTime.now(),
              confirmations: _int(cycle['confirmations']),
              rejections: _int(cycle['rejections']),
              confirmationsRequired: _int(cycle['confirmations_required']),
              rejectionsRequired: _int(cycle['rejections_required']),
              radiusKm: _double(cycle['radius_km']),
              myVote: _text(cycle['my_vote']),
            ),
    );
  }
}

class DuplicateCandidate {
  const DuplicateCandidate({required this.occurrence, required this.distanceKm});

  final Occurrence occurrence;
  final double distanceKm;
}

class LookupOption {
  const LookupOption({required this.id, required this.name, this.extra});

  final int id;
  final String name;
  final String? extra;
}

class CategoryOption {
  const CategoryOption({
    required this.id,
    required this.name,
    this.slug,
    this.requiresResolutionEvidence = false,
  });

  final int id;
  final String name;
  final String? slug;
  final bool requiresResolutionEvidence;
}

class CityOption {
  const CityOption({required this.id, required this.name, required this.stateCode});

  final int id;
  final String name;
  final String stateCode;

  String get label => '$name · ${stateCode.toUpperCase()}';
}

/// Resultado de uma operação de relato (nova ocorrência ou relato adicionado).
class ReportSubmission {
  const ReportSubmission({
    required this.occurrenceId,
    required this.postId,
    required this.createdOccurrence,
    this.reportsCount,
  });

  final int occurrenceId;
  final int postId;
  final bool createdOccurrence;
  final int? reportsCount;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
    this.occurrenceId,
    this.eventType,
    this.actorKind,
    this.agencyId,
    this.occurrenceTitle,
    this.payload = const {},
  });

  final int id;
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  final int? occurrenceId;
  final String? eventType;
  final String? actorKind;
  final int? agencyId;
  final String? occurrenceTitle;
  final Map<String, dynamic> payload;

  bool get isValidation => eventType == 'validation_opened';
  bool get isOfficial => actorKind == 'agency' || actorKind == 'administration';
  bool get isResolved => eventType == 'resolution_confirmed';
  bool get isComment => type == 'occurrence_comment' || type == 'comment_reply';
  bool get isAdministrationContact => type == 'administration_contact';

  /// Decisão da administração sobre um pedido de perfil institucional.
  bool get isInstitutionalReview => type == 'institutional_review';
  bool get isInstitutionalApproval => isInstitutionalReview && payload['decision'] == 'approved';

  String? get contactKindLabel => _text(payload['contact_kind_label']);
  String? get contactAdministrationName => _text(payload['administration_name']);
  String? get contactRequesterName => _text(payload['requester_name']);
  String? get contactRequesterUsername => _text(payload['requester_username']);
  String? get contactRequesterBadge => _text(payload['requester_badge_name']);
  int? get contactRequesterLevel => _intOrNull(payload['requester_level']);
  String? get contactSubject => _text(payload['request_subject']);
  String? get contactMessage => _text(payload['request_message']);
  int? get contactRequestId => _intOrNull(payload['request_id']);
  int get contactMediaCount => _intOrNull(payload['media_count']) ?? 0;

  AppNotification markRead() => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        createdAt: createdAt,
        read: true,
        occurrenceId: occurrenceId,
        eventType: eventType,
        actorKind: actorKind,
        agencyId: agencyId,
        occurrenceTitle: occurrenceTitle,
        payload: payload,
      );

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final payload = asJsonMap(json['payload']) ?? const {};
    return AppNotification(
      id: _int(json['id']),
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      createdAt: _date(json['created_at']) ?? DateTime.now(),
      read: json['read_at'] != null,
      occurrenceId: _intOrNull(payload['occurrence_id']),
      eventType: _text(payload['event_type']),
      actorKind: _text(payload['actor_kind']),
      agencyId: _intOrNull(payload['agency_id']),
      occurrenceTitle: _text(payload['occurrence_title']),
      payload: payload,
    );
  }
}
