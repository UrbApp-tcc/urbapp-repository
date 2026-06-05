import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logic/app_rules.dart';
import '../services/feed_service.dart';
import '../services/post_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_formatter.dart';
import '../utils/date_formatter.dart';
import 'profile_screen.dart';
import 'resolve_complaint_screen.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.post});

  final FeedPost post;

  static Future<bool?> open(BuildContext context, FeedPost post) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => PostDetailScreen(post: post)),
    );
  }

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _supabase = Supabase.instance.client;
  final _postService = PostService();
  final _commentController = TextEditingController();

  late int _supportsCount;
  late int _commentsCount;

  bool _isLiked = false;
  bool _isLikeLoading = true;
  bool _isCommentsLoading = true;
  bool _isSubmittingComment = false;
  bool _isResolvingAddress = true;
  bool _hasStatusChanges = false;

  int? _replyParentCommentId;
  String? _replyTargetLabel;

  String? _resolvedStreet;
  String? _resolvedNeighborhood;
  List<PostComment> _comments = const [];

  @override
  void initState() {
    super.initState();
    _supportsCount = widget.post.supportsCount;
    _commentsCount = widget.post.commentsCount;
    _loadLikeStatus();
    _loadComments();
    _loadAddress();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadLikeStatus() async {
    final userId = _supabase.auth.currentUser?.id;

    try {
      final countResult = await _supabase
          .from('post_supports')
          .select('id')
          .eq('post_id', widget.post.id)
          .count(CountOption.exact);

      final currentCount = countResult.count;

      var liked = false;
      if (userId != null) {
        final likeResult = await _supabase
            .from('post_supports')
            .select('id')
            .eq('post_id', widget.post.id)
            .eq('user_id', userId)
            .maybeSingle();
        liked = likeResult != null;
      }

      if (!mounted) return;
      setState(() {
        _supportsCount = currentCount;
        _isLiked = liked;
        _isLikeLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLikeLoading = false);
      }
    }
  }

  Future<void> _toggleLike() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isLikeLoading = true);

    try {
      final newLikedState = await _postService.toggleSupport(
        postId: widget.post.id,
        currentUserId: userId,
        postAuthorId: widget.post.authorId,
        isCurrentlyLiked: _isLiked,
        postStatus: widget.post.status,
      );

      if (!mounted) return;
      setState(() {
        _isLiked = newLikedState;
        _supportsCount =
            newLikedState ? _supportsCount + 1 : (_supportsCount - 1).clamp(0, 999999);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLikeLoading = false);
      }
    }
  }

  Future<void> _loadComments() async {
    try {
      final comments = await _postService.fetchComments(widget.post.id);

      if (!mounted) return;
      setState(() {
        _comments = comments;
        _commentsCount = _countComments(comments);
        _isCommentsLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isCommentsLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _submitComment() async {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) return;

    if (isFinalStatus(widget.post.status)) return;

    final body = _commentController.text.trim();
    if (body.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmittingComment = true);

    try {
      await _postService.createComment(
        postId: widget.post.id,
        userId: currentUser.id,
        body: body,
        parentCommentId: _replyParentCommentId,
      );

      if (!mounted) return;

      _commentController.clear();
      setState(() {
        _replyParentCommentId = null;
        _replyTargetLabel = null;
      });
      await _loadComments();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Comentário publicado com sucesso.'),
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
        setState(() => _isSubmittingComment = false);
      }
    }
  }

  Future<void> _toggleCommentLike(PostComment comment) async {
    final previousLiked = comment.isLiked;
    final previousCount = comment.likesCount;

    setState(() {
      _comments = _updateCommentTree(
        _comments,
        comment.id,
        (item) => item.copyWith(
          isLiked: !item.isLiked,
          likesCount: item.isLiked
              ? (item.likesCount - 1).clamp(0, 999999)
              : item.likesCount + 1,
        ),
      );
    });

    try {
      await _postService.toggleCommentLike(
        commentId: comment.id,
        isLiked: previousLiked,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _comments = _updateCommentTree(
          _comments,
          comment.id,
          (item) =>
              item.copyWith(isLiked: previousLiked, likesCount: previousCount),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _beginReply(PostComment comment) {
    final topLevelParentId = comment.parentCommentId ?? comment.id;
    final target = comment.authorUsername?.trim().isNotEmpty == true
        ? '@${comment.authorUsername!.trim()}'
        : comment.authorLabel;

    setState(() {
      _replyParentCommentId = topLevelParentId;
      _replyTargetLabel = target;
    });
  }

  void _cancelReply() {
    setState(() {
      _replyParentCommentId = null;
      _replyTargetLabel = null;
    });
  }

  Future<void> _loadAddress() async {
    try {
      final address = await _fetchAddressFromCoordinates(
        widget.post.latitude,
        widget.post.longitude,
      );

      if (!mounted) return;
      setState(() {
        _resolvedStreet = address.street;
        _resolvedNeighborhood = address.neighborhood;
        _isResolvingAddress = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolvedStreet = null;
        _resolvedNeighborhood = null;
        _isResolvingAddress = false;
      });
    }
  }

  Future<({String street, String neighborhood, String city})>
  _fetchAddressFromCoordinates(double latitude, double longitude) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': latitude.toString(),
      'lon': longitude.toString(),
      'zoom': '18',
      'addressdetails': '1',
    });

    final response = await http
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Falha ao consultar o endereço do reporte.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final address = (data['address'] as Map<String, dynamic>?) ?? const {};

    final street =
        (address['road'] ?? address['pedestrian'] ?? address['footway'] ?? '')
            .toString()
            .trim();
    final neighborhood =
        (address['suburb'] ??
                address['neighbourhood'] ??
                address['quarter'] ??
                '')
            .toString()
            .trim();
    final city =
        (address['city'] ??
                address['town'] ??
                address['village'] ??
                address['municipality'] ??
                address['county'] ??
                '')
            .toString()
            .trim();

    return (street: street, neighborhood: neighborhood, city: city);
  }

  Future<void> _copyToClipboard(String text, String successMessage) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(successMessage),
        backgroundColor: AppColors.resolved,
      ),
    );
  }

  void _showLocationMap() {
    final point = LatLng(widget.post.latitude, widget.post.longitude);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Localização do reporte',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _addressDisplayLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    height: 300,
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: point,
                        initialZoom: 16,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.meu_app',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: point,
                              width: 44,
                              height: 44,
                              child: const Icon(
                                Icons.location_pin,
                                size: 42,
                                color: AppColors.accentPink,
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
        );
      },
    );
  }

  void _showShareOptions() {
    final link = _buildShareLink();
    final message = _buildShareMessage(link);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Compartilhar reporte',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.post.title,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primaryLight,
                    child: Icon(
                      Icons.link_rounded,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  title: const Text('Copiar link'),
                  subtitle: Text(
                    link,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _copyToClipboard(
                      link,
                      'Link copiado para a área de transferência.',
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primaryLight,
                    child: Icon(
                      Icons.ios_share_rounded,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  title: const Text('Copiar mensagem para compartilhar'),
                  subtitle: const Text(
                    'Copia uma mensagem pronta com o link do reporte.',
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _copyToClipboard(
                      message,
                      'Mensagem de compartilhamento copiada.',
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openProfile(String userId) {
    ProfileScreen.open(
      context,
      profileUserId: userId,
      currentUserId: _supabase.auth.currentUser?.id,
    );
  }

  Future<void> _openResolveComplaint() async {
    final resolved = await ResolveComplaintScreen.open(context, widget.post);
    if (!mounted || resolved != true) return;

    setState(() => _hasStatusChanges = true);
  }

  int _countComments(List<PostComment> comments) {
    var total = 0;
    for (final comment in comments) {
      total += 1;
      total += comment.replies.length;
    }
    return total;
  }

  List<PostComment> _updateCommentTree(
    List<PostComment> comments,
    int commentId,
    PostComment Function(PostComment comment) update,
  ) {
    return comments.map((comment) {
      if (comment.id == commentId) {
        return update(comment);
      }

      if (comment.replies.isEmpty) return comment;

      return comment.copyWith(
        replies: comment.replies
            .map((reply) => reply.id == commentId ? update(reply) : reply)
            .toList(),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final imageUrls = _orderedImageUrls(widget.post);
    final currentUserId = _supabase.auth.currentUser?.id;
    final canResolve =
        currentUserId != null &&
        widget.post.authorId == currentUserId &&
        !isFinalStatus(widget.post.status);
    final isCompleted = widget.post.status == 'completed';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            final hasChanges =
                _hasStatusChanges ||
                _supportsCount != widget.post.supportsCount ||
                _commentsCount != widget.post.commentsCount;
            Navigator.of(context).pop(hasChanges);
          },
        ),
        title: const Text('Reporte'),
        actions: [
          IconButton(
            tooltip: 'Compartilhar',
            onPressed: _showShareOptions,
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _AuthorHeader(
            post: widget.post,
            onTap: widget.post.authorId == null || widget.post.isAnonymous
                ? null
                : () => _openProfile(widget.post.authorId!),
          ),
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
          const SizedBox(height: 12),
          Text(
            _formatPublishedAt(widget.post.createdAt),
            style: const TextStyle(color: AppColors.textHint, fontSize: 13),
          ),
          if (isCompleted) ...[
            const SizedBox(height: 14),
            _CompletedNotice(resolvedAt: widget.post.resolvedAt),
          ],
          if (widget.post.description.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
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
          const SizedBox(height: 18),
          _AddressCard(
            isLoading: _isResolvingAddress,
            address: _addressDisplayLabel,
            onTap: _showLocationMap,
          ),
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
                icon: Icons.location_city_outlined,
                label: widget.post.cityName,
              ),
              _MetaChip(
                icon: Icons.flag_outlined,
                label: _statusLabel(widget.post.status),
              ),
              if (widget.post.agencyName != null &&
                  widget.post.agencyName!.trim().isNotEmpty)
                _MetaChip(
                  icon: Icons.account_balance_outlined,
                  label: widget.post.agencyName!.trim(),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (canResolve) ...[
            _ResolveComplaintCard(onTap: _openResolveComplaint),
            const SizedBox(height: 20),
          ],
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
                '$_commentsCount',
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
              const Spacer(),
              TextButton.icon(
                onPressed: _showShareOptions,
                icon: const Icon(Icons.reply_outlined, size: 18),
                label: const Text('Compartilhar'),
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
          if (!isFinalStatus(widget.post.status))
            _CommentComposer(
              controller: _commentController,
              isSubmitting: _isSubmittingComment,
              onSubmit: _submitComment,
              replyTargetLabel: _replyTargetLabel,
              onCancelReply: _replyParentCommentId == null ? null : _cancelReply,
            ),
          const SizedBox(height: 16),
          if (_isCommentsLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_comments.isEmpty)
            const _EmptyCommentsCard()
          else
            ..._comments.map(
              (comment) => _CommentThread(
                comment: comment,
                onLikeTap: () => _toggleCommentLike(comment),
                onReplyTap: () => _beginReply(comment),
                onReplyLikeTap: _toggleCommentLike,
                onReplyReplyTap: _beginReply,
                onOpenProfile: _openProfile,
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


  String _buildShareLink() {
    return 'urbapp://posts/${widget.post.id}';
  }

  String _buildShareMessage(String link) {
    final neighborhood = _shareNeighborhood;
    return 'Veja esse reporte no UrbApp: Problema de ${widget.post.categoryName} em $neighborhood\n$link';
  }

  String get _addressDisplayLabel {
    if (_isResolvingAddress) return 'Buscando endereço...';

    final parts = <String>[
      if ((_resolvedStreet ?? '').trim().isNotEmpty) _resolvedStreet!.trim(),
      if ((_resolvedNeighborhood ?? '').trim().isNotEmpty)
        _resolvedNeighborhood!.trim(),
    ];

    if (parts.isEmpty) return 'Localização do reporte';
    return parts.join(', ');
  }

  String get _shareNeighborhood {
    final neighborhood = _resolvedNeighborhood?.trim();
    if (neighborhood == null || neighborhood.isEmpty) {
      return widget.post.cityName;
    }
    return neighborhood;
  }
}

class _AuthorHeader extends StatelessWidget {
  const _AuthorHeader({required this.post, this.onTap});

  final FeedPost post;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Row(
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

    if (onTap == null) return child;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: child,
      ),
    );
  }
}

class _DetailAvatar extends StatelessWidget {
  const _DetailAvatar({
    this.post,
    this.label,
    this.avatarUrl,
    this.backgroundColor = AppColors.primaryLight,
    this.textColor = AppColors.primaryDark,
    this.radius = 24,
  });

  final FeedPost? post;
  final String? label;
  final String? avatarUrl;
  final Color backgroundColor;
  final Color textColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (post?.isAnonymous ?? false) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: Icon(
          Icons.visibility_off_outlined,
          size: radius - 2,
          color: textColor,
        ),
      );
    }

    final resolvedAvatarUrl = avatarUrl ?? post?.authorAvatarUrl;
    if (resolvedAvatarUrl != null && resolvedAvatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        child: ClipOval(
          child: Image.network(
            resolvedAvatarUrl,
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
      backgroundColor: backgroundColor,
      child: _initials(),
    );
  }

  Widget _initials() {
    final resolvedLabel = label ?? post?.authorLabel ?? 'Usuário';
    final parts = resolvedLabel
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .take(2)
        .toList();

    String text;
    if (parts.isEmpty) {
      text = '?';
    } else if (parts.length == 1) {
      text = parts[0].substring(0, 1).toUpperCase();
    } else {
      text = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }

    return Text(
      text,
      style: TextStyle(
        fontSize: radius * 0.6,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.isLoading,
    required this.address,
    required this.onTap,
  });

  final bool isLoading;
  final String address;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.place_outlined,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      address,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isLoading
                          ? 'Carregando localização...'
                          : 'Toque para abrir no mapa',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResolveComplaintCard extends StatelessWidget {
  const _ResolveComplaintCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.resolved.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.resolved.withValues(alpha: 0.32),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.resolved.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.task_alt_rounded,
                  color: AppColors.resolved,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resolver reclamação',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Informe a solução e marque este reporte como concluído.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Icon(Icons.chevron_right_rounded, color: AppColors.resolved),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletedNotice extends StatelessWidget {
  const _CompletedNotice({this.resolvedAt});

  final DateTime? resolvedAt;

  @override
  Widget build(BuildContext context) {
    final resolvedAtLabel = resolvedAt == null
        ? null
        : _PostDetailScreenState._formatPublishedAt(resolvedAt!);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.resolved.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.resolved.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.resolved.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppColors.resolved,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reclamação concluída',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (resolvedAtLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    resolvedAtLabel.replaceFirst(
                      'Publicado em',
                      'Resolvida em',
                    ),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
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

class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.isSubmitting,
    required this.onSubmit,
    this.replyTargetLabel,
    this.onCancelReply,
  });

  final TextEditingController controller;
  final bool isSubmitting;
  final VoidCallback onSubmit;
  final String? replyTargetLabel;
  final VoidCallback? onCancelReply;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          if (replyTargetLabel != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Respondendo $replyTargetLabel',
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onCancelReply,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: replyTargetLabel == null
                  ? 'Adicione um comentário ao reporte'
                  : 'Escreva sua resposta',
              filled: true,
              fillColor: Colors.white,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  replyTargetLabel == null
                      ? 'Comentários ajudam a complementar o chamado.'
                      : 'As respostas ficam agrupadas no comentário principal.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: isSubmitting ? null : onSubmit,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(replyTargetLabel == null ? 'Comentar' : 'Responder'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommentThread extends StatelessWidget {
  const _CommentThread({
    required this.comment,
    required this.onLikeTap,
    required this.onReplyTap,
    required this.onReplyLikeTap,
    required this.onReplyReplyTap,
    required this.onOpenProfile,
  });

  final PostComment comment;
  final VoidCallback onLikeTap;
  final VoidCallback onReplyTap;
  final ValueChanged<PostComment> onReplyLikeTap;
  final ValueChanged<PostComment> onReplyReplyTap;
  final Function(String userId) onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _CommentEntry(
            comment: comment,
            isReply: false,
            onLikeTap: onLikeTap,
            onReplyTap: onReplyTap,
            onOpenProfile: onOpenProfile,
          ),
          if (comment.replies.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(left: 18),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: AppColors.border, width: 2),
                ),
              ),
              child: Column(
                children: comment.replies
                    .asMap()
                    .entries
                    .map(
                      (entry) => Padding(
                        padding: EdgeInsets.only(
                          bottom: entry.key == comment.replies.length - 1
                              ? 0
                              : 12,
                        ),
                        child: _CommentEntry(
                          comment: entry.value,
                          isReply: true,
                          onLikeTap: () => onReplyLikeTap(entry.value),
                          onReplyTap: () => onReplyReplyTap(entry.value),
                          onOpenProfile: onOpenProfile,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommentEntry extends StatelessWidget {
  const _CommentEntry({
    required this.comment,
    required this.isReply,
    required this.onLikeTap,
    required this.onReplyTap,
    required this.onOpenProfile,
  });

  final PostComment comment;
  final bool isReply;
  final VoidCallback onLikeTap;
  final VoidCallback onReplyTap;
  final Function(String userId) onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailAvatar(
          label: comment.authorLabel,
          avatarUrl: comment.authorAvatarUrl,
          backgroundColor: AppColors.primaryLight,
          textColor: AppColors.primaryDark,
          radius: isReply ? 18 : 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => onOpenProfile(comment.userId),
                      child: Text(
                        comment.authorLabel,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: isReply ? 13 : 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => onOpenProfile(comment.userId),
                    child: Text(
                      formatRelativeTime(comment.createdAt),
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (comment.authorUsername != null &&
                  comment.authorUsername!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  '@${comment.authorUsername!.trim()}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                comment.body,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: isReply ? 13 : 14,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  InkWell(
                    onTap: onLikeTap,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            comment.isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 16,
                            color: comment.isLiked
                                ? AppColors.error
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${comment.likesCount}',
                            style: TextStyle(
                              color: comment.isLiked
                                  ? AppColors.error
                                  : AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  InkWell(
                    onTap: onReplyTap,
                    borderRadius: BorderRadius.circular(999),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.reply_rounded,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Responder',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyCommentsCard extends StatelessWidget {
  const _EmptyCommentsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
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
            'Nenhum comentário ainda.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.95),
              fontSize: 14,
              height: 1.4,
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

  void _openFullscreenGallery(int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenImageGallery(
          urls: widget.urls,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.length == 1) {
      return GestureDetector(
        onTap: () => _openFullscreenGallery(0),
        child: ClipRRect(
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
              onPageChanged: (index) => setState(() => _page = index),
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => _openFullscreenGallery(index),
                child: Image.network(
                  widget.urls[index],
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
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.urls.length,
            (index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index == _page ? AppColors.primary : AppColors.border,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FullscreenImageGallery extends StatefulWidget {
  const _FullscreenImageGallery({
    required this.urls,
    required this.initialIndex,
  });

  final List<String> urls;
  final int initialIndex;

  @override
  State<_FullscreenImageGallery> createState() =>
      _FullscreenImageGalleryState();
}

class _FullscreenImageGalleryState extends State<_FullscreenImageGallery> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('${_currentIndex + 1}/${widget.urls.length}'),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.urls.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Image.network(
                    widget.urls[index],
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 56,
                        color: Colors.white70,
                      ),
                    ),
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    },
                  ),
                ),
              );
            },
          ),
          if (widget.urls.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.urls.length,
                  (index) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: _currentIndex == index ? 18 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentIndex == index
                            ? Colors.white
                            : Colors.white38,
                        borderRadius: BorderRadius.circular(999),
                      ),
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
