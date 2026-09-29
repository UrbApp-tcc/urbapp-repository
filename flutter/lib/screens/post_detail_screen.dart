import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logic/app_rules.dart';
import '../services/feed_service.dart';
import '../services/moderation_service.dart';
import '../services/post_service.dart';
import '../services/resolution_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_formatter.dart';
import '../utils/date_formatter.dart';
import '../theme/urbapp_design.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/urb_dialog.dart';
import '../widgets/urb_primary_button.dart';
import '../widgets/urb_status_chip.dart';
import 'profile_screen.dart';
import 'resolve_complaint_screen.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.post});

  final FeedPost post;

  static Future<bool?> open(BuildContext context, FeedPost post) {
    final duration = UrbMotion.of(context, const Duration(milliseconds: 280));
    return Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        opaque: false,
        barrierColor: const Color(0x940D1520),
        barrierLabel: 'Fechar',
        transitionDuration: duration,
        reverseTransitionDuration: duration,
        pageBuilder: (_, _, _) => PostDetailScreen(post: post),
        // A janela "cresce" de leve ao abrir.
        transitionsBuilder: (context, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween(begin: 0.94, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _supabase = Supabase.instance.client;
  final _postService = PostService();
  final _moderationService = ModerationService();
  final _commentController = TextEditingController();

  late int _supportsCount;
  late int _commentsCount;

  bool _isLiked = false;
  bool _isLikeLoading = true;
  bool _isCommentsLoading = true;
  bool _isSubmittingComment = false;
  bool _isResolvingAddress = true;
  bool _isSubmittingReport = false;
  bool _hasStatusChanges = false;

  int? _replyParentCommentId;
  String? _replyTargetLabel;

  String? _resolvedStreet;
  String? _resolvedNeighborhood;
  List<PostComment> _comments = const [];

  final _resolutionService = ResolutionService();

  /// Pedido de validação pendente (null = nenhum).
  ResolutionStatus? _resolution;
  bool _isVoting = false;

  /// Status atualizado nesta tela (ex.: depois da validação concluir).
  String? _statusOverride;

  String get _status => _statusOverride ?? widget.post.status;

  @override
  void initState() {
    super.initState();
    _loadResolution();
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
        postStatus: _status,
      );

      if (!mounted) return;
      setState(() {
        _isLiked = newLikedState;
        _supportsCount = newLikedState
            ? _supportsCount + 1
            : (_supportsCount - 1).clamp(0, 999999);
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

    if (isFinalStatus(_status)) return;

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
    final storedStreet = widget.post.street?.trim();
    final storedNeighborhood = widget.post.neighborhood?.trim();
    if ((storedStreet != null && storedStreet.isNotEmpty) ||
        (storedNeighborhood != null && storedNeighborhood.isNotEmpty)) {
      setState(() {
        _resolvedStreet = storedStreet;
        _resolvedNeighborhood = storedNeighborhood;
        _isResolvingAddress = false;
      });
      return;
    }

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
    showUrbSnack(context, successMessage);
  }

  void _showLocationMap() {
    final point = LatLng(widget.post.latitude, widget.post.longitude);

    showUrbDialog<void>(
      context: context,
      builder: (dialogContext) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UrbDialogHeader(
              icon: Icons.location_on_outlined,
              title: 'Localização do reporte',
              subtitle: _addressDisplayLabel,
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 300,
                child: FlutterMap(
                  options: MapOptions(initialCenter: point, initialZoom: 16),
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
                          width: 48,
                          height: 48,
                          child: const Icon(
                            Icons.location_pin,
                            size: 46,
                            color: UrbColors.violet,
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
  }

  void _showShareOptions() {
    final link = _buildShareLink();
    final message = _buildShareMessage(link);

    showUrbDialog<void>(
      context: context,
      builder: (dialogContext) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UrbDialogHeader(
              icon: Icons.ios_share_rounded,
              title: 'Compartilhar reporte',
              subtitle: 'Ajude este reporte a ganhar apoio.',
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
            const SizedBox(height: 18),
            _ShareOption(
              icon: Icons.link_rounded,
              title: 'Copiar link',
              subtitle: 'Cole onde quiser: WhatsApp, Instagram...',
              onTap: () async {
                Navigator.of(dialogContext).pop();
                await _copyToClipboard(
                  link,
                  'Link copiado para a área de transferência.',
                );
              },
            ),
            const SizedBox(height: 10),
            _ShareOption(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Copiar mensagem para compartilhar',
              subtitle: 'Copia uma mensagem pronta com o link do reporte.',
              onTap: () async {
                Navigator.of(dialogContext).pop();
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
  }

  Future<void> _showReportPostSheet() async {
    final draft = await showUrbDialog<_PostReportDraft>(
      context: context,
      builder: (_) => const _ReportPostSheet(),
    );

    if (draft == null || _isSubmittingReport) return;

    setState(() => _isSubmittingReport = true);
    try {
      await _moderationService.reportPost(
        postId: widget.post.id,
        reason: draft.reason,
        details: draft.details,
      );

      if (!mounted) return;
      showUrbSnack(
        context,
        'Denúncia enviada. Nossa equipe poderá analisar este reporte.',
      );
    } catch (error) {
      if (!mounted) return;
      showUrbSnack(context, friendlyError(error), error: true);
    } finally {
      if (mounted) {
        setState(() => _isSubmittingReport = false);
      }
    }
  }

  void _openProfile(String userId) {
    ProfileScreen.open(
      context,
      profileUserId: userId,
      currentUserId: _supabase.auth.currentUser?.id,
    );
  }

  Future<void> _loadResolution() async {
    try {
      final status = await _resolutionService.fetchStatus(widget.post.id);
      if (mounted) setState(() => _resolution = status);
    } catch (_) {
      // Sem a validação o restante da tela continua funcionando.
    }
  }

  Future<void> _openResolveComplaint() async {
    final requested = await ResolveComplaintScreen.open(context, widget.post);
    if (!mounted || requested != true) return;

    setState(() => _hasStatusChanges = true);
    await _loadResolution();
    if (!mounted) return;
    showUrbSnack(
      context,
      'Pedido enviado! Agora os vizinhos confirmam a resolução.',
    );
  }

  /// Pergunta "Foi resolvido mesmo?", pega a localização e envia o voto.
  Future<void> _openValidation() async {
    final resolution = _resolution;
    if (resolution == null || _isVoting) return;

    final confirmed = await showUrbDialog<bool>(
      context: context,
      builder: (_) =>
          _ValidateDialog(post: widget.post, resolution: resolution),
    );
    if (confirmed == null || !mounted) return;

    setState(() => _isVoting = true);
    try {
      final position = await _currentPosition();
      final result = await _resolutionService.vote(
        postId: widget.post.id,
        confirmed: confirmed,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted) return;

      if (result.result == 'approved') {
        setState(() {
          _statusOverride = 'completed';
          _resolution = null;
          _hasStatusChanges = true;
        });
        showUrbSnack(
          context,
          'Obrigado! O reporte foi confirmado como resolvido. +10 XP',
        );
      } else if (result.result == 'rejected') {
        setState(() => _resolution = null);
        showUrbSnack(
          context,
          'Obrigado! O pedido foi cancelado e o reporte segue aberto. +10 XP',
        );
      } else {
        await _loadResolution();
        if (!mounted) return;
        showUrbSnack(context, 'Obrigado por ajudar a validar! +10 XP');
      }
    } catch (error) {
      if (!mounted) return;
      showUrbSnack(context, friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _isVoting = false);
    }
  }

  Future<Position> _currentPosition() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception(
        'Precisamos da sua localização para confirmar que você está perto do local.',
      );
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
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

  void _popWithChanges() {
    final hasChanges =
        _hasStatusChanges ||
        _supportsCount != widget.post.supportsCount ||
        _commentsCount != widget.post.commentsCount;
    Navigator.of(context).pop(hasChanges);
  }

  @override
  Widget build(BuildContext context) {
    final imageUrls = _orderedImageUrls(widget.post);
    final currentUserId = _supabase.auth.currentUser?.id;
    final canResolve =
        currentUserId != null &&
        widget.post.authorId == currentUserId &&
        !isFinalStatus(_status) &&
        _resolution == null;
    final isCompleted = _status == 'completed';
    final canReport =
        currentUserId != null && widget.post.authorId != currentUserId;
    final canComment = !isFinalStatus(_status);
    final isAuthor =
        currentUserId != null && widget.post.authorId == currentUserId;
    final agency = widget.post.agencyName?.trim();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _popWithChanges();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Tocar fora da janela fecha o reporte.
            Positioned.fill(
              child: GestureDetector(
                onTap: _popWithChanges,
                behavior: HitTestBehavior.opaque,
              ),
            ),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: SizedBox(
                      height: double.infinity,
                      child: Material(
                        color: UrbColors.surface,
                        borderRadius: BorderRadius.circular(30),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            _HeaderGallery(
                              urls: imageUrls,
                              onClose: _popWithChanges,
                              onShare: _showShareOptions,
                              onReport: canReport && !_isSubmittingReport
                                  ? _showReportPostSheet
                                  : null,
                            ),
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  18,
                                  18,
                                  24,
                                ),
                                children: [
                                  FadeSlideIn(
                                    offsetY: 14,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _AuthorHeader(
                                                post: widget.post,
                                                onTap:
                                                    widget.post.authorId ==
                                                            null ||
                                                        widget.post.isAnonymous
                                                    ? null
                                                    : () => _openProfile(
                                                        widget.post.authorId!,
                                                      ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            UrbStatusChip(status: _status),
                                          ],
                                        ),
                                        const SizedBox(height: 18),
                                        Text(
                                          widget.post.title,
                                          textAlign: TextAlign.center,
                                          style: UrbText.display(
                                            size: 26,
                                            weight: FontWeight.w700,
                                          ),
                                        ),
                                        if (widget.post.description
                                            .trim()
                                            .isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          Text(
                                            widget.post.description,
                                            textAlign: TextAlign.center,
                                            style: UrbText.body(
                                              size: 15,
                                              color: const Color(0xFF374151),
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 16),
                                        Wrap(
                                          alignment: WrapAlignment.center,
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            _MetaChip(
                                              icon: Icons.sell_outlined,
                                              label: widget.post.categoryName,
                                            ),
                                            _MetaChip(
                                              icon:
                                                  Icons.location_city_outlined,
                                              label: widget.post.cityName,
                                            ),
                                            if (agency != null &&
                                                agency.isNotEmpty)
                                              _MetaChip(
                                                icon: Icons
                                                    .account_balance_outlined,
                                                label: agency,
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Icon(
                                              Icons.schedule_rounded,
                                              size: 14,
                                              color: UrbColors.textMuted,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              _formatPublishedAt(
                                                widget.post.createdAt,
                                              ),
                                              style: UrbText.body(
                                                size: 13,
                                                color: UrbColors.textMuted,
                                                height: 1.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isCompleted) ...[
                                    const SizedBox(height: 16),
                                    _CompletedNotice(
                                      resolvedAt: widget.post.resolvedAt,
                                    ),
                                  ],
                                  const SizedBox(height: 18),
                                  FadeSlideIn(
                                    delay: const Duration(milliseconds: 80),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: _ActionButton(
                                            icon: _isLiked
                                                ? Icons.favorite_rounded
                                                : Icons.favorite_border_rounded,
                                            label: '$_supportsCount',
                                            semanticLabel: _isLiked
                                                ? 'Tirar apoio'
                                                : 'Apoiar',
                                            color: UrbColors.heart,
                                            highlighted: _isLiked,
                                            loading: _isLikeLoading,
                                            onTap: _isLikeLoading
                                                ? null
                                                : _toggleLike,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _ActionButton(
                                            icon: Icons
                                                .chat_bubble_outline_rounded,
                                            label: '$_commentsCount',
                                            semanticLabel: 'Comentários',
                                            color: UrbColors.commentBlue,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _ActionButton(
                                            icon: Icons.ios_share_rounded,
                                            label: 'Enviar',
                                            semanticLabel: 'Compartilhar',
                                            color: UrbColors.violetDeep,
                                            onTap: _showShareOptions,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_resolution != null &&
                                      !isFinalStatus(_status)) ...[
                                    const SizedBox(height: 16),
                                    _ValidationCard(
                                      resolution: _resolution!,
                                      isAuthor: isAuthor,
                                      isVoting: _isVoting,
                                      onValidate: _openValidation,
                                    ),
                                  ],
                                  if (canResolve) ...[
                                    const SizedBox(height: 16),
                                    _ResolveComplaintCard(
                                      onTap: _openResolveComplaint,
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  _AddressCard(
                                    isLoading: _isResolvingAddress,
                                    address: _addressDisplayLabel,
                                    onTap: _showLocationMap,
                                  ),
                                  const SizedBox(height: 22),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Comentários',
                                          style: UrbText.display(
                                            size: 18,
                                            weight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: UrbColors.lavender,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          '$_commentsCount',
                                          style: UrbText.body(
                                            size: 13,
                                            weight: FontWeight.w700,
                                            color: UrbColors.violetDeep,
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (_isCommentsLoading)
                                    const Center(
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 32,
                                        ),
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  else if (_comments.isEmpty)
                                    const _EmptyCommentsCard()
                                  else
                                    ..._comments.map(
                                      (comment) => _CommentThread(
                                        comment: comment,
                                        onLikeTap: () =>
                                            _toggleCommentLike(comment),
                                        onReplyTap: () => _beginReply(comment),
                                        onReplyLikeTap: _toggleCommentLike,
                                        onReplyReplyTap: _beginReply,
                                        onOpenProfile: _openProfile,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Campo de comentário fixo no rodapé da janela.
                            if (canComment)
                              Container(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  10,
                                  14,
                                  12,
                                ),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  border: Border(
                                    top: BorderSide(color: UrbColors.border),
                                  ),
                                ),
                                child: _CommentComposer(
                                  controller: _commentController,
                                  isSubmitting: _isSubmittingComment,
                                  onSubmit: _submitComment,
                                  replyTargetLabel: _replyTargetLabel,
                                  onCancelReply: _replyParentCommentId == null
                                      ? null
                                      : _cancelReply,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: UrbColors.lavender,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(13),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.location_on_outlined,
                        color: UrbColors.violetDeep,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: UrbMotion.of(context, UrbMotion.fast),
                      child: Text(
                        address,
                        key: ValueKey(address),
                        style: UrbText.body(
                          size: 15,
                          weight: FontWeight.w700,
                          color: UrbColors.ink,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Toque para abrir no mapa',
                      style: UrbText.body(
                        size: 12,
                        color: UrbColors.textMuted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: UrbColors.textMuted,
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
      color: const Color(0xFFECFDF5),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFA7F3D0), width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF34D399), Color(0xFF059669)],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.task_alt_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resolver reclamação',
                      style: UrbText.body(
                        size: 15,
                        weight: FontWeight.w700,
                        color: const Color(0xFF065F46),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Informe a solução e marque este reporte como concluído.',
                      style: UrbText.body(
                        size: 12,
                        color: const Color(0xFF047857),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF059669)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botão grande da linha de ações (apoiar, comentários, compartilhar).
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.color,
    this.onTap,
    this.highlighted = false,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final Color color;
  final VoidCallback? onTap;
  final bool highlighted;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      child: Material(
        color: highlighted ? const Color(0xFFFDE8F0) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  // O coração "pula" quando o apoio muda.
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
                    child: Icon(
                      icon,
                      key: ValueKey(icon),
                      size: 21,
                      color: color,
                    ),
                  ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: UrbText.body(
                    size: 15,
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
        ),
      ),
    );
  }
}

class _ShareOption extends StatelessWidget {
  const _ShareOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: UrbColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: UrbColors.lavender,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: UrbColors.violetDeep),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: UrbText.body(
                        size: 15,
                        weight: FontWeight.w700,
                        color: UrbColors.ink,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: UrbText.body(size: 13, height: 1.35)),
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
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: UrbColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: UrbColors.violet),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: UrbText.body(
                size: 13,
                weight: FontWeight.w600,
                color: const Color(0xFF374151),
                height: 1.2,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: UrbMotion.of(context, UrbMotion.fast),
          child: replyTargetLabel == null
              ? const SizedBox(width: double.infinity)
              : Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    color: UrbColors.lavender,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Respondendo $replyTargetLabel',
                          style: UrbText.body(
                            size: 13,
                            weight: FontWeight.w700,
                            color: UrbColors.violetDeep,
                            height: 1.3,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancelar resposta',
                        onPressed: onCancelReply,
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: UrbColors.violetDeep,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                style: UrbText.body(
                  size: 15,
                  color: UrbColors.ink,
                  height: 1.35,
                ),
                decoration: InputDecoration(
                  hintText: replyTargetLabel == null
                      ? 'Adicione um comentário ao reporte'
                      : 'Escreva sua resposta',
                  hintStyle: UrbText.body(
                    size: 14,
                    color: UrbColors.textMuted,
                    height: 1.35,
                  ),
                  filled: true,
                  fillColor: UrbColors.surface,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: UrbColors.border,
                      width: 1.5,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: UrbColors.border,
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: UrbColors.violet,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: replyTargetLabel == null ? 'Comentar' : 'Responder',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: UrbGradients.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: isSubmitting ? null : onSubmit,
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
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
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: UrbColors.lavender,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              color: UrbColors.violetDeep,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Nenhum comentário ainda',
            textAlign: TextAlign.center,
            style: UrbText.body(
              size: 15,
              weight: FontWeight.w700,
              color: UrbColors.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Seja o primeiro a comentar este reporte.',
            textAlign: TextAlign.center,
            style: UrbText.body(size: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _PostReportDraft {
  const _PostReportDraft({required this.reason, required this.details});

  final String reason;
  final String details;
}

class _ReportPostSheet extends StatefulWidget {
  const _ReportPostSheet();

  @override
  State<_ReportPostSheet> createState() => _ReportPostSheetState();
}

class _ReportPostSheetState extends State<_ReportPostSheet> {
  static const _reasons = [
    'Conteúdo ofensivo',
    'Informação falsa',
    'Spam ou publicidade',
    'Localização incorreta',
    'Outro motivo',
  ];

  final _detailsController = TextEditingController();
  String? _selectedReason;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _selectedReason;
    if (reason == null) return;

    Navigator.of(context).pop(
      _PostReportDraft(reason: reason, details: _detailsController.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UrbDialogHeader(
            icon: Icons.flag_outlined,
            title: 'Denunciar reporte',
            subtitle: 'Conte o que há de errado com este reporte.',
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 18),
          for (final reason in _reasons) ...[
            _ReasonOption(
              label: reason,
              selected: _selectedReason == reason,
              onTap: () => setState(() => _selectedReason = reason),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 6),
          TextField(
            controller: _detailsController,
            minLines: 2,
            maxLines: 4,
            style: UrbText.body(size: 15, color: UrbColors.ink, height: 1.35),
            decoration: InputDecoration(
              hintText: 'Detalhes (opcional)',
              hintStyle: UrbText.body(
                size: 14,
                color: UrbColors.textMuted,
                height: 1.35,
              ),
              filled: true,
              fillColor: UrbColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: UrbColors.border,
                  width: 1.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: UrbColors.border,
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: UrbColors.violet, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: UrbSecondaryButton(
                  label: 'Cancelar',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: UrbPrimaryButton(
                  label: 'Enviar',
                  onPressed: _selectedReason == null ? null : _submit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReasonOption extends StatelessWidget {
  const _ReasonOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: UrbMotion.of(context, UrbMotion.fast),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? UrbColors.lavender : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? UrbColors.violet.withValues(alpha: 0.45)
                  : UrbColors.border,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: UrbText.body(
                    size: 15,
                    weight: FontWeight.w700,
                    color: selected ? UrbColors.violetDeep : UrbColors.ink,
                    height: 1.2,
                  ),
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? UrbColors.violetDeep : UrbColors.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderGallery extends StatefulWidget {
  const _HeaderGallery({
    required this.urls,
    required this.onClose,
    required this.onShare,
    required this.onReport,
  });

  final List<String> urls;
  final VoidCallback onClose;
  final VoidCallback onShare;
  final VoidCallback? onReport;

  @override
  State<_HeaderGallery> createState() => _HeaderGalleryState();
}

class _HeaderGalleryState extends State<_HeaderGallery> {
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

  Widget _glass(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0x660D1520),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: Colors.white, size: 19),
          ),
        ),
      ),
    );
  }

  Widget _image(String url) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, loadedSync) {
        if (loadedSync) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: UrbMotion.of(context, UrbMotion.medium),
          child: child,
        );
      },
      errorBuilder: (_, _, _) => const _PhotoPlaceholder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    final hasPhotos = urls.isNotEmpty;

    return SizedBox(
      height: hasPhotos ? 240 : 150,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!hasPhotos)
            const _PhotoPlaceholder()
          else if (urls.length == 1)
            GestureDetector(
              onTap: () => _openFullscreenGallery(0),
              child: _image(urls.first),
            )
          else
            PageView.builder(
              itemCount: urls.length,
              onPageChanged: (index) => setState(() => _page = index),
              itemBuilder: (context, index) => GestureDetector(
                onTap: () => _openFullscreenGallery(index),
                child: _image(urls[index]),
              ),
            ),
          // Escurece o topo para os botões ficarem visíveis sobre a foto.
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x800D1520), Color(0x000D1520)],
                  stops: [0, 0.45],
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: Row(
              children: [
                _glass(Icons.ios_share_rounded, 'Compartilhar', widget.onShare),
                if (widget.onReport != null) ...[
                  const SizedBox(width: 8),
                  _glass(
                    Icons.flag_outlined,
                    'Denunciar reporte',
                    widget.onReport!,
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: _glass(Icons.close_rounded, 'Fechar', widget.onClose),
          ),
          if (urls.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  urls.length,
                  (index) => AnimatedContainer(
                    duration: UrbMotion.of(context, UrbMotion.fast),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: index == _page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: index == _page
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(3),
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

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(gradient: UrbGradients.photo),
      child: Center(
        child: Icon(Icons.image_outlined, color: Color(0xFF9FB0C6), size: 36),
      ),
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

// ──────────────────────────────────────────────────────────
// Validação comunitária
// ──────────────────────────────────────────────────────────

class _ValidationCard extends StatelessWidget {
  const _ValidationCard({
    required this.resolution,
    required this.isAuthor,
    required this.isVoting,
    required this.onValidate,
  });

  final ResolutionStatus resolution;
  final bool isAuthor;
  final bool isVoting;
  final VoidCallback onValidate;

  @override
  Widget build(BuildContext context) {
    final alreadyVoted = resolution.myVote != null;
    final daysLeft = resolution.expiresAt.difference(DateTime.now()).inDays;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFA7F3D0), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF34D399), Color(0xFF059669)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aguardando validação',
                      style: UrbText.body(
                        size: 15,
                        weight: FontWeight.w700,
                        color: const Color(0xFF065F46),
                        height: 1.3,
                      ),
                    ),
                    Text(
                      daysLeft > 0
                          ? 'Faltam $daysLeft dias para encerrar'
                          : 'Encerra em breve',
                      style: UrbText.body(
                        size: 12,
                        color: const Color(0xFF047857),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '"${resolution.note}"',
            textAlign: TextAlign.center,
            style: UrbText.body(
              size: 14,
              color: const Color(0xFF065F46),
              height: 1.45,
            ).copyWith(fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 14),
          _ConfirmationsBar(
            confirmations: resolution.confirmations,
            needed: resolution.needed,
          ),
          const SizedBox(height: 14),
          if (isAuthor)
            Text(
              'Os vizinhos a até ${resolution.radiusMeters} m do local estão sendo convidados a confirmar.',
              textAlign: TextAlign.center,
              style: UrbText.body(
                size: 13,
                color: const Color(0xFF047857),
                height: 1.4,
              ),
            )
          else if (alreadyVoted)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF059669),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  resolution.myVote!
                      ? 'Você confirmou a resolução'
                      : 'Você disse que ainda não foi resolvido',
                  style: UrbText.body(
                    size: 13,
                    weight: FontWeight.w700,
                    color: const Color(0xFF047857),
                    height: 1.3,
                  ),
                ),
              ],
            )
          else
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: isVoting ? null : onValidate,
                icon: isVoting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.how_to_vote_outlined),
                label: Text(
                  'Ajudar a validar · +10 XP',
                  style: UrbText.body(
                    size: 15,
                    weight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Barra com as confirmações: cada parte "acende" quando alguém confirma.
class _ConfirmationsBar extends StatelessWidget {
  const _ConfirmationsBar({required this.confirmations, required this.needed});

  final int confirmations;
  final int needed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < needed; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: i < confirmations ? 1 : 0),
                  duration: UrbMotion.of(
                    context,
                    Duration(milliseconds: 400 + 150 * i),
                  ),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        const Color(0xFFD1FAE5),
                        const Color(0xFF10B981),
                        value,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '$confirmations de $needed confirmações',
          style: UrbText.body(
            size: 12,
            weight: FontWeight.w700,
            color: const Color(0xFF065F46),
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

/// Janela "Foi resolvido mesmo?" (retorna true = sim, false = ainda não).
class _ValidateDialog extends StatelessWidget {
  const _ValidateDialog({required this.post, required this.resolution});

  final FeedPost post;
  final ResolutionStatus resolution;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF34D399), Color(0xFF059669)],
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x59059669),
                    blurRadius: 24,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: const Icon(
                Icons.verified_user_outlined,
                color: Colors.white,
                size: 38,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Foi resolvido mesmo?',
            textAlign: TextAlign.center,
            style: UrbText.display(size: 24, weight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'O autor disse que "${post.title}" foi resolvido. Se você está perto do local, confirme se o problema acabou.',
            textAlign: TextAlign.center,
            style: UrbText.body(size: 15, height: 1.45),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: UrbColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '"${resolution.note}"',
              textAlign: TextAlign.center,
              style: UrbText.body(
                size: 14,
                color: UrbColors.ink,
                height: 1.4,
              ).copyWith(fontStyle: FontStyle.italic),
            ),
          ),
          const SizedBox(height: 14),
          _ConfirmationsBar(
            confirmations: resolution.confirmations,
            needed: resolution.needed,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: UrbSecondaryButton(
                  label: 'Ainda não',
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.check_rounded),
                    label: Text(
                      'Sim, resolvido',
                      style: UrbText.body(
                        size: 15,
                        weight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Vamos usar sua localização para conferir que você está a até ${resolution.radiusMeters} m do local.',
            textAlign: TextAlign.center,
            style: UrbText.body(
              size: 12,
              color: UrbColors.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
