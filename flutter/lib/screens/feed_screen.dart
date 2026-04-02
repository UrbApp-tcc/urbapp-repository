import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/feed_service.dart';
import '../theme/app_theme.dart';
import 'create_post_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _feedService = FeedService();
  final _authService = AuthService();
  final _searchController = TextEditingController();

  List<FeedPost> _posts = const [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFeed({bool refreshing = false}) async {
    if (refreshing) {
      setState(() => _isRefreshing = true);
    } else {
      setState(() => _isLoading = true);
    }

    try {
      final posts = await _feedService.fetchFeed();

      if (!mounted) return;
      setState(() {
        _posts = posts;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _openCreatePost() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const CreatePostScreen(returnToPreviousOnSuccess: true),
      ),
    );

    if (!mounted || created != true) return;
    await _loadFeed(refreshing: true);
  }

  Future<void> _signOut() async {
    try {
      await _authService.signOut();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  List<FeedPost> get _visiblePosts {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _posts;

    return _posts.where((post) {
      final haystack = [
        post.title,
        post.description,
        post.categoryName,
        post.cityName,
        post.authorDisplayName,
        post.agencyName ?? '',
      ].join(' ').toLowerCase();

      return haystack.contains(query);
    }).toList();
  }

  String _displayName() {
    final user = _authService.currentUser;
    final metadata = user?.userMetadata ?? const {};
    final fullName = metadata['full_name']?.toString().trim();
    final username = metadata['username']?.toString().trim();
    final email = user?.email?.trim();

    if (fullName != null && fullName.isNotEmpty) return fullName;
    if (username != null && username.isNotEmpty) return username;
    if (email != null && email.isNotEmpty) return email.split('@').first;
    return 'Usuario UrbApp';
  }

  String _avatarLabel() {
    final words = _displayName().split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    final initials = words.take(2).map((word) => word[0]).join();
    return initials.isEmpty ? 'U' : initials.toUpperCase();
  }

  String _subtitle() {
    if (_posts.isEmpty) return 'Comece a acompanhar a comunidade';

    final city = _posts.first.cityName;
    return '$city • ${_posts.length} reportes no feed';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'open':
        return 'Aberto';
      case 'in_analysis':
        return 'Em analise';
      case 'in_progress':
        return 'Em andamento';
      case 'completed':
        return 'Resolvido';
      case 'closed':
        return 'Fechado';
      case 'expired':
        return 'Expirado';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open':
        return AppColors.pending;
      case 'in_analysis':
      case 'in_progress':
        return AppColors.inProgress;
      case 'completed':
        return AppColors.resolved;
      case 'closed':
      case 'expired':
        return AppColors.textSecondary;
      default:
        return AppColors.primary;
    }
  }

  String _formatRelativeDate(DateTime value) {
    final difference = DateTime.now().difference(value.toLocal());

    if (difference.inMinutes < 1) return 'Agora';
    if (difference.inHours < 1) return '${difference.inMinutes} min';
    if (difference.inDays < 1) return '${difference.inHours} h';
    if (difference.inDays < 7) return '${difference.inDays} d';
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F8),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useFramedLayout = constraints.maxWidth > 520;
            final frameWidth = constraints.maxWidth > 460 ? 390.0 : constraints.maxWidth;

            return Center(
              child: Container(
                width: frameWidth,
                margin: EdgeInsets.symmetric(
                  vertical: useFramedLayout ? 18 : 0,
                  horizontal: useFramedLayout ? 16 : 0,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(useFramedLayout ? 34 : 0),
                  boxShadow: useFramedLayout
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 34,
                            offset: const Offset(0, 18),
                          ),
                        ]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () => _loadFeed(refreshing: true),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                          children: [
                            const SizedBox(height: 6),
                            _buildHeader(),
                            const SizedBox(height: 22),
                            _buildSearchBar(),
                            const SizedBox(height: 26),
                            _buildSectionHeader(),
                            const SizedBox(height: 18),
                            _buildFeedBody(),
                          ],
                        ),
                      ),
                    ),
                    _buildBottomBar(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF1E6BB8), Color(0xFF40B4F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            _avatarLabel(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _displayName(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF17181C),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _subtitle(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFB4B6BC),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _TopActionButton(
          icon: _isRefreshing ? Icons.hourglass_top_rounded : Icons.refresh_rounded,
          onTap: _isRefreshing ? null : () => _loadFeed(refreshing: true),
        ),
        const SizedBox(width: 10),
        _TopActionButton(
          icon: Icons.logout_rounded,
          onTap: _signOut,
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F3F4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          hintText: 'Pesquisar reportes',
          hintStyle: const TextStyle(
            color: Color(0xFFC8C8CC),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFFC8C8CC),
            size: 28,
          ),
          suffixIcon: _searchQuery.isEmpty
              ? const Icon(
                  Icons.menu_rounded,
                  color: Color(0xFFC8C8CC),
                )
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFFB9BBC1),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Reportes Recentes',
            style: TextStyle(
              color: Color(0xFF17181C),
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
        ),
        Text(
          '${_visiblePosts.length} itens',
          style: const TextStyle(
            color: Color(0xFF17181C),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildFeedBody() {
    if (_isLoading) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 22,
          crossAxisSpacing: 18,
          childAspectRatio: 0.66,
        ),
        itemBuilder: (context, index) => const _FeedCardSkeleton(),
      );
    }

    if (_visiblePosts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.forum_outlined,
              size: 34,
              color: Color(0xFF9A9CA3),
            ),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isEmpty ? 'Nenhum reporte ainda' : 'Nenhum resultado encontrado',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF17181C),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isEmpty
                  ? 'Crie o primeiro reporte para começar o feed.'
                  : 'Tente outro termo de busca para encontrar reportes.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF8F929A),
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _visiblePosts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 22,
        crossAxisSpacing: 18,
        childAspectRatio: 0.66,
      ),
      itemBuilder: (context, index) {
        return _FeedGridCard(
          post: _visiblePosts[index],
          statusLabel: _statusLabel,
          statusColor: _statusColor,
          formatRelativeDate: _formatRelativeDate,
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFF0F1F3)),
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: _BottomItem(
              icon: Icons.home_outlined,
              label: 'Feed',
              active: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: GestureDetector(
              onTap: _openCreatePost,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.accentPink,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentPink.withValues(alpha: 0.28),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
          const Expanded(
            child: _BottomItem(
              icon: Icons.edit_note_outlined,
              label: 'Reportar',
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedGridCard extends StatelessWidget {
  const _FeedGridCard({
    required this.post,
    required this.statusLabel,
    required this.statusColor,
    required this.formatRelativeDate,
  });

  final FeedPost post;
  final String Function(String status) statusLabel;
  final Color Function(String status) statusColor;
  final String Function(DateTime value) formatRelativeDate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: post.primaryImageUrl != null && post.primaryImageUrl!.isNotEmpty
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        post.primaryImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _FeedImageFallback(category: post.categoryName);
                        },
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: _StatusBadge(
                          label: statusLabel(post.status),
                          color: statusColor(post.status),
                        ),
                      ),
                    ],
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      _FeedImageFallback(category: post.categoryName),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: _StatusBadge(
                          label: statusLabel(post.status),
                          color: statusColor(post.status),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${post.categoryName} • ${post.cityName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFB8BAC0),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          post.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF17181C),
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(
              Icons.favorite_border_rounded,
              size: 16,
              color: Color(0xFF17181C),
            ),
            const SizedBox(width: 4),
            Text(
              '${post.supportsCount}',
              style: const TextStyle(
                color: Color(0xFF17181C),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              formatRelativeDate(post.createdAt),
              style: const TextStyle(
                color: Color(0xFF17181C),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeedImageFallback extends StatelessWidget {
  const _FeedImageFallback({
    required this.category,
  });

  final String category;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFF3F7FF),
            Color(0xFFF8F5FF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: Icon(
            _categoryIcon(category),
            color: AppColors.gradientBlue,
            size: 28,
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(String value) {
    final normalized = value.toLowerCase();

    if (normalized.contains('luz') || normalized.contains('ilumin')) {
      return Icons.lightbulb_outline_rounded;
    }
    if (normalized.contains('buraco') || normalized.contains('asfalto')) {
      return Icons.construction_rounded;
    }
    if (normalized.contains('lixo')) {
      return Icons.delete_outline_rounded;
    }
    if (normalized.contains('agua') || normalized.contains('esgoto')) {
      return Icons.water_drop_outlined;
    }
    if (normalized.contains('segur')) {
      return Icons.shield_outlined;
    }
    if (normalized.contains('sinal')) {
      return Icons.traffic_outlined;
    }

    return Icons.location_city_outlined;
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TopActionButton extends StatelessWidget {
  const _TopActionButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F8),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          color: const Color(0xFF17181C),
          size: 22,
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.icon,
    required this.label,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF42C7B5) : const Color(0xFFC1C3C9);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _FeedCardSkeleton extends StatelessWidget {
  const _FeedCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F6),
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 10,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F6),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 16,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F6),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 16,
          width: 70,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F6),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}
