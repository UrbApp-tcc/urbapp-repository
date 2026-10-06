import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/labels.dart';
import '../../app/app_session.dart';
import '../../app/routes.dart';
import '../../domain/models.dart';
import '../../services/institutional_service.dart';
import '../../services/notifications_service.dart';
import '../../services/occurrence_service.dart';
import '../../services/profile_service.dart';
import '../../services/ranking_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_formatter.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/occurrence_widgets.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import '../institutional/workspace_screen.dart';
import 'achievements_screen.dart';
import 'history_screens.dart';
import 'settings_screens.dart';

/// Perfil do cidadão (próprio, na aba) ou perfil público de outro usuário.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.profileId, this.isTab = false});

  final String? profileId;
  final bool isTab;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with OccurrenceListSync {
  final _profiles = ProfileService();
  final _occurrences = OccurrenceService();

  UserProfile? _profile;
  ParticipationSummary _summary = const ParticipationSummary();
  List<ProfileBadge> _badges = const [];
  List<ProfileContribution> _contributions = const [];
  List<Occurrence> _following = const [];
  InstitutionalAccess _access = const InstitutionalAccess();
  ParticipationStanding? _standing;
  int _reloads = 0;
  int _tab = 0;
  bool _loading = true;
  String? _error;

  String? get _profileId =>
      widget.profileId ?? Supabase.instance.client.auth.currentUser?.id;
  bool get _isMe => _profileId == Supabase.instance.client.auth.currentUser?.id;

  /// Conta de vereador verificado vendo o próprio perfil: identidade
  /// institucional no lugar da gamificação de cidadão.
  bool get _isCouncilorMe => _isMe && _access.isCouncilor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onOccurrenceChanged(Occurrence occurrence) {
    setState(() {
      _following = occurrence.followedByMe
          ? replaceIn(_following, occurrence)
          : _following.where((item) => item.id != occurrence.id).toList();
    });
  }

  Future<void> _load() async {
    final id = _profileId;
    if (id == null) return;
    setState(() => _error = null);
    try {
      final results = await Future.wait<dynamic>([
        _profiles.fetchProfile(id),
        _profiles.fetchParticipation(id),
        _profiles.fetchBadges(id),
        _profiles.fetchContributions(id, _occurrences.fetchByIds),
        if (_isMe) _occurrences.fetchFollowed(),
        if (_isMe) InstitutionalService().fetchMyAccess(),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = results[0] as UserProfile;
        _summary = results[1] as ParticipationSummary;
        _badges = results[2] as List<ProfileBadge>;
        _contributions = results[3] as List<ProfileContribution>;
        // Recarrega a aba Atuação junto com o perfil (puxar para atualizar).
        _reloads++;
        if (_isMe) {
          _following = results[4] as List<Occurrence>;
          _access = results[5] as InstitutionalAccess;
        }
      });
      if (_isMe) _loadStanding();
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Posição geral no ranking de cidadãos da cidade do perfil.
  Future<void> _loadStanding() async {
    final cityId = _profile?.cityId;
    if (cityId == null) return;
    try {
      final standing = await RankingService().fetchStanding(cityId);
      if (mounted) setState(() => _standing = standing);
    } catch (_) {
      // A posição é complementar no Perfil; o atalho para o Ranking continua.
    }
  }

  Future<void> _openRanking() async {
    await openCitizenRanking(context);
    _loadStanding();
  }

  Future<void> _toggleFollowProfile() async {
    final profile = _profile;
    if (profile == null) return;
    try {
      await _profiles.setFollowingProfile(profile.id, !profile.isFollowedByMe);
      await _load();
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    }
  }

  Future<void> _openSettings() async {
    final profile = _profile;
    if (profile == null) return;
    await Navigator.of(
      context,
    ).push(urbRoute(SettingsScreen(profile: profile, access: _access)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final body = profile == null
        ? (_loading
              ? const UrbLoadingView()
              : UrbErrorState(message: _error ?? '', onRetry: _load))
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 30),
              children: [
                _header(),
                _identity(profile),
                if (_isCouncilorMe) ...[
                  _councilorIdentity(),
                ] else ...[
                  _level(profile),
                  _stats(),
                  if (_badges.any((badge) => badge.earned) || _isMe)
                    _achievements(),
                  if (_isMe && _access.hasInstitutionalRole)
                    _workspaceShortcut(),
                ],
                UrbUnderlineTabs(
                  // Vereador: a atuação é o conteúdo principal do próprio
                  // perfil; acompanhar é institucional, então não há lista
                  // de "Recebendo atualizações".
                  labels: _isCouncilorMe
                      ? const ['Atuação', 'Contribuições']
                      : _isMe
                      ? const ['Contribuições', 'Recebendo atualizações']
                      : const ['Contribuições'],
                  selected: _tab,
                  background: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  onChanged: (index) => setState(() => _tab = index),
                ),
                if (_isCouncilorMe)
                  if (_tab == 0)
                    CouncilorWorkspace(
                      key: ValueKey(_reloads),
                      councilor: _access.councilor!,
                      embedded: true,
                    )
                  else
                    ..._contributionRows(profile)
                else if (_tab == 0)
                  ..._contributionRows(profile)
                else
                  ..._followingRows(),
              ],
            ),
          );
    if (widget.isTab) return body;
    return Scaffold(backgroundColor: UrbColors.canvas, body: body);
  }

  Widget _header() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 14,
        20,
        14,
      ),
      child: Row(
        children: [
          if (!widget.isTab)
            UrbSquareButton(
              icon: UrbIcons.chevronLeft,
              tooltip: 'Voltar',
              size: 36,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          const Spacer(),
          if (_isMe) ...[
            ValueListenableBuilder<int>(
              valueListenable: NotificationsService.unreadCount,
              builder: (context, count, _) => UrbBellButton(
                unreadCount: count,
                onPressed: () => openAlerts(context),
              ),
            ),
            const SizedBox(width: 8),
            UrbSquareButton(
              icon: UrbIcons.settings,
              tooltip: 'Configurações',
              onPressed: _openSettings,
            ),
          ],
        ],
      ),
    );
  }

  Widget _identity(UserProfile profile) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        children: [
          Stack(
            children: [
              profile.avatarUrl != null
                  ? UrbAvatar(
                      name: profile.fullName,
                      imageUrl: profile.avatarUrl,
                      size: 78,
                      rounded: false,
                    )
                  : Container(
                      width: 78,
                      height: 78,
                      decoration: const BoxDecoration(
                        color: UrbColors.blue,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        UrbAvatar.initialsOf(profile.fullName),
                        style: UrbText.h1.copyWith(color: Colors.white),
                      ),
                    ),
              Positioned(
                right: 3,
                bottom: 3,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: UrbColors.lime,
                    shape: BoxShape.circle,
                    border: Border.all(color: UrbColors.canvas, width: 2.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            profile.fullName,
            textAlign: TextAlign.center,
            style: UrbText.h2.copyWith(color: UrbColors.navy),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const UrbIcon(
                UrbIcons.location,
                size: 12,
                color: UrbColors.muted,
              ),
              const SizedBox(width: 4),
              Text(
                profile.cityLabel,
                style: UrbText.meta.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          if (profile.biography != null) ...[
            const SizedBox(height: 10),
            Text(
              profile.biography!,
              textAlign: TextAlign.center,
              style: UrbText.bodySmall,
            ),
          ],
          if (!_isMe) ...[
            const SizedBox(height: 14),
            UrbButton(
              label: profile.isFollowedByMe ? 'Seguindo' : 'Seguir',
              tone: profile.isFollowedByMe
                  ? UrbButtonTone.soft
                  : UrbButtonTone.blue,
              height: 40,
              onPressed: _toggleFollowProfile,
            ),
          ],
        ],
      ),
    );
  }

  Widget _level(UserProfile profile) {
    final progress = profile.levelProgress;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Nível ${progress.level} · ${progress.title}',
                  style: UrbText.caption.copyWith(
                    color: UrbColors.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                progress.isMaxLevel
                    ? '${profile.currentXp} XP · nível máximo'
                    : '${progress.xpIntoLevel} / ${progress.xpForLevel} XP',
                style: UrbText.caption,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            label: 'Progresso do nível: ${(progress.fraction * 100).round()}%',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: [
                  Container(height: 6, color: UrbColors.line),
                  FractionallySizedBox(
                    widthFactor: progress.fraction,
                    child: Container(height: 6, color: UrbColors.lime),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${plural(profile.currentPoints, 'ponto', 'pontos')} de participação',
                  style: UrbText.caption,
                ),
              ),
              if (_isMe && !_access.isCouncilor) _rankingLink(profile),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rankingLink(UserProfile profile) {
    final position = _standing?.eligible == true ? _standing?.position : null;
    final label = position != null && profile.cityName != null
        ? '#$position em ${profile.cityName}'
        : 'Ver ranking';
    return Semantics(
      button: true,
      label: position != null
          ? 'Posição $position em ${profile.cityName}. Abrir ranking de cidadãos'
          : 'Abrir ranking de cidadãos',
      excludeSemantics: true,
      child: InkWell(
        onTap: _openRanking,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: UrbText.caption.copyWith(
                  color: UrbColors.blue,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 2),
              const UrbIcon(UrbIcons.chevron, size: 13, color: UrbColors.blue),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stats() {
    Widget stat(
      String value,
      String label,
      VoidCallback? onTap, {
      bool divider = true,
    }) => Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            border: divider
                ? const Border(right: BorderSide(color: UrbColors.line))
                : null,
          ),
          child: Column(
            children: [
              Text(value, style: UrbText.stat),
              const SizedBox(height: 2),
              Text(label, style: UrbText.caption.copyWith(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: UrbColors.line),
          bottom: BorderSide(color: UrbColors.line),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            stat(
              '${_summary.reports}',
              'Relatos',
              () => setState(() => _tab = 0),
            ),
            stat(
              '${_summary.supports}',
              'Apoios',
              _isMe
                  ? () => Navigator.of(
                      context,
                    ).push(urbRoute(const SupportedHistoryScreen()))
                  : null,
            ),
            stat(
              '${_summary.validations}',
              'Validações',
              _isMe
                  ? () => Navigator.of(
                      context,
                    ).push(urbRoute(const ValidationHistoryScreen()))
                  : null,
              divider: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _achievements() {
    final earned = _badges.where((badge) => badge.earned).take(3).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final badge in earned)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFC8D2F8)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: UrbColors.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    badge.name,
                    style: UrbText.caption.copyWith(
                      color: const Color(0xFF2B3FC4),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          if (earned.isEmpty && _isMe)
            Text('Nenhuma conquista ainda.', style: UrbText.caption),
          UrbTextButton(
            'Ver todas',
            onPressed: () => Navigator.of(context).push(
              urbRoute(AchievementsScreen(badges: _badges, profile: _profile!)),
            ),
          ),
        ],
      ),
    );
  }

  /// Cargo, partido e verificação logo abaixo do nome.
  Widget _councilorIdentity() {
    final councilor = _access.councilor!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                [
                  'Vereador(a)',
                  if (councilor.party != null) councilor.party!,
                ].join(' · '),
                style: UrbText.meta.copyWith(
                  color: UrbColors.navy,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const UrbVerificationPill(label: 'Verificado'),
            ],
          ),
          UrbTextButton(
            'Ver como meu perfil aparece publicamente',
            onPressed: () => openCouncilor(context, councilor.id),
          ),
        ],
      ),
    );
  }

  Widget _workspaceShortcut() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: UrbButton(
        label: 'Sua atuação institucional',
        icon: UrbIcons.pencil,
        tone: UrbButtonTone.soft,
        expand: true,
        onPressed: () =>
            Navigator.of(context).push(urbRoute(const WorkspaceScreen())),
      ),
    );
  }

  List<Widget> _contributionRows(UserProfile profile) {
    if (!_isMe && !profile.isPublic) {
      return const [
        UrbEmptyState(
          icon: UrbIcons.lock,
          title: 'Perfil privado',
          message:
              'Esta pessoa optou por não exibir suas contribuições publicamente.',
        ),
      ];
    }
    if (_contributions.isEmpty) {
      return [
        UrbEmptyState(
          icon: UrbIcons.pencil,
          title: _isMe
              ? 'Você ainda não relatou nenhum problema'
              : 'Nenhuma contribuição pública',
          message: _isMe
              ? 'Seus relatos e as ocorrências que você iniciou aparecerão aqui.'
              : 'Quando houver relatos públicos, eles aparecerão aqui.',
          actionLabel: _isMe ? 'Relatar um problema' : null,
          onAction: _isMe ? () => openReportFlow(context) : null,
        ),
      ];
    }
    return [
      for (final contribution in _contributions)
        CompactOccurrenceRow(
          occurrence: contribution.occurrence,
          anonymous: _isMe && contribution.isAnonymous,
          role:
              '${contribution.isInitiator ? (_isMe ? 'Você iniciou esta ocorrência' : 'Iniciou esta ocorrência') : (_isMe ? 'Você adicionou um relato' : 'Adicionou um relato')} · '
              '${formatRelativeTime(contribution.contributedAt).toLowerCase()}',
          onTap: () => openOccurrence(
            context,
            occurrenceId: contribution.occurrence.id,
            initial: contribution.occurrence,
          ),
        ),
    ];
  }

  List<Widget> _followingRows() {
    if (_following.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(40),
          child: Center(
            child: Text('Você ainda não acompanha nenhuma ocorrência.'),
          ),
        ),
      ];
    }
    return [
      for (final occurrence in _following)
        CompactOccurrenceRow(
          occurrence: occurrence,
          role: 'Você recebe atualizações desta ocorrência',
          onTap: () => openOccurrence(
            context,
            occurrenceId: occurrence.id,
            initial: occurrence,
          ),
          trailing: UrbSquareButton(
            icon: UrbIcons.bookmark,
            tooltip: 'Parar de acompanhar ${occurrence.title}',
            size: 32,
            iconSize: 16,
            onPressed: () =>
                AppSession.instance.toggleFollow(context, occurrence),
          ),
        ),
    ];
  }
}
