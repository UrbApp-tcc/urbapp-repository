import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/city_service.dart';
import '../services/feed_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_formatter.dart';
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 44, 0, 0),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const SizedBox(width: 44),
                    Expanded(
                      child: Center(
                        child: RichText(
                          text: const TextSpan(
                            children: [
                              TextSpan(
                                text: 'Urb',
                                style: TextStyle(
                                  color: Color(0xFF22252A),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              TextSpan(
                                text: 'App',
                                style: TextStyle(
                                  color: Color(0xFF8A8F98),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w300,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Abrir mapa da cidade',
                      onPressed: widget.onOpenMap,
                      icon: const Icon(Icons.map_outlined),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: DropdownButtonFormField<int?>(
                  key: ValueKey(widget.selectedCityId),
                  initialValue: widget.selectedCityId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Filtrar por cidade',
                    prefixIcon: Icon(Icons.location_city_outlined),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Todas as cidades'),
                    ),
                    ...widget.cities.map(
                      (city) => DropdownMenuItem<int?>(
                        value: city.id,
                        child: Text(city.name),
                      ),
                    ),
                  ],
                  onChanged: widget.onCityChanged,
                ),
              ),
              const SizedBox(height: 16),
              // Tab bar de ponta a ponta (sem padding horizontal)
              _FeedTabBar(controller: _tabController),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _FeedPostsList(
                posts: widget.posts,
                likedPostIds: widget.likedPostIds,
                isLoading: widget.isLoading,
                isTrending: false,
                sectionTitle: 'Ultimos reportes',
                emptyHero: const _FeedEmptyHero(),
                emptyList: const _FeedEmptyList(),
                onOpenPost: widget.onOpenPost,
              ),
              _FeedPostsList(
                posts: widget.trendingPosts,
                likedPostIds: widget.likedPostIds,
                isLoading: widget.isLoading,
                isTrending: true,
                sectionTitle: 'Top 20 da comunidade',
                emptyHero: const _TrendingEmptyHero(),
                emptyList: const _TrendingEmptyList(),
                onOpenPost: widget.onOpenPost,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeedPostsList extends StatelessWidget {
  const _FeedPostsList({
    required this.posts,
    required this.likedPostIds,
    required this.isLoading,
    required this.isTrending,
    required this.sectionTitle,
    required this.emptyHero,
    required this.emptyList,
    required this.onOpenPost,
  });

  final List<FeedPost> posts;
  final Set<int> likedPostIds;
  final bool isLoading;
  final bool isTrending;
  final String sectionTitle;
  final Widget emptyHero;
  final Widget emptyList;
  final ValueChanged<FeedPost> onOpenPost;

  @override
  Widget build(BuildContext context) {
    final featuredPost = posts.isNotEmpty ? posts.first : null;
    final latestPosts = posts.length > 1
        ? posts.skip(1).toList()
        : const <FeedPost>[];

    return Stack(
      fit: StackFit.expand,
      children: [
        if (isTrending) const _TrendingFeedBackdrop(),
        ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 132),
          children: [
            if (isLoading)
              const _FeaturedCardSkeleton()
            else if (featuredPost != null)
              _FeaturedFeedCard(
                post: featuredPost,
                isLiked: likedPostIds.contains(featuredPost.id),
                onOpen: () => onOpenPost(featuredPost),
              )
            else
              emptyHero,
            const SizedBox(height: 34),
            _SectionTitle(title: sectionTitle, trailing: '${posts.length}'),
            const SizedBox(height: 18),
            if (isLoading)
              ...List.generate(
                4,
                (index) => Padding(
                  padding: EdgeInsets.only(bottom: index == 3 ? 0 : 24),
                  child: const _LatestPostSkeleton(),
                ),
              )
            else if (posts.isEmpty)
              emptyList
            else
              ...latestPosts.asMap().entries.map(
                (entry) => Padding(
                  padding: EdgeInsets.only(
                    bottom: entry.key == latestPosts.length - 1 ? 0 : 24,
                  ),
                  child: _LatestPostRow(
                    post: entry.value,
                    isLiked: likedPostIds.contains(entry.value.id),
                    onOpen: () => onOpenPost(entry.value),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TrendingFeedBackdrop extends StatelessWidget {
  const _TrendingFeedBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Color(0x10FF9A4D),
                    Color(0x06FFC786),
                    Color(0x00FFFFFF),
                  ],
                  stops: [0.0, 0.22, 0.58],
                ),
              ),
            ),
          ),
          Positioned(
            top: 24,
            right: -42,
            child: Container(
              width: 170,
              height: 170,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0x18FF8B2D),
                    Color(0x08FFB35C),
                    Color(0x00FFFFFF),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 260,
            left: -76,
            child: Container(
              width: 220,
              height: 220,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0x10FFB14A),
                    Color(0x06FFD7A0),
                    Color(0x00FFFFFF),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedTabBar extends StatelessWidget {
  const _FeedTabBar({required this.controller});

  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFFF4F6F8),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE3E7EC)),
        ),
      ),
      child: TabBar(
        controller: controller,
        indicator: const BoxDecoration(
          color: Color(0xFF18222E),
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF7A838E),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        tabs: const [
          Tab(text: 'Recentes'),
          Tab(text: 'Em Alta'),
        ],
      ),
    );
  }
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


class _FeaturedFeedCard extends StatelessWidget {
  const _FeaturedFeedCard({
    required this.post,
    required this.isLiked,
    required this.onOpen,
  });

  final FeedPost post;
  final bool isLiked;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isCompleted = post.status == 'completed';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onOpen,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 311,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (post.primaryImageUrl != null &&
                    post.primaryImageUrl!.isNotEmpty)
                  Image.network(
                    post.primaryImageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _HeroFallback(category: post.categoryName);
                    },
                  )
                else
                  _HeroFallback(category: post.categoryName),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF141E28).withValues(alpha: 0.18),
                        const Color(0xFF141E28).withValues(alpha: 0.12),
                        const Color(0xFF141E28).withValues(alpha: 0.86),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              post.categoryName.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (isCompleted) ...[
                            const SizedBox(width: 8),
                            const _CompletedBadge(onDarkBackground: true),
                          ],
                          const SizedBox(width: 8),
                          Text(
                            formatRelativeTime(post.createdAt),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _FeedAuthorRow(
                        post: post,
                        onDarkBackground: true,
                        onTap: () => _openProfileFromPost(context, post),
                      ),
                      const Spacer(),
                      Text(
                        post.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Icon(
                            Icons.mode_comment_outlined,
                            color: Colors.white,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${post.commentsCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 24),
                          Icon(
                            isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: isLiked ? AppColors.error : Colors.white,
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${post.supportsCount}',
                            style: TextStyle(
                              color: isLiked ? AppColors.error : Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.reply_outlined,
                            color: Colors.white,
                            size: 24,
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
      ),
    );
  }
}

class _LatestPostRow extends StatelessWidget {
  const _LatestPostRow({
    required this.post,
    required this.isLiked,
    required this.onOpen,
  });

  final FeedPost post;
  final bool isLiked;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isCompleted = post.status == 'completed';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child:
                        post.primaryImageUrl != null &&
                            post.primaryImageUrl!.isNotEmpty
                        ? Image.network(
                            post.primaryImageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return _ThumbFallback(
                                category: post.categoryName,
                              );
                            },
                          )
                        : _ThumbFallback(category: post.categoryName),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FeedAuthorRow(
                          post: post,
                          onDarkBackground: false,
                          onTap: () => _openProfileFromPost(context, post),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                post.categoryName.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF9CA3AD),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (isCompleted) ...[
                              const SizedBox(width: 8),
                              const _CompletedBadge(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          post.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF141E28),
                            fontSize: 18,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              Icons.mode_comment_outlined,
                              size: 16,
                              color: const Color(
                                0xFF8F949D,
                              ).withValues(alpha: 0.92),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${post.commentsCount}',
                              style: const TextStyle(
                                color: Color(0xFF8F949D),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Icon(
                              isLiked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 16,
                              color: isLiked
                                  ? AppColors.error
                                  : const Color(
                                      0xFF8F949D,
                                    ).withValues(alpha: 0.92),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${post.supportsCount}',
                              style: TextStyle(
                                color: isLiked
                                    ? AppColors.error
                                    : const Color(0xFF8F949D),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Icon(
                              Icons.schedule_rounded,
                              size: 16,
                              color: const Color(
                                0xFF8F949D,
                              ).withValues(alpha: 0.92),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              formatRelativeTime(post.createdAt),
                              style: const TextStyle(
                                color: Color(0xFF8F949D),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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

class _CompletedBadge extends StatelessWidget {
  const _CompletedBadge({this.onDarkBackground = false});

  final bool onDarkBackground;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = onDarkBackground
        ? AppColors.resolved.withValues(alpha: 0.92)
        : AppColors.resolved.withValues(alpha: 0.12);
    final foregroundColor = onDarkBackground
        ? Colors.white
        : AppColors.resolved;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: onDarkBackground
              ? Colors.white.withValues(alpha: 0.28)
              : AppColors.resolved.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 13, color: foregroundColor),
          const SizedBox(width: 4),
          Text(
            'Concluida',
            style: TextStyle(
              color: foregroundColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedAuthorRow extends StatelessWidget {
  const _FeedAuthorRow({
    required this.post,
    required this.onDarkBackground,
    this.onTap,
  });

  final FeedPost post;
  final bool onDarkBackground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = onDarkBackground
        ? Colors.white.withValues(alpha: 0.92)
        : const Color(0xFF4B5563);
    final avatarBg = onDarkBackground
        ? Colors.white.withValues(alpha: 0.22)
        : const Color(0xFFE8ECF0);
    final iconColor = onDarkBackground
        ? Colors.white.withValues(alpha: 0.85)
        : const Color(0xFF8F949D);

    final child = Row(
      children: [
        _AuthorAvatar(
          post: post,
          backgroundColor: avatarBg,
          iconColor: iconColor,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            post.authorLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );

    if (onTap == null || post.isAnonymous || post.authorId == null) {
      return child;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: child,
      ),
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({
    required this.post,
    required this.backgroundColor,
    required this.iconColor,
  });

  final FeedPost post;
  final Color backgroundColor;
  final Color iconColor;

  static const double _radius = 14;

  @override
  Widget build(BuildContext context) {
    if (post.isAnonymous) {
      return CircleAvatar(
        radius: _radius,
        backgroundColor: backgroundColor,
        child: Icon(Icons.visibility_off_outlined, size: 16, color: iconColor),
      );
    }

    final url = post.authorAvatarUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: _radius,
        backgroundColor: backgroundColor,
        child: ClipOval(
          child: Image.network(
            url,
            width: _radius * 2,
            height: _radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _initials(),
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: _radius,
      backgroundColor: backgroundColor,
      child: _initials(),
    );
  }

  Widget _initials() {
    final label = post.authorLabel;
    final parts = label
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .take(2)
        .toList();
    String t;
    if (parts.isEmpty) {
      t = '?';
    } else if (parts.length == 1) {
      t = parts[0].substring(0, 1).toUpperCase();
    } else {
      t = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return Text(
      t,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: iconColor,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF8F949D),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFB9BEC6), width: 1.4),
          ),
          alignment: Alignment.center,
          child: Text(
            trailing,
            style: const TextStyle(
              color: Color(0xFF8F949D),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

IconData _iconForCategory(String categoryName) {
  final normalized = categoryName.toLowerCase();
  if (normalized.contains('luz')) return Icons.lightbulb_outline_rounded;
  if (normalized.contains('buraco')) return Icons.construction_rounded;
  if (normalized.contains('lixo')) return Icons.delete_outline_rounded;
  if (normalized.contains('agua') || normalized.contains('esgoto')) {
    return Icons.water_drop_outlined;
  }
  return Icons.location_city_outlined;
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF303B49), Color(0xFF18222E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          _iconForCategory(category),
          color: Colors.white.withValues(alpha: 0.88),
          size: 72,
        ),
      ),
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF4F6FA), Color(0xFFE9EEF5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          _iconForCategory(category),
          color: const Color(0xFF4B6078),
          size: 34,
        ),
      ),
    );
  }
}

class _FeaturedCardSkeleton extends StatelessWidget {
  const _FeaturedCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 311,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F6),
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

class _LatestPostSkeleton extends StatelessWidget {
  const _LatestPostSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F6),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 86,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3F6),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 18,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3F6),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 140,
                height: 18,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3F6),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeedEmptyHero extends StatelessWidget {
  const _FeedEmptyHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.forum_outlined, size: 32, color: Color(0xFF9097A1)),
          Spacer(),
          Text(
            'Nenhum reporte publicado ainda',
            style: TextStyle(
              color: Color(0xFF141E28),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Use o botao central para criar o primeiro reporte da comunidade.',
            style: TextStyle(
              color: Color(0xFF8F949D),
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedEmptyList extends StatelessWidget {
  const _FeedEmptyList();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Quando novos reportes forem criados, eles vao aparecer aqui.',
      style: TextStyle(color: Color(0xFF8F949D), fontSize: 15, height: 1.45),
    );
  }
}

class _TrendingEmptyHero extends StatelessWidget {
  const _TrendingEmptyHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFDF6EC), Color(0xFFF8E8D0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.local_fire_department_rounded,
            size: 34,
            color: Color(0xFFCB6A12),
          ),
          Spacer(),
          Text(
            'Ainda nao ha posts em alta',
            style: TextStyle(
              color: Color(0xFF141E28),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Assim que os reportes acumularem apoios, comentarios e engajamento, eles aparecem aqui.',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendingEmptyList extends StatelessWidget {
  const _TrendingEmptyList();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Esse ranking considera comentarios, apoios, seguidores do autor e o tempo no status atual.',
      style: TextStyle(color: Color(0xFF8F949D), fontSize: 15, height: 1.45),
    );
  }
}
