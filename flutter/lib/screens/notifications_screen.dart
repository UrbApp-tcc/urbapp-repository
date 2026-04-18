import 'package:flutter/material.dart';

import '../services/feed_service.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({
    super.key,
    required this.posts,
    required this.isLoading,
    required this.onOpenSearch,
  });

  final List<FeedPost> posts;
  final bool isLoading;
  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    final unreadItems = posts.take(2).toList();
    final pastItems = posts.length > 2 ? posts.skip(2).take(6).toList() : const <FeedPost>[];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 132),
      children: [
        _TopBar(onOpenSearch: onOpenSearch),
        const SizedBox(height: 28),
        const Text(
          'Não lidas',
          style: TextStyle(
            color: Color(0xFF141E28),
            fontSize: 36,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 24),
        if (isLoading)
          const _UnreadSkeleton()
        else if (unreadItems.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF141E28).withValues(alpha: 0.12),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: unreadItems.asMap().entries.map((entry) {
                final isLast = entry.key == unreadItems.length - 1;
                return Column(
                  children: [
                    _NotificationTile(post: entry.value),
                    if (!isLast)
                      Container(
                        height: 2,
                        color: const Color(0xFF141E28).withValues(alpha: 0.08),
                      ),
                  ],
                );
              }).toList(),
            ),
          )
        else
          const _EmptyState(
            title: 'Nenhuma notificação nova',
            description: 'Novos movimentos da comunidade vão aparecer aqui.',
          ),
        const SizedBox(height: 38),
        Text(
          _todayLabel(),
          style: const TextStyle(
            color: Color(0xFF141E28),
            fontSize: 26,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 18),
        if (isLoading)
          ...List.generate(
            4,
            (index) => Padding(
              padding: EdgeInsets.only(bottom: index == 3 ? 0 : 24),
              child: const _PastNotificationSkeleton(),
            ),
          )
        else if (pastItems.isNotEmpty)
          ...pastItems.asMap().entries.map(
                (entry) => Padding(
                  padding: EdgeInsets.only(bottom: entry.key == pastItems.length - 1 ? 0 : 24),
                  child: _NotificationTile(post: entry.value),
                ),
              )
        else
          const _EmptyState(
            title: 'Sem histórico recente',
            description:
                'Assim que novos reportes surgirem, eles vão aparecer nesta linha do tempo.',
          ),
      ],
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    final months = [
      'janeiro',
      'fevereiro',
      'março',
      'abril',
      'maio',
      'junho',
      'julho',
      'agosto',
      'setembro',
      'outubro',
      'novembro',
      'dezembro',
    ];

    return '${now.day} de ${months[now.month - 1]} de ${now.year}';
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onOpenSearch,
  });

  final VoidCallback onOpenSearch;

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
        GestureDetector(
          onTap: onOpenSearch,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF18222E), width: 1.6),
            ),
            child: const Icon(
              Icons.search_rounded,
              color: Color(0xFF18222E),
              size: 22,
            ),
          ),
        ),
      ],
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.post,
  });

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 20),
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
          const SizedBox(height: 8),
          Text(
            post.title,
            style: const TextStyle(
              color: Color(0xFF141E28),
              fontSize: 16,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnreadSkeleton extends StatelessWidget {
  const _UnreadSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 224,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F6),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

class _PastNotificationSkeleton extends StatelessWidget {
  const _PastNotificationSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 88,
          height: 12,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F6),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F6),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 220,
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F3F6),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF141E28),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
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
