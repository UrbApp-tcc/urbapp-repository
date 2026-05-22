import 'package:flutter/material.dart';

import '../services/notifications_service.dart';
import '../utils/date_formatter.dart';
import '../utils/error_formatter.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.currentUserId,
    required this.isActive,
    required this.onOpenSearch,
  });

  final String? currentUserId;
  final bool isActive;
  final VoidCallback onOpenSearch;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _notificationsService = NotificationsService();

  List<AppNotificationItem> _items = const [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  @override
  void didUpdateWidget(covariant NotificationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final becameActive = widget.isActive && !oldWidget.isActive;
    final userChanged = widget.currentUserId != oldWidget.currentUserId;
    if (becameActive || userChanged) {
      _loadNotifications();
    }
  }

  Future<void> _loadNotifications() async {
    final userId = widget.currentUserId;
    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _isLoading = false;
        _errorMessage = 'Não foi possível identificar sua conta.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await _notificationsService.fetchNotifications(userId: userId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = friendlyError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final unreadItems = _items.take(3).toList();
    final pastItems = _items.length > 3 ? _items.skip(3).toList() : const <AppNotificationItem>[];

    return RefreshIndicator(
      onRefresh: _loadNotifications,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 40, 32, 132),
        children: [
          _TopBar(onOpenSearch: widget.onOpenSearch),
          const SizedBox(height: 28),
          const Text(
            'Notificações',
            style: TextStyle(
              color: Color(0xFF141E28),
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 24),
          if (_isLoading)
            const _UnreadSkeleton()
          else if (_errorMessage != null)
            _EmptyState(
              title: 'Não foi possível carregar',
              description: _errorMessage!,
            )
          else if (unreadItems.isEmpty)
            const _EmptyState(
              title: 'Nenhuma notificação ainda',
              description: 'Quando alguém seguir, apoiar ou responder você, a atividade aparece aqui.',
            )
          else ...[
            const Text(
              'Mais recentes',
              style: TextStyle(
                color: Color(0xFF141E28),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF141E28).withValues(alpha: 0.08),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: unreadItems.asMap().entries.map((entry) {
                  final isLast = entry.key == unreadItems.length - 1;
                  return Column(
                    children: [
                      _NotificationTile(item: entry.value),
                      if (!isLast)
                        Divider(
                          height: 1,
                          color: const Color(0xFF141E28).withValues(alpha: 0.08),
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 34),
          const Text(
            'Anteriores',
            style: TextStyle(
              color: Color(0xFF141E28),
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 18),
          if (_isLoading)
            ...List.generate(
              4,
              (index) => Padding(
                padding: EdgeInsets.only(bottom: index == 3 ? 0 : 20),
                child: const _PastNotificationSkeleton(),
              ),
            )
          else if (pastItems.isEmpty)
            const _EmptyState(
              title: 'Sem histórico anterior',
              description: 'As notificações mais antigas vão ficando listadas aqui.',
            )
          else
            ...pastItems.asMap().entries.map(
                  (entry) => Padding(
                    padding: EdgeInsets.only(bottom: entry.key == pastItems.length - 1 ? 0 : 18),
                    child: _NotificationTile(item: entry.value),
                  ),
                ),
        ],
      ),
    );
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
            Icons.notifications_none_rounded,
            color: Colors.white,
            size: 22,
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
    required this.item,
  });

  final AppNotificationItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _NotificationAvatar(item: item),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          color: Color(0xFF141E28),
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatRelativeTime(item.createdAt),
                      style: const TextStyle(
                        color: Color(0xFF8F949D),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.description,
                  style: const TextStyle(
                    color: Color(0xFF4B5563),
                    fontSize: 14,
                    height: 1.45,
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

class _NotificationAvatar extends StatelessWidget {
  const _NotificationAvatar({required this.item});

  final AppNotificationItem item;

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.type) {
      AppNotificationType.newFollower => Icons.person_add_alt_1_rounded,
      AppNotificationType.postSupport => Icons.favorite_rounded,
      AppNotificationType.commentSupport => Icons.thumb_up_alt_rounded,
      AppNotificationType.postComment => Icons.chat_bubble_rounded,
      AppNotificationType.commentReply => Icons.reply_rounded,
    };

    final fallback = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFF4F1FF),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE4DAFF)),
      ),
      child: Icon(icon, color: const Color(0xFF8F6FE8), size: 22),
    );

    final avatarUrl = item.actorAvatarUrl;
    if (avatarUrl == null || avatarUrl.isEmpty) return fallback;

    return ClipOval(
      child: Image.network(
        avatarUrl,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class _UnreadSkeleton extends StatelessWidget {
  const _UnreadSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F6),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}

class _PastNotificationSkeleton extends StatelessWidget {
  const _PastNotificationSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: Color(0xFFF1F3F6),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 140,
                height: 14,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3F6),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3F6),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 200,
                height: 16,
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
