import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../logic/app_rules.dart';
import '../services/feed_service.dart';
import '../services/institutional_service.dart';
import '../services/moderation_service.dart';
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
  final _institutionalService = InstitutionalService();
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
  bool _isOccurrenceLoading = true;
  bool _isVoting = false;
  bool _isFollowingLoading = false;
  bool _isReopening = false;
  bool _isInstitutionalActionLoading = false;

  late String _currentStatus;
  ResolutionCycleInfo? _activeResolutionCycle;
  OccurrenceEngagementContext? _occurrenceEngagement;
  OccurrenceActorCapabilities? _actorCapabilities;
  List<OccurrenceTimelineEvent> _timeline = const [];

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
    _currentStatus = widget.post.status;
    _loadLikeStatus();
    _loadComments();
    _loadAddress();
    _loadOccurrenceContext();
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
        postStatus: _currentStatus,
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

    if (isFinalStatus(_currentStatus)) return;

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
      enableDrag: false,
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

  Future<void> _showReportPostSheet() async {
    final draft = await showModalBottomSheet<_PostReportDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => const _ReportPostSheet(),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Denúncia enviada. Nossa equipe poderá analisar este reporte.',
          ),
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

  Future<void> _openResolveComplaint() async {
    final resolved = await ResolveComplaintScreen.open(context, widget.post);
    if (!mounted || resolved != true) return;

    setState(() {
      _hasStatusChanges = true;
      _currentStatus = 'awaiting_validation';
    });
    await _loadOccurrenceContext();
  }

  Future<void> _loadOccurrenceContext() async {
    try {
      final results = await Future.wait<dynamic>([
        _postService.fetchActiveResolutionCycle(widget.post.id),
        _postService.fetchOccurrenceTimeline(widget.post.id),
        _postService.fetchOccurrenceEngagement(widget.post.id),
        if (_supabase.auth.currentUser != null)
          _institutionalService.fetchCapabilitiesForPost(widget.post.id)
        else
          Future<OccurrenceActorCapabilities?>.value(null),
      ]);
      final cycle = results[0] as ResolutionCycleInfo?;
      final timeline = results[1] as List<OccurrenceTimelineEvent>;
      final engagement = results[2] as OccurrenceEngagementContext?;
      final actorCapabilities = results[3] as OccurrenceActorCapabilities?;
      if (!mounted) return;
      setState(() {
        _activeResolutionCycle = cycle;
        _timeline = timeline;
        _occurrenceEngagement = engagement;
        _actorCapabilities = actorCapabilities;
        _isOccurrenceLoading = false;
        if (cycle != null) _currentStatus = 'awaiting_validation';
      });
    } catch (_) {
      if (mounted) setState(() => _isOccurrenceLoading = false);
    }
  }

  Future<void> _handleInstitutionalAction() async {
    final capabilities = _actorCapabilities;
    if (capabilities == null || _isInstitutionalActionLoading) return;

    if (capabilities.isEligibleCouncilor &&
        !capabilities.hasActiveCouncilorFollowing &&
        !capabilities.canActForAdministration &&
        !capabilities.canActForAgency) {
      setState(() => _isInstitutionalActionLoading = true);
      try {
        await _institutionalService.startCouncilorFollowing(
          capabilities.occurrenceId,
        );
        await _loadOccurrenceContext();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Acompanhamento público iniciado.'),
            backgroundColor: AppColors.resolved,
          ),
        );
      } catch (error) {
        _showActionError(error);
      } finally {
        if (mounted) setState(() => _isInstitutionalActionLoading = false);
      }
      return;
    }

    final asCouncilor =
        capabilities.isEligibleCouncilor &&
        capabilities.hasActiveCouncilorFollowing &&
        !capabilities.canActForAdministration &&
        !capabilities.canActForAgency;
    List<InstitutionalAgencyOption> agencies = const [];
    if (!asCouncilor && capabilities.canActForAdministration) {
      try {
        agencies = await _institutionalService.fetchAgenciesForCity(
          capabilities.cityId,
        );
      } catch (error) {
        _showActionError(error);
        return;
      }
    }
    if (!mounted) return;
    final draft = await showModalBottomSheet<_ActorActionDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _ActorActionSheet(
        asCouncilor: asCouncilor,
        canActForAdministration: capabilities.canActForAdministration,
        agencies: agencies,
        currentAgencyId: capabilities.agencyId,
      ),
    );
    if (draft == null) return;

    setState(() => _isInstitutionalActionLoading = true);
    String? evidencePath;
    try {
      evidencePath = draft.evidence == null
          ? null
          : await _institutionalService.uploadActionEvidence(
              occurrenceId: capabilities.occurrenceId,
              file: draft.evidence!,
            );
      if (asCouncilor) {
        if (draft.actionType == 'end_following') {
          await _institutionalService.endCouncilorFollowing(
            followingId: capabilities.councilorFollowingId!,
            description: draft.description,
          );
        } else {
          await _institutionalService.registerCouncilorAction(
            followingId: capabilities.councilorFollowingId!,
            actionType: draft.actionType,
            description: draft.description,
            evidenceStoragePath: evidencePath,
          );
        }
      } else {
        await _institutionalService.registerInstitutionalAction(
          occurrenceId: capabilities.occurrenceId,
          actionType: draft.actionType,
          description: draft.description,
          targetAgencyId: draft.targetAgencyId,
          forecastAt: draft.forecastAt,
          evidenceStoragePath: evidencePath,
        );
      }
      await _loadOccurrenceContext();
      if (!mounted) return;
      setState(() => _hasStatusChanges = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ação registrada na linha do tempo pública.'),
          backgroundColor: AppColors.resolved,
        ),
      );
    } catch (error) {
      if (evidencePath != null) {
        await _institutionalService.deleteActionEvidence(evidencePath);
      }
      _showActionError(error);
    } finally {
      if (mounted) setState(() => _isInstitutionalActionLoading = false);
    }
  }

  void _showActionError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(friendlyError(error)),
        backgroundColor: AppColors.error,
      ),
    );
  }

  Future<void> _toggleOccurrenceFollowing() async {
    final engagement = _occurrenceEngagement;
    if (engagement == null || _isFollowingLoading) return;

    setState(() => _isFollowingLoading = true);
    try {
      final following = await _postService.toggleOccurrenceFollowing(
        occurrenceId: engagement.occurrenceId,
        isFollowing: engagement.isFollowing,
      );
      if (!mounted) return;
      setState(() {
        _occurrenceEngagement = OccurrenceEngagementContext(
          occurrenceId: engagement.occurrenceId,
          isFollowing: following,
          reportsCount: engagement.reportsCount,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            following
                ? 'Você receberá atualizações desta ocorrência.'
                : 'Acompanhamento removido.',
          ),
          backgroundColor: AppColors.primary,
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
      if (mounted) setState(() => _isFollowingLoading = false);
    }
  }

  Future<void> _openReopeningFlow() async {
    final engagement = _occurrenceEngagement;
    if (engagement == null || _isReopening) return;

    final draft = await showModalBottomSheet<_ReopeningDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _ReopenOccurrenceSheet(),
    );
    if (draft == null) return;

    setState(() => _isReopening = true);
    try {
      final evidencePath = await _postService.uploadReopeningEvidence(
        occurrenceId: engagement.occurrenceId,
        file: draft.evidence,
      );
      await _postService.reopenOccurrence(
        occurrenceId: engagement.occurrenceId,
        description: draft.description,
        evidenceStoragePath: evidencePath,
      );
      if (!mounted) return;
      setState(() {
        _currentStatus = 'reopened';
        _hasStatusChanges = true;
      });
      await _loadOccurrenceContext();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ocorrência reaberta com a nova evidência.'),
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
      if (mounted) setState(() => _isReopening = false);
    }
  }

  Future<void> _voteResolution(bool confirm) async {
    final cycle = _activeResolutionCycle;
    if (cycle == null || _isVoting) return;

    setState(() => _isVoting = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception(
          'A localizacao e necessaria para comprovar que voce esta proximo da ocorrencia.',
        );
      }

      final position = await Geolocator.getCurrentPosition();
      final result = await _postService.voteResolution(
        cycleId: cycle.id,
        confirm: confirm,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      final refreshedPost = await FeedService().fetchPostById(widget.post.id);
      if (!mounted) return;
      setState(() {
        _hasStatusChanges = true;
        if (refreshedPost != null) _currentStatus = refreshedPost.status;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.cycleStatus == 'approved'
                ? 'A comunidade confirmou a resolucao.'
                : result.cycleStatus == 'rejected'
                ? 'A validacao foi rejeitada e a ocorrencia voltou ao status anterior.'
                : 'Voto registrado: ${result.confirmations}/${result.confirmationsRequired} confirmacoes.',
          ),
          backgroundColor: AppColors.primary,
        ),
      );
      await _loadOccurrenceContext();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error)),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isVoting = false);
    }
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
        currentUserId != null && canStartResolutionValidation(_currentStatus);
    final isCompleted = _currentStatus == 'completed';
    final canUseCouncilorTools =
        _actorCapabilities?.isEligibleCouncilor == true &&
        (_actorCapabilities!.hasActiveCouncilorFollowing ||
            !isFinalStatus(_currentStatus));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _popWithChanges();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _popWithChanges,
          ),
          title: const Text('Reporte'),
          actions: [
            if (currentUserId != null && widget.post.authorId != currentUserId)
              IconButton(
                tooltip: 'Denunciar reporte',
                onPressed: _isSubmittingReport ? null : _showReportPostSheet,
                icon: const Icon(Icons.flag_outlined),
              ),
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
                  label: _statusLabel(_currentStatus),
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
            if (_occurrenceEngagement != null) ...[
              _OccurrenceActionsCard(
                engagement: _occurrenceEngagement!,
                isFollowingLoading: _isFollowingLoading,
                isReopening: _isReopening,
                canReopen: isCompleted && currentUserId != null,
                onToggleFollowing: currentUserId == null
                    ? null
                    : _toggleOccurrenceFollowing,
                onReopen: _openReopeningFlow,
              ),
              const SizedBox(height: 20),
            ],
            if (_actorCapabilities != null &&
                (_actorCapabilities!.canActForAdministration ||
                    _actorCapabilities!.canActForAgency ||
                    canUseCouncilorTools)) ...[
              _InstitutionalActionCard(
                capabilities: _actorCapabilities!,
                isLoading: _isInstitutionalActionLoading,
                onTap: _handleInstitutionalAction,
              ),
              const SizedBox(height: 20),
            ],
            if (canResolve) ...[
              _ResolveComplaintCard(onTap: _openResolveComplaint),
              const SizedBox(height: 20),
            ],
            if (_isOccurrenceLoading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 20),
            ] else if (_activeResolutionCycle != null) ...[
              _ValidationCard(
                cycle: _activeResolutionCycle!,
                currentUserId: currentUserId,
                isVoting: _isVoting,
                onConfirm: () => _voteResolution(true),
                onReject: () => _voteResolution(false),
              ),
              const SizedBox(height: 20),
            ],
            if (_timeline.isNotEmpty) ...[
              _TimelineCard(events: _timeline),
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
            if (!isFinalStatus(_currentStatus))
              _CommentComposer(
                controller: _commentController,
                isSubmitting: _isSubmittingComment,
                onSubmit: _submitComment,
                replyTargetLabel: _replyTargetLabel,
                onCancelReply: _replyParentCommentId == null
                    ? null
                    : _cancelReply,
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
        return 'Resolvido';
      case 'awaiting_validation':
        return 'Aguardando validação';
      case 'reopened':
        return 'Reaberto';
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

class _InstitutionalActionCard extends StatelessWidget {
  const _InstitutionalActionCard({
    required this.capabilities,
    required this.isLoading,
    required this.onTap,
  });

  final OccurrenceActorCapabilities capabilities;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final startsCouncilorFollowing =
        capabilities.isEligibleCouncilor &&
        !capabilities.hasActiveCouncilorFollowing &&
        !capabilities.canActForAdministration &&
        !capabilities.canActForAgency;
    final label = startsCouncilorFollowing
        ? 'Acompanhar como vereador'
        : capabilities.canActForAdministration
        ? 'Registrar ação da gestão'
        : capabilities.canActForAgency
        ? 'Registrar ação do órgão'
        : 'Registrar atuação do vereador';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0DDA8)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.verified_user_outlined,
            color: Color(0xFF73510A),
            size: 28,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ação pública e auditável',
                  style: TextStyle(
                    color: Color(0xFF493407),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF73510A),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: isLoading ? null : onTap,
            icon: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _ActorActionDraft {
  const _ActorActionDraft({
    required this.actionType,
    required this.description,
    this.targetAgencyId,
    this.forecastAt,
    this.evidence,
  });

  final String actionType;
  final String description;
  final int? targetAgencyId;
  final DateTime? forecastAt;
  final XFile? evidence;
}

class _ActorActionSheet extends StatefulWidget {
  const _ActorActionSheet({
    required this.asCouncilor,
    required this.canActForAdministration,
    required this.agencies,
    this.currentAgencyId,
  });

  final bool asCouncilor;
  final bool canActForAdministration;
  final List<InstitutionalAgencyOption> agencies;
  final int? currentAgencyId;

  @override
  State<_ActorActionSheet> createState() => _ActorActionSheetState();
}

class _ActorActionSheetState extends State<_ActorActionSheet> {
  final _descriptionController = TextEditingController();
  late String _actionType;
  int? _targetAgencyId;
  DateTime? _forecastAt;
  XFile? _evidence;

  static const _councilorActions = <String, String>{
    'forwarding': 'Encaminhamento',
    'request': 'Solicitação',
    'charge': 'Cobrança',
    'official_letter': 'Ofício',
    'agency_contact': 'Contato com órgão',
    'response_received': 'Retorno recebido',
    'visit': 'Visita ou verificação',
    'public_update': 'Atualização pública',
    'possible_resolution': 'Possível resolução',
    'end_following': 'Encerrar acompanhamento',
  };

  static const _administrationActions = <String, String>{
    'priority': 'Reconhecer prioridade',
    'forwarding': 'Encaminhar para outro órgão',
    'request': 'Solicitar providências',
    'official_position': 'Posicionamento oficial',
    'forecast': 'Informar previsão',
    'analysis': 'Registrar análise',
    'scheduled': 'Serviço programado',
    'in_progress': 'Serviço em andamento',
    'executed': 'Serviço executado',
    'conclusion': 'Informar conclusão',
  };

  static const _agencyActions = <String, String>{
    'official_position': 'Posicionamento oficial',
    'forecast': 'Informar previsão',
    'analysis': 'Registrar análise',
    'scheduled': 'Serviço programado',
    'in_progress': 'Serviço em andamento',
    'executed': 'Serviço executado',
    'conclusion': 'Informar conclusão',
  };

  Map<String, String> get _actions => widget.asCouncilor
      ? _councilorActions
      : widget.canActForAdministration
      ? _administrationActions
      : _agencyActions;

  @override
  void initState() {
    super.initState();
    _actionType = _actions.keys.first;
    _targetAgencyId = widget.agencies
        .where((agency) => agency.id != widget.currentAgencyId)
        .firstOrNull
        ?.id;
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    final description = _descriptionController.text.trim();
    final requiresAgencyTarget =
        !widget.asCouncilor && _actionType == 'forwarding';
    if (description.length < 3 ||
        (requiresAgencyTarget && _targetAgencyId == null) ||
        (_actionType == 'forecast' && _forecastAt == null)) {
      return;
    }
    Navigator.of(context).pop(
      _ActorActionDraft(
        actionType: _actionType,
        description: description,
        targetAgencyId: _actionType == 'forwarding' ? _targetAgencyId : null,
        forecastAt: _actionType == 'forecast' ? _forecastAt : null,
        evidence: _actionType == 'end_following' ? null : _evidence,
      ),
    );
  }

  Future<void> _pickForecast() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _forecastAt ?? now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (selected != null) setState(() => _forecastAt = selected);
  }

  Future<void> _pickEvidence() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file != null && mounted) setState(() => _evidence = file);
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        _descriptionController.text.trim().length >= 3 &&
        (widget.asCouncilor ||
            _actionType != 'forwarding' ||
            _targetAgencyId != null) &&
        (_actionType != 'forecast' || _forecastAt != null);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.asCouncilor
                  ? 'Registrar atuação pública'
                  : 'Registrar ação oficial',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              initialValue: _actionType,
              items: _actions.entries
                  .map(
                    (entry) => DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _actionType = value;
                    if (value != 'forecast') _forecastAt = null;
                  });
                }
              },
              decoration: const InputDecoration(labelText: 'Tipo de ação'),
            ),
            if (!widget.asCouncilor && _actionType == 'forwarding') ...[
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: _targetAgencyId,
                items: widget.agencies
                    .where((agency) => agency.id != widget.currentAgencyId)
                    .map(
                      (agency) => DropdownMenuItem<int>(
                        value: agency.id,
                        child: Text(agency.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _targetAgencyId = value),
                decoration: const InputDecoration(
                  labelText: 'Novo órgão responsável',
                ),
              ),
            ],
            if (_actionType == 'forecast') ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _pickForecast,
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  _forecastAt == null
                      ? 'Selecionar previsão oficial'
                      : 'Previsão: ${_forecastAt!.day.toString().padLeft(2, '0')}/${_forecastAt!.month.toString().padLeft(2, '0')}/${_forecastAt!.year}',
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _descriptionController,
              minLines: 3,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Descrição pública',
                alignLabelWithHint: true,
              ),
            ),
            if (_actionType != 'end_following') ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _pickEvidence,
                icon: const Icon(Icons.attach_file_rounded),
                label: Text(
                  _evidence == null
                      ? 'Anexar evidência (opcional)'
                      : _evidence!.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_evidence != null)
                TextButton.icon(
                  onPressed: () => setState(() => _evidence = null),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Remover evidência'),
                ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canSubmit ? _submit : null,
                icon: const Icon(Icons.publish_rounded),
                label: const Text('Publicar na linha do tempo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OccurrenceActionsCard extends StatelessWidget {
  const _OccurrenceActionsCard({
    required this.engagement,
    required this.isFollowingLoading,
    required this.isReopening,
    required this.canReopen,
    required this.onToggleFollowing,
    required this.onReopen,
  });

  final OccurrenceEngagementContext engagement;
  final bool isFollowingLoading;
  final bool isReopening;
  final bool canReopen;
  final VoidCallback? onToggleFollowing;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_outlined, color: AppColors.primaryDark),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  engagement.reportsCount == 1
                      ? '1 relato nesta ocorrência'
                      : '${engagement.reportsCount} relatos nesta ocorrência',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Relatos semelhantes ficam reunidos para que o problema conte apenas uma vez nos indicadores.',
            style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.95),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: isFollowingLoading ? null : onToggleFollowing,
                icon: isFollowingLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        engagement.isFollowing
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_none_rounded,
                      ),
                label: Text(
                  engagement.isFollowing ? 'Acompanhando' : 'Acompanhar',
                ),
              ),
              if (canReopen)
                OutlinedButton.icon(
                  onPressed: isReopening ? null : onReopen,
                  icon: isReopening
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: const Text('Reabrir com evidência'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReopeningDraft {
  const _ReopeningDraft({required this.description, required this.evidence});

  final String description;
  final XFile evidence;
}

class _ReopenOccurrenceSheet extends StatefulWidget {
  const _ReopenOccurrenceSheet();

  @override
  State<_ReopenOccurrenceSheet> createState() => _ReopenOccurrenceSheetState();
}

class _ReopenOccurrenceSheetState extends State<_ReopenOccurrenceSheet> {
  final _descriptionController = TextEditingController();
  XFile? _evidence;
  bool _isPicking = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickEvidence() async {
    setState(() => _isPicking = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );
      if (!mounted || file == null) return;
      setState(() => _evidence = file);
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _submit() {
    final description = _descriptionController.text.trim();
    final evidence = _evidence;
    if (description.length < 3 || evidence == null) return;
    Navigator.of(
      context,
    ).pop(_ReopeningDraft(description: description, evidence: evidence));
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        _descriptionController.text.trim().length >= 3 && _evidence != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reabrir ocorrência',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use esta opção somente se o mesmo problema reapareceu ou se a solução não permaneceu efetiva.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _descriptionController,
              minLines: 3,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'O que voltou a acontecer?',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: Text(
                _evidence?.name ?? 'Selecionar nova evidência',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: const Text('Uma foto atual é obrigatória.'),
              trailing: _isPicking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: _isPicking ? null : _pickEvidence,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canSubmit ? _submit : null,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Confirmar reabertura'),
              ),
            ),
          ],
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
                      'Informar possível resolução',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Envie evidências para a comunidade confirmar o resultado.',
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

class _ValidationCard extends StatelessWidget {
  const _ValidationCard({
    required this.cycle,
    required this.currentUserId,
    required this.isVoting,
    required this.onConfirm,
    required this.onReject,
  });

  final ResolutionCycleInfo cycle;
  final String? currentUserId;
  final bool isVoting;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final isInitiator = currentUserId == cycle.initiatedBy;
    final remaining = cycle.expiresAt.difference(DateTime.now());
    final remainingHours = remaining.inHours.clamp(0, 72);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.pending.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.pending.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.how_to_vote_outlined, color: AppColors.pending),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Validação comunitária em andamento',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${cycle.confirmations}/${cycle.confirmationsRequired} confirmações · '
            '${cycle.rejections}/${cycle.rejectionsRequired} rejeições · '
            '${remainingHours}h restantes',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          if (isInitiator)
            const Text(
              'Você iniciou esta validação e não pode votar no próprio ciclo.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            )
          else if (currentUserId != null)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isVoting ? null : onReject,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Ainda existe'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isVoting ? null : onConfirm,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Foi resolvido'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.events});

  final List<OccurrenceTimelineEvent> events;

  @override
  Widget build(BuildContext context) {
    final visibleEvents = events.reversed.take(8).toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Linha do tempo pública',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          ...visibleEvents.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.description,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_actorLabel(event.actorKind)} · ${formatRelativeTime(event.createdAt)}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        if (event.evidenceUrl != null) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              event.evidenceUrl!,
                              width: double.infinity,
                              height: 150,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                height: 52,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                color: AppColors.border.withValues(alpha: 0.4),
                                child: const Text(
                                  'Evidência indisponível',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _actorLabel(String actorKind) {
    switch (actorKind) {
      case 'citizen':
        return 'Cidadão';
      case 'agency':
        return 'Órgão municipal';
      case 'administration':
        return 'Gestão municipal';
      case 'councilor':
        return 'Vereador';
      case 'moderator':
        return 'Moderação';
      default:
        return 'UrbApp';
    }
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
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          22,
          24,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Denunciar reporte',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Selecione o motivo. A denúncia será enviada para análise.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              RadioGroup<String>(
                groupValue: _selectedReason,
                onChanged: (value) => setState(() {
                  _selectedReason = value;
                }),
                child: Column(
                  children: _reasons
                      .map(
                        (reason) => RadioListTile<String>(
                          value: reason,
                          contentPadding: EdgeInsets.zero,
                          title: Text(reason),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _detailsController,
                maxLength: 300,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Detalhes adicionais',
                  hintText: 'Explique o problema, se necessário',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _selectedReason == null ? null : _submit,
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Enviar denúncia'),
                ),
              ),
            ],
          ),
        ),
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
