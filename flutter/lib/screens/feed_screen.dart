import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/city_service.dart';
import '../services/feed_service.dart';
import '../theme/urbapp_design.dart';
import '../utils/date_formatter.dart';
import '../widgets/city_picker_sheet.dart';
import '../widgets/city_skyline.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/urb_status_chip.dart';
import 'profile_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({
    super.key,
    required this.posts,
    required this.trendingPosts,
    required this.likedPostIds,
    required this.isLoading,
    required this.isRefreshing,
    required this.onOpenPost,
    required this.cities,
    required this.selectedCityId,
    required this.onCityChanged,
    required this.onOpenMap,
    this.onToggleSupport,
    this.awaitingValidationIds = const <int>{},
  });

  final List<FeedPost> posts;
  final List<FeedPost> trendingPosts;
  final Set<int> likedPostIds;
  final bool isLoading;
  final bool isRefreshing;
  final ValueChanged<FeedPost> onOpenPost;
  final List<CityOption> cities;
  final int? selectedCityId;
  final ValueChanged<int?> onCityChanged;
  final VoidCallback onOpenMap;

  /// Dá ou tira o apoio (curtida) de um reporte.
  final ValueChanged<FeedPost>? onToggleSupport;

  /// Reportes aguardando a validação da comunidade.
  final Set<int> awaitingValidationIds;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  CityOption? get _selectedCity {
    final selectedCityId = widget.selectedCityId;
    if (selectedCityId == null) return null;
    return widget.cities.where((city) => city.id == selectedCityId).firstOrNull;
  }

  Future<void> _chooseCity() async {
    final result = await showCityPickerSheet(
      context,
      cities: widget.cities,
      selectedCityId: widget.selectedCityId,
      allowAllCities: true,
    );
    if (result == null || !mounted) return;
    widget.onCityChanged(result.cityId);
  }

  @override
  Widget build(BuildContext context) {
    final cityName = _selectedCity?.name;

    return ColoredBox(
      color: UrbColors.surface,
      child: Column(
        children: [
          _FeedHeader(
            title: cityName == null
                ? 'O que está rolando nas cidades'
                : 'O que está rolando em $cityName',
            cityLabel: cityName ?? 'Todas as cidades',
            onChooseCity: widget.cities.isEmpty ? null : _chooseCity,
            onOpenMap: widget.onOpenMap,
            tabController: _tabController,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _RecentList(
                  posts: widget.posts,
                  likedPostIds: widget.likedPostIds,
                  isLoading: widget.isLoading,
                  onOpenPost: widget.onOpenPost,
                  onToggleSupport: widget.onToggleSupport,
                  awaitingIds: widget.awaitingValidationIds,
                ),
                _TrendingList(
                  posts: widget.trendingPosts,
                  likedPostIds: widget.likedPostIds,
                  isLoading: widget.isLoading,
                  onOpenPost: widget.onOpenPost,
                  onToggleSupport: widget.onToggleSupport,
                  awaitingIds: widget.awaitingValidationIds,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// Topo roxo
// ──────────────────────────────────────────────────────────

class _FeedHeader extends StatelessWidget {
  const _FeedHeader({
    required this.title,
    required this.cityLabel,
    required this.onChooseCity,
    required this.onOpenMap,
    required this.tabController,
  });

  final String title;
  final String cityLabel;
  final VoidCallback? onChooseCity;
  final VoidCallback onOpenMap;
  final TabController tabController;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: UrbColors.hero,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 110,
            child: CitySkyline(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _GlassChip(
                      icon: Icons.location_on_outlined,
                      label: cityLabel,
                      trailing: Icons.expand_more_rounded,
                      onPressed: onChooseCity,
                    ),
                    const Spacer(),
                    _GlassIconButton(
                      icon: Icons.map_outlined,
                      tooltip: 'Abrir mapa da cidade',
                      onPressed: onOpenMap,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: UrbText.display(
                    size: 24,
                    weight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 18),
                _FeedTabs(controller: tabController),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedTabs extends StatelessWidget {
  const _FeedTabs({required this.controller});

  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TabBar(
        controller: controller,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        labelColor: UrbColors.violetDeep,
        unselectedLabelColor: Colors.white,
        labelStyle: UrbText.body(
          size: 14,
          weight: FontWeight.w700,
          height: 1.2,
        ),
        unselectedLabelStyle: UrbText.body(
          size: 14,
          weight: FontWeight.w600,
          height: 1.2,
        ),
        splashBorderRadius: BorderRadius.circular(12),
        tabs: const [
          Tab(text: 'Recentes'),
          Tab(text: 'Em alta'),
        ],
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({
    required this.icon,
    required this.label,
    required this.trailing,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final IconData trailing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: UrbText.body(
                    size: 14,
                    weight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(trailing, color: Colors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
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

// ──────────────────────────────────────────────────────────
// Aba "Recentes": cartões grandes
// ──────────────────────────────────────────────────────────

class _RecentList extends StatelessWidget {
  const _RecentList({
    required this.posts,
    required this.likedPostIds,
    required this.isLoading,
    required this.onOpenPost,
    required this.onToggleSupport,
    required this.awaitingIds,
  });

  final List<FeedPost> posts;
  final Set<int> likedPostIds;
  final bool isLoading;
  final ValueChanged<FeedPost> onOpenPost;
  final ValueChanged<FeedPost>? onToggleSupport;
  final Set<int> awaitingIds;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 132),
        children: const [
          _CardSkeleton(),
          SizedBox(height: 16),
          _CardSkeleton(),
        ],
      );
    }

    if (posts.isEmpty) {
      return const _EmptyState(
        icon: Icons.location_city_rounded,
        title: 'Nenhum reporte publicado ainda',
        text:
            'Use o botão central para criar o primeiro reporte da comunidade.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 132),
      itemCount: posts.length + 1,
      separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 14 : 16),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _SectionTitle(title: 'Últimos reportes', count: posts.length);
        }
        final post = posts[index - 1];
        final card = _PostCard(
          key: ValueKey('card-${post.id}'),
          post: post,
          isLiked: likedPostIds.contains(post.id),
          onOpen: () => onOpenPost(post),
          onToggleSupport: onToggleSupport == null
              ? null
              : () => onToggleSupport!(post),
          awaitingValidation: awaitingIds.contains(post.id),
        );
        // Só os primeiros cartões animam ao abrir, para não pesar.
        return index <= 4
            ? FadeSlideIn(
                delay: Duration(milliseconds: 60 * (index - 1)),
                child: card,
              )
            : card;
      },
    );
  }
}

class _PostCard extends StatefulWidget {
  const _PostCard({
    super.key,
    required this.post,
    required this.isLiked,
    required this.onOpen,
    required this.onToggleSupport,
    this.awaitingValidation = false,
  });

  final FeedPost post;
  final bool isLiked;
  final VoidCallback onOpen;
  final VoidCallback? onToggleSupport;
  final bool awaitingValidation;

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard>
    with SingleTickerProviderStateMixin {
  /// Coração grande que aparece sobre a foto ao tocar duas vezes.
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  /// Dois toques: só curte (nunca descurte), como nas redes sociais.
  void _onDoubleTap() {
    if (!MediaQuery.disableAnimationsOf(context)) _burst.forward(from: 0);
    if (!widget.isLiked) widget.onToggleSupport?.call();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final isLiked = widget.isLiked;
    final onOpen = widget.onOpen;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onOpen,
        onDoubleTap: widget.onToggleSupport == null ? null : _onDoubleTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F1A1A2E),
                blurRadius: 20,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _AuthorAvatar(post: post, size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openProfileFromPost(context, post),
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _authorName(post),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: UrbText.body(
                              size: 15,
                              weight: FontWeight.w700,
                              color: UrbColors.ink,
                              height: 1.3,
                            ),
                          ),
                          Text(
                            '${formatRelativeTime(post.createdAt)} · ${post.cityName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: UrbText.body(
                              size: 12,
                              color: UrbColors.textMuted,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  UrbStatusChip(
                    status: widget.awaitingValidation
                        ? 'awaiting_validation'
                        : post.status,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Stack(
                alignment: Alignment.center,
                children: [
                  _PostImage(
                    url: post.primaryImageUrl,
                    height: 180,
                    radius: 18,
                  ),
                  IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _burst,
                      builder: (context, _) {
                        final t = _burst.value;
                        if (t == 0 || t == 1) return const SizedBox.shrink();
                        final scale = Curves.elasticOut.transform(
                          (t * 1.6).clamp(0.0, 1.0),
                        );
                        final opacity = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3);
                        return Opacity(
                          opacity: opacity.clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: 0.4 + 0.8 * scale,
                            child: const Icon(
                              Icons.favorite_rounded,
                              size: 96,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  color: Color(0x80E0467C),
                                  blurRadius: 24,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                post.title,
                style: UrbText.display(size: 18, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.sell_outlined,
                    size: 15,
                    color: UrbColors.violet,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      post.categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.body(size: 13, height: 1.3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _CountPill(
                    icon: isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: UrbColors.heart,
                    count: post.supportsCount,
                    highlighted: isLiked,
                    semanticLabel: 'apoios',
                    onTap: widget.onToggleSupport,
                  ),
                  const SizedBox(width: 8),
                  _CountPill(
                    icon: Icons.chat_bubble_outline_rounded,
                    color: UrbColors.commentBlue,
                    count: post.commentsCount,
                    semanticLabel: 'comentários',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.icon,
    required this.color,
    required this.count,
    required this.semanticLabel,
    this.highlighted = false,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final int count;
  final String semanticLabel;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pill = Semantics(
      label: '$count $semanticLabel',
      button: onTap != null,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: UrbMotion.of(context, UrbMotion.fast),
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: highlighted ? const Color(0xFFFDE8F0) : UrbColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: UrbMotion.of(
                context,
                const Duration(milliseconds: 320),
              ),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.elasticOut,
                ),
                child: child,
              ),
              child: Icon(icon, key: ValueKey(icon), size: 19, color: color),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: UrbText.body(
                size: 14,
                weight: FontWeight.w700,
                color: highlighted
                    ? const Color(0xFFB0164F)
                    : const Color(0xFF374151),
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null) return pill;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: pill,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// Aba "Em alta": ranking com medalhas
// ──────────────────────────────────────────────────────────

class _TrendingList extends StatelessWidget {
  const _TrendingList({
    required this.posts,
    required this.likedPostIds,
    required this.isLoading,
    required this.onOpenPost,
    required this.onToggleSupport,
    required this.awaitingIds,
  });

  final List<FeedPost> posts;
  final Set<int> likedPostIds;
  final bool isLoading;
  final ValueChanged<FeedPost> onOpenPost;
  final ValueChanged<FeedPost>? onToggleSupport;
  final Set<int> awaitingIds;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 132),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, _) => const _RowSkeleton(),
      );
    }

    if (posts.isEmpty) {
      return const _EmptyState(
        icon: Icons.local_fire_department_outlined,
        title: 'Ainda não há reportes em alta',
        text:
            'Assim que os reportes acumularem apoios, comentários e engajamento, eles aparecem aqui.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 132),
      itemCount: posts.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Row(
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                color: Color(0xFFE8590C),
                size: 22,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Top 20 da comunidade',
                  style: UrbText.display(size: 20, weight: FontWeight.w700),
                ),
              ),
              _CountBadge(count: posts.length),
            ],
          );
        }
        final post = posts[index - 1];
        final isLiked = likedPostIds.contains(post.id);
        final row = _RankRow(
          position: index,
          post: post,
          isLiked: isLiked,
          onOpen: () => onOpenPost(post),
          // Dois toques: curte (se ainda não curtiu).
          onDoubleTap: onToggleSupport == null || isLiked
              ? null
              : () => onToggleSupport!(post),
          awaitingValidation: awaitingIds.contains(post.id),
        );
        return index <= 6
            ? FadeSlideIn(
                delay: Duration(milliseconds: 50 * (index - 1)),
                child: row,
              )
            : row;
      },
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.position,
    required this.post,
    required this.isLiked,
    required this.onOpen,
    required this.onDoubleTap,
    this.awaitingValidation = false,
  });

  final int position;
  final FeedPost post;
  final bool isLiked;
  final VoidCallback onOpen;
  final VoidCallback? onDoubleTap;
  final bool awaitingValidation;

  static const _medals = {
    1: [Color(0xFFF6D365), Color(0xFFD4A017)],
    2: [Color(0xFFE3E7EC), Color(0xFF9AA3AD)],
    3: [Color(0xFFF0C08F), Color(0xFFB7773F)],
  };

  @override
  Widget build(BuildContext context) {
    final medal = _medals[position];

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onOpen,
        onDoubleTap: onDoubleTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: medal == null
                    ? null
                    : BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: medal,
                        ),
                      ),
                child: Text(
                  '$position',
                  style: UrbText.display(
                    size: 16,
                    weight: FontWeight.w800,
                    color: medal == null ? UrbColors.textMuted : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _PostImage(
                url: post.primaryImageUrl,
                height: 64,
                width: 64,
                radius: 14,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.display(size: 16, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _authorName(post),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.body(
                        size: 12,
                        color: UrbColors.textMuted,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Flexible(
                          child: UrbStatusChip(
                            status: awaitingValidation
                                ? 'awaiting_validation'
                                : post.status,
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedSwitcher(
                          duration: UrbMotion.of(
                            context,
                            const Duration(milliseconds: 320),
                          ),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(
                                scale: CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.elasticOut,
                                ),
                                child: child,
                              ),
                          child: Icon(
                            isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            key: ValueKey(isLiked),
                            size: 14,
                            color: UrbColors.heart,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${post.supportsCount}',
                          style: UrbText.body(
                            size: 13,
                            weight: FontWeight.w700,
                            color: const Color(0xFFB0164F),
                            height: 1.2,
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

// ──────────────────────────────────────────────────────────
// Peças compartilhadas
// ──────────────────────────────────────────────────────────

String _authorName(FeedPost post) {
  if (post.isAnonymous) return 'Usuário anônimo';
  final username = post.authorUsername?.trim();
  if (username != null && username.isNotEmpty) return '@$username';
  return post.authorLabel;
}

void _openProfileFromPost(BuildContext context, FeedPost post) {
  final authorId = post.authorId;
  if (authorId == null || post.isAnonymous) return;

  ProfileScreen.open(
    context,
    profileUserId: authorId,
    currentUserId: Supabase.instance.client.auth.currentUser?.id,
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: UrbText.display(size: 20, weight: FontWeight.w700),
          ),
        ),
        _CountBadge(count: count),
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: UrbColors.lavender,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: UrbText.body(
          size: 13,
          weight: FontWeight.w700,
          color: UrbColors.violetDeep,
          height: 1.3,
        ),
      ),
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({required this.post, required this.size});

  final FeedPost post;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = post.authorAvatarUrl;

    Widget content;
    if (post.isAnonymous) {
      content = Icon(
        Icons.visibility_off_outlined,
        size: size * 0.45,
        color: UrbColors.violetDeep,
      );
    } else if (url != null && url.isNotEmpty) {
      content = ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _initials(),
        ),
      );
    } else {
      content = _initials();
    }

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFEDE7FB), Color(0xFFDDF1FD)],
        ),
      ),
      child: content,
    );
  }

  Widget _initials() {
    final parts = post.authorLabel
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .take(2)
        .toList();
    final text = parts.isEmpty
        ? '?'
        : parts.length == 1
        ? parts.first.substring(0, 1).toUpperCase()
        : '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return Text(
      text,
      style: UrbText.display(
        size: size * 0.4,
        weight: FontWeight.w700,
        color: UrbColors.violetDeep,
      ),
    );
  }
}

class _PostImage extends StatelessWidget {
  const _PostImage({
    required this.url,
    required this.height,
    this.width,
    required this.radius,
  });

  final String? url;
  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = DecoratedBox(
      decoration: const BoxDecoration(gradient: UrbGradients.photo),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: const Color(0xFF9FB0C6),
          size: height > 100 ? 32 : 20,
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        width: width ?? double.infinity,
        child: url == null || url!.isEmpty
            ? fallback
            : Image.network(
                url!,
                fit: BoxFit.cover,
                // A foto aparece suavemente quando termina de carregar.
                frameBuilder: (context, child, frame, loadedSync) {
                  if (loadedSync) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: UrbMotion.of(context, UrbMotion.medium),
                    child: child,
                  );
                },
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 132),
      children: [
        FadeSlideIn(
          child: Column(
            children: [
              Container(
                width: 150,
                height: 150,
                decoration: const BoxDecoration(
                  color: UrbColors.lavender,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 64, color: UrbColors.violetDeep),
              ),
              const SizedBox(height: 22),
              Text(
                title,
                textAlign: TextAlign.center,
                style: UrbText.display(size: 22, weight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                text,
                textAlign: TextAlign.center,
                style: UrbText.body(size: 15),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({this.width, required this.height, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          colors: [Color(0xFFE6E8EE), Color(0xFFF3F4F8), Color(0xFFE6E8EE)],
        ),
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Skeleton(width: 40, height: 40, radius: 20),
              SizedBox(width: 10),
              Expanded(child: _Skeleton(height: 12)),
              SizedBox(width: 60),
            ],
          ),
          SizedBox(height: 12),
          _Skeleton(height: 170, radius: 18),
          SizedBox(height: 12),
          _Skeleton(width: 200, height: 16),
          SizedBox(height: 8),
          _Skeleton(width: 120, height: 12),
        ],
      ),
    );
  }
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        children: [
          _Skeleton(width: 36, height: 36, radius: 18),
          SizedBox(width: 12),
          _Skeleton(width: 64, height: 64, radius: 14),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Skeleton(height: 14),
                SizedBox(height: 8),
                _Skeleton(width: 90, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
