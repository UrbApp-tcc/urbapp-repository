import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/feed_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_formatter.dart';
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
      final cities = _isOwnProfile ? await _profileService.fetchCities() : const <ProfileCityOption>[];

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error)),
          backgroundColor: AppColors.error,
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error)),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isFollowingLoading = false);
      }
    }
  }

  Future<void> _openEditProfileSheet() async {
    final profile = _profile;
    if (profile == null || !_isOwnProfile) return;

    final result = await showModalBottomSheet<_EditProfileResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfil atualizado com sucesso.'),
          backgroundColor: AppColors.resolved,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error)),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _openSettingsSheet() async {
    if (!_isOwnProfile) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Configurações',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Editar perfil'),
                onTap: () {
                  Navigator.of(context).pop();
                  _openEditProfileSheet();
                },
              ),
              if (widget.currentUserId != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_balance_outlined),
                  title: const Text('Perfis institucionais'),
                  subtitle: const Text('Criar ou gerenciar secretaria/prefeitura'),
                  onTap: () {
                    Navigator.of(context).pop();
                    AgencyProfilesScreen.open(
                      context,
                      currentUserId: widget.currentUserId!,
                    );
                  },
                ),
              if (widget.onSignOut != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout_rounded, color: AppColors.error),
                  title: const Text('Sair da conta'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await widget.onSignOut!.call();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : profile == null
                ? const Center(child: Text('Não foi possível carregar o perfil.'))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 132),
                    children: [
                      _ProfileTopBar(
                        isOwnProfile: _isOwnProfile,
                        onOpenSettings: _openSettingsSheet,
                        onBack: Navigator.of(context).canPop()
                            ? () => Navigator.of(context).pop()
                            : null,
                      ),
                      const SizedBox(height: 24),
                      _ProfileHeader(
                        profile: profile,
                        isOwnProfile: _isOwnProfile,
                        isSaving: _isSaving,
                        isFollowingLoading: _isFollowingLoading,
                        onEditProfile: _openEditProfileSheet,
                        onToggleFollow: _toggleFollow,
                      ),
                      const SizedBox(height: 22),
                      _StatsGrid(profile: profile),
                      const SizedBox(height: 20),
                      _XpCard(profile: profile),
                      const SizedBox(height: 24),
                      _ProfilePostsSection(
                        posts: profile.posts,
                        isOwnProfile: _isOwnProfile,
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _ProfileTopBar extends StatelessWidget {
  const _ProfileTopBar({
    required this.isOwnProfile,
    required this.onOpenSettings,
    this.onBack,
  });

  final bool isOwnProfile;
  final VoidCallback onOpenSettings;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null)
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          )
        else
          const SizedBox(width: 48),
        const Spacer(),
        const Text(
          'Perfil',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        if (isOwnProfile)
          IconButton(
            onPressed: onOpenSettings,
            icon: const Icon(Icons.tune_rounded),
          )
        else
          const SizedBox(width: 48),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
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

  ButtonStyle get _headerButtonStyle => ElevatedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      );

  @override
  Widget build(BuildContext context) {
    final badge = profile.featuredBadge;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _ProfileAvatar(
              avatarUrl: profile.avatarUrl,
              label: profile.fullName,
            ),
            if (badge != null) ...[
              const SizedBox(width: 18),
              _ProfileFeaturedBadge(badge: badge),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Text(
          profile.fullName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '@${profile.username}',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if ((profile.cityName ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            profile.cityName!,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if ((profile.biography ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              profile.biography!.trim(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isOwnProfile)
              ElevatedButton.icon(
                onPressed: isSaving ? null : onEditProfile,
                style: _headerButtonStyle,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(isSaving ? 'Salvando...' : 'Personalizar'),
              )
            else
              ElevatedButton.icon(
                onPressed: isFollowingLoading ? null : onToggleFollow,
                style: _headerButtonStyle,
                icon: Icon(
                  profile.isFollowing ? Icons.person_remove_alt_1_rounded : Icons.person_add_alt_1,
                  size: 18,
                ),
                label: Text(
                  isFollowingLoading
                      ? 'Aguarde'
                      : profile.isFollowing
                          ? 'Seguindo'
                          : 'Seguir',
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.avatarUrl,
    required this.label,
  });

  final String? avatarUrl;
  final String label;

  @override
  Widget build(BuildContext context) {
    final initials = label
        .trim()
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .take(2)
        .map((item) => item[0])
        .join()
        .toUpperCase();

    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 42,
        backgroundColor: AppColors.primaryLight,
        child: ClipOval(
          child: Image.network(
            avatarUrl!,
            width: 84,
            height: 84,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _fallback(initials),
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 42,
      backgroundColor: AppColors.primaryLight,
      child: _fallback(initials),
    );
  }

  Widget _fallback(String initials) {
    return Text(
      initials.isEmpty ? 'U' : initials,
      style: const TextStyle(
        color: AppColors.primaryDark,
        fontSize: 26,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _ProfileFeaturedBadge extends StatelessWidget {
  const _ProfileFeaturedBadge({required this.badge});

  final ProfileBadge badge;

  @override
  Widget build(BuildContext context) {
    return _BadgeMedal(
      badge: badge,
      size: 68,
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
  const _BadgeMedal({
    required this.badge,
    required this.size,
  });

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
            colors: [
              palette.light,
              palette.base,
              palette.dark,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: palette.dark.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(color: Colors.white.withValues(alpha: 0.65), width: 2.4),
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

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.profile});

  final UserProfileData profile;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 3,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.92,
      children: [
        _StatCard(label: 'Seguidores', value: '${profile.followersCount}'),
        _StatCard(label: 'Apoios recebidos', value: '${profile.likesReceived}'),
        _StatCard(label: 'Nível', value: '${profile.currentLevel}'),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _XpCard extends StatelessWidget {
  const _XpCard({required this.profile});

  final UserProfileData profile;

  @override
  Widget build(BuildContext context) {
    final progress = (profile.xpIntoCurrentLevel / 1000).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Progresso de XP',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Faltam ${profile.xpToNextLevel} XP para o próximo nível',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${profile.xpIntoCurrentLevel}/1000 XP neste nível',
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _BadgesSection extends StatelessWidget {
  const _BadgesSection({
    required this.badges,
    required this.featuredBadge,
    required this.showAll,
    required this.onToggleShowAll,
  });

  final List<ProfileBadge> badges;
  final ProfileBadge? featuredBadge;
  final bool showAll;
  final VoidCallback onToggleShowAll;

  @override
  Widget build(BuildContext context) {
    final visibleBadges = showAll ? badges : badges.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Conquistas',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (featuredBadge != null) ...[
            const SizedBox(height: 12),
            _FeaturedBadgeCard(badge: featuredBadge!),
          ],
          const SizedBox(height: 14),
          if (badges.isEmpty)
            const Text(
              'Nenhuma insígnia conquistada ainda.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            )
          else ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: visibleBadges
                  .map((badge) => _BadgeChip(badge: badge))
                  .toList(),
            ),
            if (badges.length > 3) ...[
              const SizedBox(height: 14),
              TextButton(
                onPressed: onToggleShowAll,
                child: Text(showAll ? 'Ver menos' : 'Ver todas (${badges.length})'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ignore: unused_element
class _FeaturedBadgeCard extends StatelessWidget {
  const _FeaturedBadgeCard({required this.badge});

  final ProfileBadge badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Insígnia em destaque',
            style: TextStyle(
              color: AppColors.textHint,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            badge.name,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            badge.description,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.badge});

  final ProfileBadge badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            badge.name,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 120,
            child: Text(
              badge.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _ProfileAchievementsSection extends StatelessWidget {
  const _ProfileAchievementsSection({
    required this.badges,
    required this.featuredBadge,
    required this.showAll,
    required this.onToggleShowAll,
  });

  static const ProfileBadge _bronzePreviewBadge = ProfileBadge(
    id: -1,
    name: 'UrbApp Bronze',
    slug: 'urbapp-bronze-preview',
    description: 'Previa visual da insignia bronze para validar como ela aparece no perfil.',
    icon: 'assets/images/badges/badge-bronze.png',
  );

  final List<ProfileBadge> badges;
  final ProfileBadge? featuredBadge;
  final bool showAll;
  final VoidCallback onToggleShowAll;

  @override
  Widget build(BuildContext context) {
    final previewBadge = badges.isEmpty && featuredBadge == null ? _bronzePreviewBadge : null;
    final visibleBadges = showAll ? badges : badges.take(3).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Conquistas',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (featuredBadge != null) ...[
            const SizedBox(height: 12),
            _AchievementFeaturedBadgeCard(badge: featuredBadge!),
          ] else if (previewBadge != null) ...[
            const SizedBox(height: 12),
            _AchievementFeaturedBadgeCard(
              badge: previewBadge,
              eyebrow: 'Previa de insignia',
            ),
          ],
          const SizedBox(height: 14),
          if (badges.isEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Nenhuma insignia conquistada ainda.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'A imagem bronze acima e so um teste visual do layout.',
                  style: TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            )
          else ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: visibleBadges
                  .map((badge) => _AchievementBadgeChip(badge: badge))
                  .toList(),
            ),
            if (badges.length > 3) ...[
              const SizedBox(height: 14),
              TextButton(
                onPressed: onToggleShowAll,
                child: Text(showAll ? 'Ver menos' : 'Ver todas (${badges.length})'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ignore: unused_element
class _AchievementFeaturedBadgeCard extends StatelessWidget {
  const _AchievementFeaturedBadgeCard({
    required this.badge,
    this.eyebrow = 'Insignia em destaque',
  });

  final ProfileBadge badge;
  final String eyebrow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AchievementBadgeArtwork(
            icon: badge.icon,
            size: 74,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  badge.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  badge.description,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _AchievementBadgeChip extends StatelessWidget {
  const _AchievementBadgeChip({required this.badge});

  final ProfileBadge badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AchievementBadgeArtwork(
            icon: badge.icon,
            size: 56,
          ),
          const SizedBox(height: 10),
          Text(
            badge.name,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            badge.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _AchievementBadgeArtwork extends StatelessWidget {
  const _AchievementBadgeArtwork({
    required this.icon,
    required this.size,
  });

  final String? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFF3D1AE)),
    );

    if (icon != null && icon!.startsWith('assets/')) {
      return Container(
        width: size,
        height: size,
        decoration: decoration,
        padding: const EdgeInsets.all(8),
        child: Image.asset(icon!, fit: BoxFit.contain),
      );
    }

    if (icon != null && icon!.startsWith('http')) {
      return Container(
        width: size,
        height: size,
        decoration: decoration,
        padding: const EdgeInsets.all(8),
        child: Image.network(
          icon!,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _fallback(decoration),
        ),
      );
    }

    return _fallback(decoration);
  }

  Widget _fallback(BoxDecoration decoration) {
    return Container(
      width: size,
      height: size,
      decoration: decoration,
      child: const Icon(
        Icons.workspace_premium_rounded,
        color: Color(0xFFB66A1E),
        size: 34,
      ),
    );
  }
}

class _ProfilePostsSection extends StatelessWidget {
  const _ProfilePostsSection({
    required this.posts,
    required this.isOwnProfile,
  });

  final List<FeedPost> posts;
  final bool isOwnProfile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Posts',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        if (posts.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text(
              'Nenhum reporte publicado para exibir.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          )
        else
          ...posts.map(
            (post) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ProfilePostCard(
                post: post,
                isOwnProfile: isOwnProfile,
              ),
            ),
          ),
      ],
    );
  }
}

class _ProfilePostCard extends StatelessWidget {
  const _ProfilePostCard({
    required this.post,
    required this.isOwnProfile,
  });

  final FeedPost post;
  final bool isOwnProfile;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => PostDetailScreen.open(context, post),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: post.primaryImageUrl != null && post.primaryImageUrl!.isNotEmpty
                      ? Image.network(
                          post.primaryImageUrl!,
                          fit: BoxFit.cover,
                        )
                      : const ColoredBox(
                          color: AppColors.divider,
                          child: Icon(Icons.image_outlined, color: AppColors.textHint),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${post.categoryName} · ${post.cityName}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    if (isOwnProfile && post.isAnonymous) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4E5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Post anônimo - só você vê no seu perfil',
                          style: TextStyle(
                            color: Color(0xFF9A5B00),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.favorite_border_rounded, size: 16, color: AppColors.textHint),
                        const SizedBox(width: 6),
                        Text(
                          '${post.supportsCount}',
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Icon(Icons.mode_comment_outlined, size: 16, color: AppColors.textHint),
                        const SizedBox(width: 6),
                        Text(
                          '${post.commentsCount}',
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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

  ProfileBadge? get _selectedBadge {
    for (final badge in widget.badgesOptions) {
      if (badge.id == _selectedBadgeId) return badge;
    }
    return null;
  }

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
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    const maxBytes = 5 * 1024 * 1024; // 5 MB
    if ((file.size) > maxBytes) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('A imagem deve ter no máximo 5 MB.'),
          backgroundColor: AppColors.error,
        ),
      );
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
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Personalizar perfil',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickAvatar,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(_avatarFile == null ? 'Mudar foto' : _avatarFile!.name),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fullNameController,
              decoration: const InputDecoration(
                labelText: 'Nome social',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Nome de usuário',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _biographyController,
              maxLength: 240,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Biografia',
                hintText: 'Conte um pouco sobre sua participação na cidade',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _selectedCityId,
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Sem cidade informada'),
                ),
                ...widget.cities.map(
                  (city) => DropdownMenuItem<int?>(
                    value: city.id,
                    child: Text(city.name),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _selectedCityId = value),
              decoration: const InputDecoration(
                labelText: 'Cidade',
              ),
            ),
            const SizedBox(height: 12),
            if (_selectedBadge != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    _BadgeMedal(
                      badge: _selectedBadge!,
                      size: 54,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Insígnia selecionada',
                            style: TextStyle(
                              color: AppColors.textHint,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectedBadge!.name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<int?>(
              initialValue: _selectedBadgeId,
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Sem insígnia em destaque'),
                ),
                ...widget.badgesOptions.map(
                  (badge) => DropdownMenuItem<int?>(
                    value: badge.id,
                    child: Text(badge.name),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _selectedBadgeId = value),
              decoration: const InputDecoration(
                labelText: 'Insígnia em destaque',
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _save,
              child: const Text('Salvar alterações'),
            ),
          ],
        ),
      ),
    );
  }
}
