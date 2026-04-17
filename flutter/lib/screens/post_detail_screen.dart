import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/feed_service.dart';
import '../theme/app_theme.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.post});

  final FeedPost post;

  static void open(BuildContext context, FeedPost post) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PostDetailScreen(post: post)),
    );
  }

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _supabase = Supabase.instance.client;

  late int _supportsCount;
  bool _isLiked = false;
  bool _isLikeLoading = true;

  @override
  void initState() {
    super.initState();
    _supportsCount = widget.post.supportsCount;
    _loadLikeStatus();
  }

  Future<void> _loadLikeStatus() async {
    final userId = _supabase.auth.currentUser?.id;

    try {
      // Busca o count atualizado do banco
      final countResult = await _supabase
          .from('post_supports')
          .select('id')
          .eq('post_id', widget.post.id);

      final currentCount = (countResult as List).length;

      bool liked = false;
      if (userId != null) {
        final likeResult = await _supabase
            .from('post_supports')
            .select('id')
            .eq('post_id', widget.post.id)
            .eq('user_id', userId)
            .maybeSingle();
        liked = likeResult != null;
      }

      if (mounted) {
        setState(() {
          _supportsCount = currentCount;
          _isLiked = liked;
          _isLikeLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLikeLoading = false);
    }
  }

  Future<void> _toggleLike() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isLikeLoading = true);

    try {
      if (_isLiked) {
        await _supabase
            .from('post_supports')
            .delete()
            .eq('post_id', widget.post.id)
            .eq('user_id', userId);

        if (mounted) {
          setState(() {
            _isLiked = false;
            _supportsCount = (_supportsCount - 1).clamp(0, 999999);
          });
        }
      } else {
        await _supabase.from('post_supports').insert({
          'post_id': widget.post.id,
          'user_id': userId,
        });

        if (mounted) {
          setState(() {
            _isLiked = true;
            _supportsCount++;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao registrar like: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLikeLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrls = _orderedImageUrls(widget.post);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Reporte'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _AuthorHeader(post: widget.post),
          const SizedBox(height: 16),
          Text(
            widget.post.title,
            style: const TextStyle(
              color: Color(0xFF141E28),
              fontSize: 22,
              height: 1.25,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          if (widget.post.description.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              widget.post.description,
              style: const TextStyle(
                color: Color(0xFF374151),
                fontSize: 16,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
          if (imageUrls.isNotEmpty) ...[
            const SizedBox(height: 20),
            _PostImageGallery(urls: imageUrls),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(
                icon: Icons.label_outline_rounded,
                label: widget.post.categoryName,
              ),
              _MetaChip(
                icon: Icons.location_on_outlined,
                label: widget.post.cityName,
              ),
              _MetaChip(
                icon: Icons.flag_outlined,
                label: _statusLabel(widget.post.status),
              ),
            ],
          ),
          if (widget.post.agencyName != null &&
              widget.post.agencyName!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _MetaChip(
                icon: Icons.account_balance_outlined,
                label: widget.post.agencyName!.trim(),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            _formatPublishedAt(widget.post.createdAt),
            style: const TextStyle(color: AppColors.textHint, fontSize: 13),
          ),
          const SizedBox(height: 20),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                Icons.mode_comment_outlined,
                size: 22,
                color: AppColors.textSecondary.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 8),
              Text(
                '${widget.post.commentsCount}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 28),
              GestureDetector(
                onTap: _isLikeLoading ? null : _toggleLike,
                child: Row(
                  children: [
                    _isLikeLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 22,
                            color: _isLiked
                                ? AppColors.error
                                : AppColors.textSecondary.withValues(
                                    alpha: 0.9,
                                  ),
                          ),
                    const SizedBox(width: 8),
                    Text(
                      '$_supportsCount',
                      style: TextStyle(
                        color: _isLiked
                            ? AppColors.error
                            : AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Comentários',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 36,
                  color: AppColors.textHint.withValues(alpha: 0.85),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.post.commentsCount == 0
                      ? 'Nenhum comentário ainda.'
                      : 'Lista de comentários em breve.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.95),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<String> _orderedImageUrls(FeedPost post) {
    final fromItems =
        post.images
            .where((e) => e.publicUrl != null && e.publicUrl!.isNotEmpty)
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    final urls = fromItems.map((e) => e.publicUrl!).toList();
    if (urls.isNotEmpty) return urls;
    if (post.primaryImageUrl != null && post.primaryImageUrl!.isNotEmpty) {
      return [post.primaryImageUrl!];
    }
    return const [];
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'open':
        return 'Aberto';
      case 'in_analysis':
        return 'Em análise';
      case 'in_progress':
        return 'Em andamento';
      case 'completed':
        return 'Concluído';
      case 'closed':
        return 'Encerrado';
      case 'expired':
        return 'Expirado';
      default:
        return status;
    }
  }

  static String _formatPublishedAt(DateTime at) {
    final local = at.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year;
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return 'Publicado em $d/$m/$y às $h:$min';
  }
}

class _AuthorHeader extends StatelessWidget {
  const _AuthorHeader({required this.post});
  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailAvatar(post: post),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                post.authorLabel,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!post.isAnonymous &&
                  post.authorUsername != null &&
                  post.authorUsername!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  '@${post.authorUsername!.trim()}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailAvatar extends StatelessWidget {
  const _DetailAvatar({required this.post});
  final FeedPost post;
  static const double radius = 24;

  @override
  Widget build(BuildContext context) {
    if (post.isAnonymous) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.primaryLight,
        child: Icon(
          Icons.visibility_off_outlined,
          size: 22,
          color: AppColors.primaryDark,
        ),
      );
    }
    final url = post.authorAvatarUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.primaryLight,
        child: ClipOval(
          child: Image.network(
            url,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _initials(),
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primaryLight,
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
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.primaryDark,
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.divider,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostImageGallery extends StatefulWidget {
  const _PostImageGallery({required this.urls});
  final List<String> urls;

  @override
  State<_PostImageGallery> createState() => _PostImageGalleryState();
}

class _PostImageGalleryState extends State<_PostImageGallery> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.urls.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: Image.network(
            widget.urls.first,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const ColoredBox(
              color: AppColors.divider,
              child: Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 48,
                  color: AppColors.textHint,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: PageView.builder(
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => Image.network(
                widget.urls[i],
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: AppColors.divider,
                  child: Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 48,
                      color: AppColors.textHint,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.urls.length,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == _page ? AppColors.primary : AppColors.border,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
