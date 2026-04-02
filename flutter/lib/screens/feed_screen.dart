import 'package:flutter/material.dart';

import '../services/feed_service.dart';

class FeedScreen extends StatelessWidget {
  const FeedScreen({
    super.key,
    required this.posts,
    required this.isLoading,
    required this.isRefreshing,
    required this.onCreatePost,
  });

  final List<FeedPost> posts;
  final bool isLoading;
  final bool isRefreshing;
  final VoidCallback onCreatePost;

  @override
  Widget build(BuildContext context) {
    final featuredPost = posts.isNotEmpty ? posts.first : null;
    final latestPosts = posts.length > 1 ? posts.skip(1).take(6).toList() : const <FeedPost>[];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 132),
      children: [
        _HomeHeader(
          isRefreshing: isRefreshing,
          onCreatePost: onCreatePost,
        ),
        const SizedBox(height: 28),
        if (isLoading)
          const _FeaturedCardSkeleton()
        else if (featuredPost != null)
          _FeaturedFeedCard(post: featuredPost)
        else
          const _FeedEmptyHero(),
        const SizedBox(height: 34),
        _SectionTitle(
          title: 'Latest Reports',
          trailing: '${posts.length}',
        ),
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
          const _FeedEmptyList()
        else
          ...latestPosts.asMap().entries.map(
                (entry) => Padding(
                  padding: EdgeInsets.only(
                    bottom: entry.key == latestPosts.length - 1 ? 0 : 24,
                  ),
                  child: _LatestPostRow(post: entry.value),
                ),
              ),
      ],
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.isRefreshing,
    required this.onCreatePost,
  });

  final bool isRefreshing;
  final VoidCallback onCreatePost;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Color(0xFF18222E),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.remove_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        const Spacer(),
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'Urb',
                style: TextStyle(
                  color: Color(0xFF22252A),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              TextSpan(
                text: 'App',
                style: TextStyle(
                  color: Color(0xFF8A8F98),
                  fontSize: 16,
                  fontWeight: FontWeight.w300,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onCreatePost,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF18222E), width: 1.6),
            ),
            child: isRefreshing
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.add_rounded,
                    color: Color(0xFF18222E),
                    size: 22,
                  ),
          ),
        ),
      ],
    );
  }
}

class _FeaturedFeedCard extends StatelessWidget {
  const _FeaturedFeedCard({
    required this.post,
  });

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 311,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (post.primaryImageUrl != null && post.primaryImageUrl!.isNotEmpty)
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
                      Text(
                        post.categoryName.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatRelativeDate(post.createdAt),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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
                      const Icon(Icons.mode_comment_outlined, color: Colors.white, size: 24),
                      const SizedBox(width: 24),
                      const Icon(Icons.bookmark_border_rounded, color: Colors.white, size: 24),
                      const Spacer(),
                      const Icon(Icons.reply_outlined, color: Colors.white, size: 24),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatRelativeDate(DateTime value) {
    final difference = DateTime.now().difference(value.toLocal());

    if (difference.inMinutes < 1) return 'Agora';
    if (difference.inHours < 1) return '${difference.inMinutes} min ago';
    if (difference.inDays < 1) return '${difference.inHours} h ago';
    return '${difference.inDays} d ago';
  }
}

class _LatestPostRow extends StatelessWidget {
  const _LatestPostRow({
    required this.post,
  });

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 100,
            height: 100,
            child: post.primaryImageUrl != null && post.primaryImageUrl!.isNotEmpty
                ? Image.network(
                    post.primaryImageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _ThumbFallback(category: post.categoryName);
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
                Text(
                  post.categoryName.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF9CA3AD),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
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
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.trailing,
  });

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

class _HeroFallback extends StatelessWidget {
  const _HeroFallback({
    required this.category,
  });

  final String category;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF303B49),
            Color(0xFF18222E),
          ],
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
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback({
    required this.category,
  });

  final String category;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFF4F6FA),
            Color(0xFFE9EEF5),
          ],
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
      style: TextStyle(
        color: Color(0xFF8F949D),
        fontSize: 15,
        height: 1.45,
      ),
    );
  }
}
