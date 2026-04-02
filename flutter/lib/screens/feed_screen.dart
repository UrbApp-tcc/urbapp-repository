import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/feed_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import 'create_post_screen.dart';

enum _FeedCollection {
  recent,
  progress,
  resolved,
}

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _feedService = FeedService();
  final _authService = AuthService();

  List<FeedPost> _posts = const [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String _searchQuery = '';
  String _selectedCategory = 'Todas';
  _FeedCollection _selectedCollection = _FeedCollection.recent;

  @override
  void initState() {
    super.initState();
    _loadFeed();
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

    return _posts.where((post) {
      final matchesCategory = _selectedCategory == 'Todas' ||
          post.categoryName.toLowerCase() == _selectedCategory.toLowerCase();
      final matchesCollection = _matchesCollection(post);
      final haystack = [
        post.title,
        post.description,
        post.cityName,
        post.categoryName,
        post.authorDisplayName,
        post.agencyName ?? '',
      ].join(' ').toLowerCase();
      final matchesQuery = query.isEmpty || haystack.contains(query);

      return matchesCategory && matchesCollection && matchesQuery;
    }).toList();
  }

  List<String> get _categoryOptions {
    final categories = _posts
        .map((post) => post.categoryName.trim())
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return ['Todas', ...categories.take(8)];
  }

  bool _matchesCollection(FeedPost post) {
    switch (_selectedCollection) {
      case _FeedCollection.recent:
        return true;
      case _FeedCollection.progress:
        return post.status == 'open' ||
            post.status == 'in_analysis' ||
            post.status == 'in_progress';
      case _FeedCollection.resolved:
        return post.status == 'completed' || post.status == 'closed';
    }
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }

  String _formatRelativeDate(DateTime value) {
    final difference = DateTime.now().difference(value.toLocal());

    if (difference.inMinutes < 1) return 'Agora';
    if (difference.inHours < 1) return '${difference.inMinutes} min';
    if (difference.inDays < 1) return '${difference.inHours} h';
    if (difference.inDays < 7) return '${difference.inDays} d';
    return _formatDate(value);
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

  Color _statusBackgroundColor(String status) {
    return _statusColor(status).withValues(alpha: 0.12);
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
    return 'Comunidade UrbApp';
  }

  String _avatarLabel() {
    final value = _displayName().trim();
    if (value.isEmpty) return 'U';

    final words = value.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    final initials = words.take(2).map((word) => word[0]).join();
    return initials.isEmpty ? 'U' : initials.toUpperCase();
  }

  String _primaryCityLabel() {
    if (_posts.isEmpty) return 'Sua cidade';

    final counts = <String, int>{};
    for (final post in _posts) {
      counts.update(post.cityName, (value) => value + 1, ifAbsent: () => 1);
    }

    final ordered = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ordered.first.key;
  }

  int _openPostsCount() {
    return _posts
        .where(
          (post) =>
              post.status == 'open' ||
              post.status == 'in_analysis' ||
              post.status == 'in_progress',
        )
        .length;
  }

  int _resolvedPostsCount() {
    return _posts
        .where(
          (post) => post.status == 'completed' || post.status == 'closed',
        )
        .length;
  }

  String _mostActiveCategory() {
    if (_posts.isEmpty) return 'Sem dados ainda';

    final counts = <String, int>{};
    for (final post in _posts) {
      counts.update(post.categoryName, (value) => value + 1, ifAbsent: () => 1);
    }

    final ordered = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ordered.first.key;
  }

  String _collectionLabel(_FeedCollection collection) {
    switch (collection) {
      case _FeedCollection.recent:
        return 'Mais recentes';
      case _FeedCollection.progress:
        return 'Em andamento';
      case _FeedCollection.resolved:
        return 'Resolvidos';
    }
  }

  @override
  Widget build(BuildContext context) {
    final visiblePosts = _visiblePosts;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreatePost,
        backgroundColor: AppColors.accentPink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo reporte'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadFeed(refreshing: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            children: [
              _buildTopHero(),
              const SizedBox(height: 18),
              _buildSearchBar(),
              const SizedBox(height: 18),
              _buildAroundYouCard(),
              const SizedBox(height: 22),
              _buildCategoryStrip(),
              const SizedBox(height: 18),
              _buildCollectionTabs(),
              const SizedBox(height: 22),
              _buildSectionHeader(visiblePosts.length),
              const SizedBox(height: 16),
              if (_isLoading)
                ...List.generate(
                  3,
                  (index) => Padding(
                    padding: EdgeInsets.only(bottom: index == 2 ? 0 : 18),
                    child: const _FeedCardSkeleton(),
                  ),
                )
              else if (visiblePosts.isEmpty)
                _buildEmptyState()
              else
                ...visiblePosts.asMap().entries.map(
                      (entry) => Padding(
                        padding: EdgeInsets.only(
                          bottom: entry.key == visiblePosts.length - 1 ? 0 : 18,
                        ),
                        child: _FeedPostCard(
                          post: entry.value,
                          statusColor: _statusColor,
                          statusBackgroundColor: _statusBackgroundColor,
                          statusLabel: _statusLabel,
                          formatDate: _formatDate,
                          formatRelativeDate: _formatRelativeDate,
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHero() {
    final email = _authService.currentUser?.email ?? 'Sessao ativa';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF143C72),
            Color(0xFF1E6BB8),
            Color(0xFF40B4F5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.gradientBlue.withValues(alpha: 0.22),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                ),
                alignment: Alignment.center,
                child: const AppLogo(height: 34),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ola, ${_displayName()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Acompanhe ocorrencias da comunidade e publique novos reportes.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: IconButton(
                  onPressed: _signOut,
                  color: Colors.white,
                  tooltip: 'Sair',
                  icon: const Icon(Icons.logout_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _avatarLabel(),
                    style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_posts.length} reportes visiveis no momento',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isRefreshing)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchQuery.isEmpty
              ? const Icon(Icons.tune_rounded)
              : IconButton(
                  onPressed: () => setState(() => _searchQuery = ''),
                  icon: const Icon(Icons.close_rounded),
                ),
          hintText: 'Buscar por titulo, categoria, cidade ou orgao',
        ),
      ),
    );
  }

  Widget _buildAroundYouCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ao seu redor',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Um resumo rapido da movimentacao da comunidade em ${_primaryCityLabel()}.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            height: 170,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFEAF5FF),
                  Color(0xFFF3F8FF),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 18,
                  left: 16,
                  right: 16,
                  bottom: 18,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: AppColors.gradientBlue.withValues(alpha: 0.14),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 30,
                  left: 32,
                  child: _MapGlow(
                    color: AppColors.gradientBlue.withValues(alpha: 0.16),
                    size: 70,
                  ),
                ),
                Positioned(
                  right: 26,
                  top: 42,
                  child: _MapGlow(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    size: 52,
                  ),
                ),
                Positioned(
                  left: 54,
                  bottom: 34,
                  child: _MapGlow(
                    color: AppColors.accentPink.withValues(alpha: 0.12),
                    size: 46,
                  ),
                ),
                Align(
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gradientBlue.withValues(alpha: 0.16),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.place_rounded,
                      color: AppColors.gradientBlue,
                      size: 34,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _InsightMetric(
                  label: 'Em aberto',
                  value: _openPostsCount().toString(),
                  accent: AppColors.pending,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _InsightMetric(
                  label: 'Resolvidos',
                  value: _resolvedPostsCount().toString(),
                  accent: AppColors.resolved,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _InsightMetric(
                  label: 'Categoria em alta',
                  value: _mostActiveCategory(),
                  accent: AppColors.gradientBlue,
                  compactValue: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryStrip() {
    final options = _categoryOptions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Categorias',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: options.map((category) {
              final isSelected = category == _selectedCategory;

              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => setState(() => _selectedCategory = category),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.textPrimary : Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.textPrimary
                            : AppColors.border,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: AppColors.textPrimary.withValues(
                                  alpha: 0.08,
                                ),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _categoryIcon(category),
                          size: 18,
                          color: isSelected
                              ? Colors.white
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          category,
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildCollectionTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _FeedCollection.values.map((collection) {
          final isSelected = collection == _selectedCollection;

          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ChoiceChip(
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedCollection = collection),
              showCheckmark: false,
              selectedColor: AppColors.primaryLight,
              backgroundColor: Colors.white,
              side: BorderSide(
                color: isSelected ? AppColors.primaryDark : AppColors.border,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              label: Text(
                _collectionLabel(collection),
                style: TextStyle(
                  color: isSelected ? AppColors.primaryDark : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionHeader(int count) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Text(
            'Ocorrencias da comunidade',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            '$count itens',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    final isFiltered = _searchQuery.trim().isNotEmpty ||
        _selectedCategory != 'Todas' ||
        _selectedCollection != _FeedCollection.recent;

    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(22),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.forum_outlined,
              color: AppColors.primaryDark,
              size: 34,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isFiltered ? 'Nenhum resultado encontrado' : 'Nenhum reporte ainda',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isFiltered
                ? 'Ajuste os filtros ou a busca para explorar mais publicacoes.'
                : 'Publique o primeiro reporte para iniciar o feed da comunidade.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          if (isFiltered)
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                  _selectedCategory = 'Todas';
                  _selectedCollection = _FeedCollection.recent;
                });
              },
              child: const Text('Limpar filtros'),
            )
          else
            ElevatedButton.icon(
              onPressed: _openCreatePost,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Criar primeiro reporte'),
            ),
        ],
      ),
    );
  }

  IconData _categoryIcon(String category) {
    final normalized = category.toLowerCase();

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

    return Icons.grid_view_rounded;
  }
}

class _FeedPostCard extends StatelessWidget {
  const _FeedPostCard({
    required this.post,
    required this.statusColor,
    required this.statusBackgroundColor,
    required this.statusLabel,
    required this.formatDate,
    required this.formatRelativeDate,
  });

  final FeedPost post;
  final Color Function(String status) statusColor;
  final Color Function(String status) statusBackgroundColor;
  final String Function(String status) statusLabel;
  final String Function(DateTime value) formatDate;
  final String Function(DateTime value) formatRelativeDate;

  @override
  Widget build(BuildContext context) {
    final images = post.images.where((image) => image.publicUrl != null).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (images.isNotEmpty)
            _PostImageGallery(
              images: images,
              status: statusLabel(post.status),
              statusColor: statusColor(post.status),
              statusBackgroundColor: statusBackgroundColor(post.status),
            )
          else
            _PostImageFallback(
              category: post.categoryName,
              status: statusLabel(post.status),
              statusColor: statusColor(post.status),
              statusBackgroundColor: statusBackgroundColor(post.status),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _authorInitials(post.authorDisplayName),
                        style: const TextStyle(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.authorDisplayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${post.cityName}  •  ${formatRelativeDate(post.createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      formatDate(post.createdAt),
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(
                      icon: Icons.category_outlined,
                      label: post.categoryName,
                    ),
                    if (post.agencyName != null && post.agencyName!.trim().isNotEmpty)
                      _InfoChip(
                        icon: Icons.apartment_outlined,
                        label: post.agencyName!,
                      ),
                    if (post.isAnonymous)
                      const _InfoChip(
                        icon: Icons.visibility_off_outlined,
                        label: 'Anonimo',
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  post.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                if (post.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    post.description,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _MetricPill(
                        icon: Icons.favorite_border_rounded,
                        label: '${post.supportsCount} apoios',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricPill(
                        icon: Icons.mode_comment_outlined,
                        label: '${post.commentsCount} comentarios',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricPill(
                        icon: Icons.photo_library_outlined,
                        label: '${post.imageCount} imagens',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8FC),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.place_outlined,
                          color: AppColors.gradientBlue,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Local do reporte',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${post.cityName} • Lat ${post.latitude.toStringAsFixed(4)} • Lon ${post.longitude.toStringAsFixed(4)}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _authorInitials(String value) {
    final parts = value.split(RegExp(r'\s+')).where((item) => item.isNotEmpty);
    final initials = parts.take(2).map((item) => item[0]).join();
    return initials.isEmpty ? 'U' : initials.toUpperCase();
  }
}

class _PostImageGallery extends StatefulWidget {
  const _PostImageGallery({
    required this.images,
    required this.status,
    required this.statusColor,
    required this.statusBackgroundColor,
  });

  final List<FeedImage> images;
  final String status;
  final Color statusColor;
  final Color statusBackgroundColor;

  @override
  State<_PostImageGallery> createState() => _PostImageGalleryState();
}

class _PostImageGalleryState extends State<_PostImageGallery> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 250,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemBuilder: (context, index) {
                final image = widget.images[index];

                return Image.network(
                  image.publicUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: AppColors.primaryLight,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.primaryDark,
                        size: 36,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.18),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.36),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: widget.statusBackgroundColor,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                widget.status,
                style: TextStyle(
                  color: widget.statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (widget.images.length > 1)
            Positioned(
              right: 16,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.38),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_currentPage + 1}/${widget.images.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PostImageFallback extends StatelessWidget {
  const _PostImageFallback({
    required this.category,
    required this.status,
    required this.statusColor,
    required this.statusBackgroundColor,
  });

  final String category;
  final String status;
  final Color statusColor;
  final Color statusBackgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        gradient: const LinearGradient(
          colors: [
            Color(0xFFEAF4FF),
            Color(0xFFF7F4FF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: statusBackgroundColor,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.gradientBlue,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  category,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
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

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.primaryDark),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.primaryDark,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightMetric extends StatelessWidget {
  const _InsightMetric({
    required this.label,
    required this.value,
    required this.accent,
    this.compactValue = false,
  });

  final String label;
  final String value;
  final Color accent;
  final bool compactValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: compactValue ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: compactValue ? AppColors.textPrimary : accent,
              fontSize: compactValue ? 14 : 24,
              height: 1.15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MapGlow extends StatelessWidget {
  const _MapGlow({
    required this.color,
    required this.size,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size),
      ),
    );
  }
}

class _FeedCardSkeleton extends StatelessWidget {
  const _FeedCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        children: [
          Container(
            height: 220,
            decoration: const BoxDecoration(
              color: Color(0xFFEFF3F8),
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: List.generate(
                4,
                (index) => Container(
                  height: index == 2 ? 48 : 14,
                  margin: EdgeInsets.only(bottom: index == 3 ? 0 : 12),
                  decoration: BoxDecoration(
                    color: index == 2
                        ? const Color(0xFFF2F4F8)
                        : const Color(0xFFEFF3F8),
                    borderRadius: BorderRadius.circular(16),
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
