import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../logic/app_rules.dart';
import '../services/feed_service.dart';
import '../services/profile_service.dart';
import '../theme/urbapp_design.dart';
import '../utils/error_formatter.dart';
import '../widgets/city_skyline.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/urb_dialog.dart';
import '../widgets/urb_post_image.dart';
import '../widgets/urb_primary_button.dart';
import '../widgets/urb_status_chip.dart';
import '../widgets/urb_text_field.dart';
import 'agency_profiles_screen.dart';
import 'post_detail_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.profileUserId,
    required this.currentUserId,
    this.onSignOut,
    this.isActive = false,
  });

  final String profileUserId;
  final String? currentUserId;
  final Future<void> Function()? onSignOut;
  final bool isActive;

  static Future<void> open(
    BuildContext context, {
    required String profileUserId,
    required String? currentUserId,
    Future<void> Function()? onSignOut,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(
          profileUserId: profileUserId,
          currentUserId: currentUserId,
          onSignOut: onSignOut,
        ),
      ),
    );
  }

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _profileService = ProfileService();

  UserProfileData? _profile;
  List<ProfileCityOption> _cities = const [];
  List<ProfileBadge> _availableBadges = const [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isFollowingLoading = false;

  bool get _isOwnProfile => widget.currentUserId == widget.profileUserId;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void didUpdateWidget(ProfileScreen old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);

    try {
      final profile = await _profileService.fetchProfile(
        profileUserId: widget.profileUserId,
        viewerUserId: widget.currentUserId,
      );
      final cities = _isOwnProfile
          ? await _profileService.fetchCities()
          : const <ProfileCityOption>[];

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _cities = cities;
        _availableBadges = _isOwnProfile ? profile.badges : [];
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showUrbSnack(context, friendlyError(error), error: true);
    }
  }

  Future<void> _toggleFollow() async {
    final viewerUserId = widget.currentUserId;
    final profile = _profile;
    if (viewerUserId == null || profile == null || _isOwnProfile) return;

    setState(() => _isFollowingLoading = true);

    try {
      if (profile.isFollowing) {
        await _profileService.unfollowProfile(
          viewerUserId: viewerUserId,
          profileUserId: profile.id,
        );
      } else {
        await _profileService.followProfile(
          viewerUserId: viewerUserId,
          profileUserId: profile.id,
        );
      }

      await _loadProfile();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isFollowingLoading = false);
      showUrbSnack(context, friendlyError(error), error: true);
    } finally {
      if (mounted) {
        setState(() => _isFollowingLoading = false);
      }
    }
  }

  Future<void> _openEditProfileSheet() async {
    final profile = _profile;
    if (profile == null || !_isOwnProfile) return;

    final result = await showUrbDialog<_EditProfileResult>(
      context: context,
      builder: (context) => _EditProfileSheet(
        profile: profile,
        cities: _cities,
        badgesOptions: _availableBadges,
      ),
    );

    if (result == null) return;

    setState(() => _isSaving = true);
    try {
      String? avatarUrl;
      if (result.avatarFile != null && widget.currentUserId != null) {
        avatarUrl = await _profileService.uploadAvatar(
          userId: widget.currentUserId!,
          file: result.avatarFile!,
        );
      }

      await _profileService.updateProfile(
        userId: widget.profileUserId,
        fullName: result.fullName,
        username: result.username,
        biography: result.biography,
        cityId: result.cityId,
        featuredBadgeId: result.featuredBadgeId,
        avatarUrl: avatarUrl,
      );

      await _loadProfile();

      if (!mounted) return;
      showUrbSnack(context, 'Perfil atualizado com sucesso.');
    } catch (error) {
      if (!mounted) return;
      showUrbSnack(context, friendlyError(error), error: true);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _openSettingsSheet() async {
    if (!_isOwnProfile) return;

    await showUrbDialog<void>(
      context: context,
      builder: (dialogContext) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UrbDialogHeader(
              icon: Icons.tune_rounded,
              title: 'Configurações',
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
            const SizedBox(height: 18),
            _SettingsOption(
              icon: Icons.edit_outlined,
              title: 'Editar perfil',
              subtitle: 'Foto, nome, biografia, cidade e insígnia',
              onTap: () {
                Navigator.of(dialogContext).pop();
                _openEditProfileSheet();
              },
            ),
            if (widget.currentUserId != null) ...[
              const SizedBox(height: 10),
              _SettingsOption(
                icon: Icons.account_balance_outlined,
                title: 'Perfis institucionais',
                subtitle: 'Criar ou gerenciar secretaria/prefeitura',
                color: const Color(0xFF1E40AF),
                background: const Color(0xFFDBEAFE),
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  AgencyProfilesScreen.open(
                    context,
                    currentUserId: widget.currentUserId!,
                  );
                },
              ),
            ],
            if (widget.onSignOut != null) ...[
              const SizedBox(height: 10),
              _SettingsOption(
                icon: Icons.logout_rounded,
                title: 'Sair da conta',
                subtitle: 'Encerrar a sessão neste aparelho',
                color: const Color(0xFFB91C1C),
                background: const Color(0xFFFEE2E2),
                onTap: () async {
                  Navigator.of(dialogContext).pop();
                  await widget.onSignOut!.call();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: UrbColors.surface,
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 132),
          children: [
            _ProfileHero(
              profile: _isLoading ? null : profile,
              isOwnProfile: _isOwnProfile,
              onBack: canPop ? () => Navigator.of(context).pop() : null,
              onOpenSettings: _isOwnProfile ? _openSettingsSheet : null,
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 70, 20, 0),
                child: Column(
                  children: [
                    UrbSkeleton(width: 160, height: 22),
                    SizedBox(height: 10),
                    UrbSkeleton(width: 120, height: 14),
                    SizedBox(height: 24),
                    UrbSkeleton(height: 84, radius: 22),
                    SizedBox(height: 18),
                    UrbSkeleton(height: 150, radius: 26),
                  ],
                ),
              )
            else if (profile == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 80, 24, 0),
                child: Column(
                  children: [
                    const UrbEmptyState(
                      icon: Icons.person_off_outlined,
                      title: 'Não foi possível carregar o perfil',
                      text: 'Verifique sua conexão e tente de novo.',
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _loadProfile,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tentar novamente'),
                      style: TextButton.styleFrom(
                        foregroundColor: UrbColors.violetDeep,
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ProfileIdentity(
                      profile: profile,
                      isOwnProfile: _isOwnProfile,
                      isSaving: _isSaving,
                      isFollowingLoading: _isFollowingLoading,
                      onEditProfile: _openEditProfileSheet,
                      onToggleFollow: _toggleFollow,
                    ),
                    const SizedBox(height: 22),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 60),
                      child: _StatsRow(profile: profile),
                    ),
                    const SizedBox(height: 18),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 120),
                      child: _LevelCard(profile: profile),
                    ),
                    const SizedBox(height: 26),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 180),
                      child: _BadgesRow(profile: profile),
                    ),
                    const SizedBox(height: 26),
                    _PostsSection(
                      posts: profile.posts,
                      isOwnProfile: _isOwnProfile,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// Topo roxo, avatar e identidade
// ──────────────────────────────────────────────────────────

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.profile,
    required this.isOwnProfile,
    required this.onBack,
    required this.onOpenSettings,
  });

  final UserProfileData? profile;
  final bool isOwnProfile;
  final VoidCallback? onBack;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final data = profile;
    final badge = data?.featuredBadge;

    return SizedBox(
      height: 250 + MediaQuery.paddingOf(context).top,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 190 + MediaQuery.paddingOf(context).top,
            decoration: const BoxDecoration(
              color: UrbColors.hero,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 130,
                  child: CitySkyline(),
                ),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Row(
                      children: [
                        onBack == null
                            ? const SizedBox(width: 44)
                            : _GlassSquare(
                                icon: Icons.arrow_back_rounded,
                                tooltip: 'Voltar',
                                onPressed: onBack!,
                              ),
                        Expanded(
                          child: Text(
                            'Perfil',
                            textAlign: TextAlign.center,
                            style: UrbText.display(
                              size: 19,
                              weight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        onOpenSettings == null
                            ? const SizedBox(width: 44)
                            : _GlassSquare(
                                icon: Icons.tune_rounded,
                                tooltip: 'Configurações',
                                onPressed: onOpenSettings!,
                              ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Avatar sobreposto ao topo, com a insígnia em destaque no canto.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.85, end: 1),
                duration: UrbMotion.of(
                  context,
                  const Duration(milliseconds: 500),
                ),
                curve: Curves.easeOutBack,
                builder: (context, value, child) =>
                    Transform.scale(scale: value, child: child),
                child: SizedBox(
                  width: 128,
                  height: 128,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 128,
                        height: 128,
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x59180F4A),
                              blurRadius: 30,
                              offset: Offset(0, 14),
                            ),
                          ],
                        ),
                        child: data == null
                            ? const UrbSkeleton(
                                width: 118,
                                height: 118,
                                radius: 59,
                              )
                            : _ProfileAvatar(
                                avatarUrl: data.avatarUrl,
                                label: data.fullName,
                                size: 118,
                              ),
                      ),
                      if (badge != null)
                        Positioned(
                          right: -8,
                          bottom: -2,
                          child: Container(
                            width: 54,
                            height: 54,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x2E1A1A2E),
                                  blurRadius: 14,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Tooltip(
                              message: badge.name,
                              child: _BadgeMedal(badge: badge, size: 44),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassSquare extends StatelessWidget {
  const _GlassSquare({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: Colors.white, size: 21),
          ),
        ),
      ),
    );
  }
}

class _ProfileIdentity extends StatelessWidget {
  const _ProfileIdentity({
    required this.profile,
    required this.isOwnProfile,
    required this.isSaving,
    required this.isFollowingLoading,
    required this.onEditProfile,
    required this.onToggleFollow,
  });

  final UserProfileData profile;
  final bool isOwnProfile;
  final bool isSaving;
  final bool isFollowingLoading;
  final VoidCallback onEditProfile;
  final VoidCallback onToggleFollow;

  @override
  Widget build(BuildContext context) {
    final bio = profile.biography?.trim();
    final city = profile.cityName?.trim();

    return FadeSlideIn(
      offsetY: 12,
      child: Column(
        children: [
          const SizedBox(height: 14),
          Text(
            profile.fullName,
            textAlign: TextAlign.center,
            style: UrbText.display(size: 26, weight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(
                '@${profile.username}',
                style: UrbText.body(size: 14, height: 1.3),
              ),
              if (city != null && city.isNotEmpty) ...[
                Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: Color(0xFF9CA3AF),
                    shape: BoxShape.circle,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 15,
                      color: UrbColors.violet,
                    ),
                    const SizedBox(width: 3),
                    Text(city, style: UrbText.body(size: 14, height: 1.3)),
                  ],
                ),
              ],
            ],
          ),
          if (bio != null && bio.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              bio,
              textAlign: TextAlign.center,
              style: UrbText.body(
                size: 14,
                color: const Color(0xFF374151),
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (isOwnProfile)
            _PillButton(
              icon: Icons.edit_outlined,
              label: isSaving ? 'Salvando...' : 'Personalizar',
              dark: true,
              loading: isSaving,
              onPressed: isSaving ? null : onEditProfile,
            )
          else
            AnimatedSwitcher(
              duration: UrbMotion.of(context, UrbMotion.fast),
              child: _PillButton(
                key: ValueKey(profile.isFollowing),
                icon: profile.isFollowing
                    ? Icons.check_rounded
                    : Icons.person_add_alt_1_rounded,
                label: profile.isFollowing ? 'Seguindo' : 'Seguir',
                dark: false,
                outlined: profile.isFollowing,
                loading: isFollowingLoading,
                onPressed: isFollowingLoading ? null : onToggleFollow,
              ),
            ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.dark = false,
    this.outlined = false,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool dark;
  final bool outlined;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final foreground = outlined ? UrbColors.violetDeep : Colors.white;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: outlined
            ? Colors.white
            : (dark ? const Color(0xFF18222E) : null),
        gradient: outlined || dark ? null : UrbGradients.primary,
        borderRadius: BorderRadius.circular(22),
        border: outlined
            ? Border.all(color: const Color(0xFFD9D3F0), width: 1.5)
            : null,
        boxShadow: outlined
            ? null
            : [
                BoxShadow(
                  color: (dark ? const Color(0xFF18222E) : UrbColors.violet)
                      .withValues(alpha: 0.3),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                loading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: foreground,
                        ),
                      )
                    : Icon(icon, size: 17, color: foreground),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: UrbText.body(
                    size: 15,
                    weight: FontWeight.w700,
                    color: foreground,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// Números, nível, insígnias e reportes
// ──────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.profile});

  final UserProfileData profile;

  @override
  Widget build(BuildContext context) {
    Widget stat(
      int value,
      String singular,
      String plural,
      Color color,
    ) => Expanded(
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: UrbMotion.of(context, const Duration(milliseconds: 700)),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Text(
              '${v.round()}',
              style: UrbText.display(
                size: 24,
                weight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value == 1 ? singular : plural,
            textAlign: TextAlign.center,
            style: UrbText.body(size: 12, weight: FontWeight.w600, height: 1.3),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F1A1A2E),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            stat(
              profile.posts.length,
              'Reporte',
              'Reportes',
              UrbColors.violetDeep,
            ),
            const VerticalDivider(width: 1, color: UrbColors.border),
            stat(
              profile.likesReceived,
              'Apoio recebido',
              'Apoios recebidos',
              const Color(0xFFC2185B),
            ),
            const VerticalDivider(width: 1, color: UrbColors.border),
            stat(
              profile.followersCount,
              'Seguidor',
              'Seguidores',
              const Color(0xFF1565A8),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.profile});

  final UserProfileData profile;

  @override
  Widget build(BuildContext context) {
    final LevelProgress progress = profile.levelProgress;
    final subtitle = progress.isMaxLevel
        ? 'Você chegou ao nível máximo!'
        : 'Faltam ${progress.xpToNextLevel} XP para ${progress.nextLevelTitle ?? 'o próximo nível'}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF18222E),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4018222E),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: UrbGradients.gamification,
                ),
                child: Container(
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFF18222E),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${progress.level}',
                    style: UrbText.display(
                      size: 24,
                      weight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NÍVEL ${progress.level}',
                      style: UrbText.body(
                        size: 12,
                        weight: FontWeight.w700,
                        color: const Color(0xFFB9C4D4),
                        height: 1.3,
                      ).copyWith(letterSpacing: 1.2),
                    ),
                    Text(
                      progress.title.isEmpty
                          ? 'Progresso de XP'
                          : progress.title,
                      style: UrbText.display(
                        size: 22,
                        weight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // A barra enche do zero até o XP atual ao abrir.
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                Container(height: 12, color: const Color(0xFF2C3848)),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress.fraction),
                  duration: UrbMotion.of(
                    context,
                    const Duration(milliseconds: 900),
                  ),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => FractionallySizedBox(
                    widthFactor: value,
                    child: Container(
                      height: 12,
                      decoration: const BoxDecoration(
                        gradient: UrbGradients.gamification,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                progress.isMaxLevel
                    ? '${profile.currentXp} XP'
                    : '${progress.xpIntoLevel} / ${progress.xpForLevel} XP',
                style: UrbText.body(
                  size: 13,
                  weight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.3,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  subtitle,
                  textAlign: TextAlign.right,
                  style: UrbText.body(
                    size: 13,
                    color: const Color(0xFFB9C4D4),
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// As 5 insígnias do UrbApp: coloridas as conquistadas, cinza com cadeado as bloqueadas.
class _BadgesRow extends StatelessWidget {
  const _BadgesRow({required this.profile});

  final UserProfileData profile;

  static const _tiers = [
    ('bronze', 'Bronze'),
    ('silver', 'Prata'),
    ('gold', 'Ouro'),
    ('diamond', 'Diamante'),
    ('ametist', 'Safira'),
  ];

  @override
  Widget build(BuildContext context) {
    final earned = <String, ProfileBadge>{};
    for (final badge in profile.badges) {
      final path = _badgeAssetPath(badge);
      if (path == null) continue;
      for (final tier in _tiers) {
        if (path.contains('badge-${tier.$1}'))
          earned.putIfAbsent(tier.$1, () => badge);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Insígnias',
                style: UrbText.display(size: 20, weight: FontWeight.w700),
              ),
            ),
            UrbCountBadge(label: '${earned.length} de ${_tiers.length}'),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            for (var i = 0; i < _tiers.length; i++)
              Expanded(
                child: Column(
                  children: [
                    Tooltip(
                      message: earned.containsKey(_tiers[i].$1)
                          ? earned[_tiers[i].$1]!.name
                          : '${_tiers[i].$2}: desbloqueia no nível ${i + 1}',
                      child: SizedBox(
                        width: 58,
                        height: 58,
                        child: earned.containsKey(_tiers[i].$1)
                            ? _BadgeMedal(
                                badge: earned[_tiers[i].$1]!,
                                size: 58,
                              )
                            : Stack(
                                alignment: Alignment.center,
                                children: [
                                  Opacity(
                                    opacity: 0.35,
                                    child: ColorFiltered(
                                      colorFilter: const ColorFilter.matrix([
                                        0.2126,
                                        0.7152,
                                        0.0722,
                                        0,
                                        0,
                                        0.2126,
                                        0.7152,
                                        0.0722,
                                        0,
                                        0,
                                        0.2126,
                                        0.7152,
                                        0.0722,
                                        0,
                                        0,
                                        0,
                                        0,
                                        0,
                                        1,
                                        0,
                                      ]),
                                      child: Image.asset(
                                        'assets/images/badges/badge-${_tiers[i].$1}.png',
                                        width: 58,
                                        height: 58,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Color(0x26000000),
                                          blurRadius: 6,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.lock_rounded,
                                      size: 13,
                                      color: UrbColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      earned.containsKey(_tiers[i].$1)
                          ? _tiers[i].$2
                          : 'Nível ${i + 1}',
                      style: UrbText.body(
                        size: 12,
                        weight: FontWeight.w700,
                        color: earned.containsKey(_tiers[i].$1)
                            ? UrbColors.ink
                            : UrbColors.textMuted,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PostsSection extends StatelessWidget {
  const _PostsSection({required this.posts, required this.isOwnProfile});

  final List<FeedPost> posts;
  final bool isOwnProfile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isOwnProfile ? 'Meus reportes' : 'Reportes',
                style: UrbText.display(size: 20, weight: FontWeight.w700),
              ),
            ),
            UrbCountBadge(label: '${posts.length}'),
          ],
        ),
        const SizedBox(height: 14),
        if (posts.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              isOwnProfile
                  ? 'Você ainda não publicou reportes. Toque no + para criar o primeiro!'
                  : 'Nenhum reporte publicado para exibir.',
              textAlign: TextAlign.center,
              style: UrbText.body(size: 14, height: 1.45),
            ),
          )
        else
          for (var i = 0; i < posts.length; i++) ...[
            if (i < 6)
              FadeSlideIn(
                delay: Duration(milliseconds: 220 + 50 * i),
                child: _ProfilePostCard(
                  post: posts[i],
                  isOwnProfile: isOwnProfile,
                ),
              )
            else
              _ProfilePostCard(post: posts[i], isOwnProfile: isOwnProfile),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _ProfilePostCard extends StatelessWidget {
  const _ProfilePostCard({required this.post, required this.isOwnProfile});

  final FeedPost post;
  final bool isOwnProfile;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: () => PostDetailScreen.open(context, post),
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              UrbPostImage(
                url: post.primaryImageUrl,
                height: 84,
                width: 84,
                radius: 16,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            post.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: UrbText.display(
                              size: 17,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        UrbStatusChip(status: post.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${post.categoryName} · ${post.cityName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.body(size: 13, height: 1.3),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(
                          Icons.favorite_rounded,
                          size: 15,
                          color: UrbColors.heart,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${post.supportsCount}',
                          style: UrbText.body(
                            size: 13,
                            weight: FontWeight.w700,
                            color: const Color(0xFF374151),
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 15,
                          color: UrbColors.commentBlue,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${post.commentsCount}',
                          style: UrbText.body(
                            size: 13,
                            weight: FontWeight.w700,
                            color: const Color(0xFF374151),
                            height: 1.2,
                          ),
                        ),
                        if (isOwnProfile && post.isAnonymous) ...[
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF4E5),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.visibility_off_outlined,
                                  size: 12,
                                  color: Color(0xFF9A5B00),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Anônimo',
                                  style: UrbText.body(
                                    size: 11,
                                    weight: FontWeight.w700,
                                    color: const Color(0xFF9A5B00),
                                    height: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.avatarUrl,
    required this.label,
    this.size = 118,
  });

  final String? avatarUrl;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final parts = label
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .take(2)
        .toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
        ? parts.first.substring(0, 1).toUpperCase()
        : '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFEDE7FB), Color(0xFFDDF1FD)],
        ),
      ),
      child: Text(
        initials,
        style: UrbText.display(
          size: size * 0.38,
          weight: FontWeight.w700,
          color: UrbColors.violetDeep,
        ),
      ),
    );
    final url = avatarUrl;
    if (url == null || url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class _SettingsOption extends StatelessWidget {
  const _SettingsOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color = UrbColors.violetDeep,
    this.background = UrbColors.lavender,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: UrbColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: UrbText.body(
                        size: 15,
                        weight: FontWeight.w700,
                        color: UrbColors.ink,
                        height: 1.3,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: UrbText.body(
                        size: 12,
                        color: UrbColors.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: UrbColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgePalette {
  const _BadgePalette({
    required this.base,
    required this.dark,
    required this.light,
  });

  final Color base;
  final Color dark;
  final Color light;
}

_BadgePalette _badgePalette(ProfileBadge badge) {
  final key = '${badge.slug} ${badge.name} ${badge.icon ?? ''}'.toLowerCase();

  if (key.contains('diamond') || key.contains('diamante')) {
    return const _BadgePalette(
      base: Color(0xFFBFE6FF),
      dark: Color(0xFF6D90B8),
      light: Color(0xFFF7FCFF),
    );
  }

  if (key.contains('sapphire') || key.contains('safira')) {
    return const _BadgePalette(
      base: Color(0xFF6D4DFF),
      dark: Color(0xFF2F1363),
      light: Color(0xFFD9C8FF),
    );
  }

  if (key.contains('gold') || key.contains('ouro')) {
    return const _BadgePalette(
      base: Color(0xFFF1C40F),
      dark: Color(0xFFB9770E),
      light: Color(0xFFFFF3B0),
    );
  }

  if (key.contains('silver') || key.contains('prata')) {
    return const _BadgePalette(
      base: Color(0xFFC0C7D1),
      dark: Color(0xFF6B7280),
      light: Color(0xFFF3F4F6),
    );
  }

  return const _BadgePalette(
    base: Color(0xFFCD7F32),
    dark: Color(0xFF7C3A10),
    light: Color(0xFFFAD7A0),
  );
}

String? _badgeAssetPath(ProfileBadge badge) {
  final icon = badge.icon?.trim();
  if (icon != null && icon.startsWith('assets/')) {
    return icon;
  }

  final key = '${badge.slug} ${badge.name} ${badge.icon ?? ''}'.toLowerCase();

  if (key.contains('diamond') || key.contains('diamante')) {
    return 'assets/images/badges/badge-diamond.png';
  }

  if (key.contains('sapphire') ||
      key.contains('safira') ||
      key.contains('ametist') ||
      key.contains('amethyst')) {
    return 'assets/images/badges/badge-ametist.png';
  }

  if (key.contains('gold') || key.contains('ouro')) {
    return 'assets/images/badges/badge-gold.png';
  }

  if (key.contains('silver') || key.contains('prata')) {
    return 'assets/images/badges/badge-silver.png';
  }

  if (key.contains('bronze')) {
    return 'assets/images/badges/badge-bronze.png';
  }

  return null;
}

class _BadgeMedal extends StatelessWidget {
  const _BadgeMedal({required this.badge, required this.size});

  final ProfileBadge badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = _badgePalette(badge);
    final assetPath = _badgeAssetPath(badge);

    if (assetPath != null) {
      return SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _buildFallbackMedal(palette),
        ),
      );
    }

    return _buildFallbackMedal(palette);
  }

  Widget _buildFallbackMedal(_BadgePalette palette) {
    return SizedBox(
      width: size,
      height: size,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.light, palette.base, palette.dark],
          ),
          boxShadow: [
            BoxShadow(
              color: palette.dark.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.65),
            width: 2.4,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size * 0.68,
              height: size * 0.68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
            ),
            Icon(
              Icons.location_city_rounded,
              size: size * 0.34,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditProfileResult {
  const _EditProfileResult({
    required this.fullName,
    required this.username,
    required this.biography,
    required this.cityId,
    required this.featuredBadgeId,
    this.avatarFile,
  });

  final String fullName;
  final String username;
  final String biography;
  final int? cityId;
  final int? featuredBadgeId;
  final PlatformFile? avatarFile;
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({
    required this.profile,
    required this.cities,
    required this.badgesOptions,
  });

  final UserProfileData profile;
  final List<ProfileCityOption> cities;
  final List<ProfileBadge> badgesOptions;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _fullNameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _biographyController;
  int? _selectedCityId;
  int? _selectedBadgeId;
  PlatformFile? _avatarFile;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(text: widget.profile.fullName);
    _usernameController = TextEditingController(text: widget.profile.username);
    _biographyController = TextEditingController(
      text: widget.profile.biography ?? '',
    );
    _selectedCityId = widget.profile.cityId;
    _selectedBadgeId = widget.profile.featuredBadge?.id;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _biographyController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    const maxBytes = 5 * 1024 * 1024; // 5 MB
    if (file.size > maxBytes) {
      if (mounted)
        showUrbSnack(context, 'A imagem deve ter no máximo 5 MB.', error: true);
      return;
    }

    if (!mounted) return;
    setState(() => _avatarFile = file);
  }

  void _save() {
    Navigator.of(context).pop(
      _EditProfileResult(
        fullName: _fullNameController.text.trim(),
        username: _usernameController.text.trim(),
        biography: _biographyController.text.trim(),
        cityId: _selectedCityId,
        featuredBadgeId: _selectedBadgeId,
        avatarFile: _avatarFile,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarBytes = _avatarFile?.bytes;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UrbDialogHeader(
              title: 'Personalizar perfil',
              subtitle: 'Como você aparece para a comunidade.',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: UrbGradients.gamification,
                    ),
                    child: ClipOval(
                      child: avatarBytes != null
                          ? Image.memory(avatarBytes, fit: BoxFit.cover)
                          : _ProfileAvatar(
                              avatarUrl: widget.profile.avatarUrl,
                              label: widget.profile.fullName,
                              size: 88,
                            ),
                    ),
                  ),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Material(
                      color: UrbColors.violet,
                      shape: const CircleBorder(
                        side: BorderSide(color: Colors.white, width: 3),
                      ),
                      child: InkWell(
                        onTap: _pickAvatar,
                        customBorder: const CircleBorder(),
                        child: const SizedBox(
                          width: 38,
                          height: 38,
                          child: Icon(
                            Icons.photo_camera_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _pickAvatar,
              child: Text(
                _avatarFile == null ? 'Mudar foto' : _avatarFile!.name,
                style: UrbText.body(
                  size: 14,
                  weight: FontWeight.w700,
                  color: UrbColors.violetDeep,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 10),
            UrbTextField(
              label: 'Nome social',
              controller: _fullNameController,
              icon: Icons.badge_outlined,
              hintText: 'Seu nome',
            ),
            const SizedBox(height: 18),
            UrbTextField(
              label: 'Nome de usuário',
              controller: _usernameController,
              icon: Icons.alternate_email_rounded,
              hintText: 'seu.usuario',
            ),
            const SizedBox(height: 18),
            Text(
              'Biografia',
              style: UrbText.body(
                size: 13,
                weight: FontWeight.w700,
                color: const Color(0xFF374151),
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _biographyController,
              minLines: 2,
              maxLines: 4,
              maxLength: 160,
              textAlign: TextAlign.center,
              style: UrbText.body(size: 15, color: UrbColors.ink, height: 1.4),
              decoration: urbInputDecoration(
                hintText: 'Conte um pouco sobre você e seu bairro',
              ).copyWith(contentPadding: const EdgeInsets.all(16)),
            ),
            const SizedBox(height: 10),
            Text(
              'Cidade',
              style: UrbText.body(
                size: 13,
                weight: FontWeight.w700,
                color: const Color(0xFF374151),
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int?>(
              initialValue: _selectedCityId,
              isExpanded: true,
              alignment: Alignment.center,
              borderRadius: BorderRadius.circular(16),
              style: UrbText.body(size: 15, color: UrbColors.ink, height: 1.3),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  alignment: Alignment.center,
                  child: Text('Sem cidade'),
                ),
                for (final city in widget.cities)
                  DropdownMenuItem<int?>(
                    value: city.id,
                    alignment: Alignment.center,
                    child: Text(city.name),
                  ),
              ],
              onChanged: (value) => setState(() => _selectedCityId = value),
              decoration: urbInputDecoration(
                icon: Icons.location_on_outlined,
                suffix: const SizedBox(width: 0),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Insígnia em destaque',
              style: UrbText.body(
                size: 13,
                weight: FontWeight.w700,
                color: const Color(0xFF374151),
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            if (widget.badgesOptions.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: UrbColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Você ainda não conquistou insígnias. Suba de nível para desbloquear!',
                  textAlign: TextAlign.center,
                  style: UrbText.body(size: 13, height: 1.4),
                ),
              )
            else
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final badge in widget.badgesOptions)
                    _BadgeChoice(
                      badge: badge,
                      selected: _selectedBadgeId == badge.id,
                      onTap: () => setState(() {
                        _selectedBadgeId = _selectedBadgeId == badge.id
                            ? null
                            : badge.id;
                      }),
                    ),
                ],
              ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: UrbSecondaryButton(
                    label: 'Cancelar',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: UrbPrimaryButton(label: 'Salvar', onPressed: _save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeChoice extends StatelessWidget {
  const _BadgeChoice({
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  final ProfileBadge badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: badge.name,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: UrbMotion.of(context, UrbMotion.fast),
          width: 88,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? UrbColors.lavender : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? UrbColors.violet : UrbColors.border,
              width: selected ? 2 : 1.5,
            ),
          ),
          child: Column(
            children: [
              _BadgeMedal(badge: badge, size: 48),
              const SizedBox(height: 6),
              Text(
                badge.name.replaceFirst('UrbApp ', ''),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: UrbText.body(
                  size: 12,
                  weight: FontWeight.w700,
                  color: selected ? UrbColors.violetDeep : UrbColors.ink,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
