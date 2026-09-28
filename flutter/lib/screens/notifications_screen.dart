import 'package:flutter/material.dart';

import '../services/notifications_service.dart';
import '../theme/urbapp_design.dart';
import '../utils/date_formatter.dart';
import '../utils/error_formatter.dart';
import '../widgets/city_skyline.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/urb_post_image.dart';

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
      final items = await _notificationsService.fetchNotifications(
        userId: userId,
      );
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
    final recentItems = _items.take(3).toList();
    final pastItems = _items.length > 3
        ? _items.skip(3).toList()
        : const <AppNotificationItem>[];

    return ColoredBox(
      color: UrbColors.surface,
      child: RefreshIndicator(
        onRefresh: _loadNotifications,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 132),
          children: [
            _Header(
              subtitle: _isLoading
                  ? 'Carregando atividade...'
                  : _items.isEmpty
                  ? 'Tudo em dia'
                  : _items.length == 1
                  ? '1 atividade'
                  : '${_items.length} atividades',
              onOpenSearch: widget.onOpenSearch,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isLoading) ...[
                    const _SectionLabel(text: 'Mais recentes', highlight: true),
                    const SizedBox(height: 10),
                    for (var i = 0; i < 4; i++) ...[
                      const _TileSkeleton(),
                      const SizedBox(height: 10),
                    ],
                  ] else if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: FadeSlideIn(
                        child: Column(
                          children: [
                            UrbEmptyState(
                              icon: Icons.cloud_off_rounded,
                              title: 'Não foi possível carregar',
                              text: _errorMessage!,
                            ),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: _loadNotifications,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Tentar novamente'),
                              style: TextButton.styleFrom(
                                foregroundColor: UrbColors.violetDeep,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: FadeSlideIn(
                        child: UrbEmptyState(
                          icon: Icons.notifications_none_rounded,
                          title: 'Nenhuma notificação ainda',
                          text:
                              'Quando alguém seguir, apoiar ou responder você, a atividade aparece aqui.',
                        ),
                      ),
                    )
                  else ...[
                    const _SectionLabel(text: 'Mais recentes', highlight: true),
                    const SizedBox(height: 10),
                    for (var i = 0; i < recentItems.length; i++) ...[
                      FadeSlideIn(
                        key: ValueKey('recent-${recentItems[i].id}'),
                        delay: Duration(milliseconds: 60 * i),
                        child: _NotificationTile(
                          item: recentItems[i],
                          highlighted: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (pastItems.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const _SectionLabel(text: 'Anteriores', highlight: false),
                      const SizedBox(height: 10),
                      for (var i = 0; i < pastItems.length; i++) ...[
                        if (i < 6)
                          FadeSlideIn(
                            key: ValueKey('past-${pastItems[i].id}'),
                            delay: Duration(milliseconds: 180 + 40 * i),
                            child: _NotificationTile(
                              item: pastItems[i],
                              highlighted: false,
                            ),
                          )
                        else
                          _NotificationTile(
                            item: pastItems[i],
                            highlighted: false,
                          ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ],
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
// Topo roxo
// ──────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.subtitle, required this.onOpenSearch});

  final String subtitle;
  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            height: 100,
            child: CitySkyline(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
            child: Row(
              children: [
                const SizedBox(width: 44),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'Notificações',
                        textAlign: TextAlign.center,
                        style: UrbText.display(
                          size: 26,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedSwitcher(
                        duration: UrbMotion.of(context, UrbMotion.fast),
                        child: Text(
                          subtitle,
                          key: ValueKey(subtitle),
                          textAlign: TextAlign.center,
                          style: UrbText.body(
                            size: 14,
                            color: UrbColors.heroText,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: 'Buscar reportes',
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                    child: InkWell(
                      onTap: onOpenSearch,
                      borderRadius: BorderRadius.circular(14),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.search_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.highlight});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: UrbText.body(
        size: 12,
        weight: FontWeight.w700,
        color: highlight ? UrbColors.violet : UrbColors.textMuted,
        height: 1.3,
      ).copyWith(letterSpacing: 1.1),
    );
  }
}

// ──────────────────────────────────────────────────────────
// Notificação
// ──────────────────────────────────────────────────────────

({IconData icon, Color color, Color background}) _typeStyle(
  AppNotificationType type,
) {
  switch (type) {
    case AppNotificationType.newFollower:
      return (
        icon: Icons.person_add_alt_1_rounded,
        color: const Color(0xFF065F46),
        background: const Color(0xFFD1FAE5),
      );
    case AppNotificationType.postSupport:
      return (
        icon: Icons.favorite_rounded,
        color: const Color(0xFFB0164F),
        background: const Color(0xFFFDE8F0),
      );
    case AppNotificationType.commentSupport:
      return (
        icon: Icons.thumb_up_alt_rounded,
        color: const Color(0xFFB0164F),
        background: const Color(0xFFFDE8F0),
      );
    case AppNotificationType.postComment:
      return (
        icon: Icons.chat_bubble_rounded,
        color: UrbColors.commentBlue,
        background: const Color(0xFFE0ECFB),
      );
    case AppNotificationType.commentReply:
      return (
        icon: Icons.reply_rounded,
        color: UrbColors.commentBlue,
        background: const Color(0xFFE0ECFB),
      );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.highlighted});

  final AppNotificationItem item;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final style = _typeStyle(item.type);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlighted ? Colors.white : Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: highlighted
            ? const [
                BoxShadow(
                  color: Color(0x0F1A1A2E),
                  blurRadius: 20,
                  offset: Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Foto de quem fez a ação, com o ícone do tipo no canto.
          SizedBox(
            width: 50,
            height: 50,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _Avatar(url: item.actorAvatarUrl, label: item.actorDisplayName),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: style.background,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Icon(style.icon, size: 12, color: style.color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: UrbText.body(
                          size: 14,
                          weight: FontWeight.w700,
                          color: UrbColors.ink,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatRelativeTime(item.createdAt),
                      style: UrbText.body(
                        size: 12,
                        weight: FontWeight.w600,
                        color: UrbColors.textMuted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  item.description,
                  style: UrbText.body(size: 13, height: 1.4),
                ),
              ],
            ),
          ),
          if (highlighted) ...[
            const SizedBox(width: 8),
            Container(
              margin: const EdgeInsets.only(top: 6),
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: UrbColors.violet,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.label});

  final String? url;
  final String label;

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
    final fallback = Text(
      initials,
      style: UrbText.display(
        size: 17,
        weight: FontWeight.w700,
        color: UrbColors.violetDeep,
      ),
    );
    final imageUrl = url;

    return Container(
      width: 50,
      height: 50,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFEDE7FB), Color(0xFFDDF1FD)],
        ),
      ),
      child: imageUrl == null || imageUrl.isEmpty
          ? fallback
          : ClipOval(
              child: Image.network(
                imageUrl,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
    );
  }
}

class _TileSkeleton extends StatelessWidget {
  const _TileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        children: [
          UrbSkeleton(width: 50, height: 50, radius: 25),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UrbSkeleton(height: 13),
                SizedBox(height: 8),
                UrbSkeleton(width: 170, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
