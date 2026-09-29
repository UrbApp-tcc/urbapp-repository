import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/city_service.dart';
import '../services/feed_service.dart';
import '../services/resolution_service.dart';
import '../theme/app_theme.dart';
import '../theme/urbapp_design.dart';
import '../widgets/urb_bottom_bar.dart';
import '../widgets/urb_dialog.dart';
import '../utils/error_formatter.dart';
import 'create_post_screen.dart';
import 'city_map_screen.dart';
import 'feed_screen.dart';
import 'notifications_screen.dart';
import 'post_detail_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});

  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen> {
  final _feedService = FeedService();
  final _cityService = CityService();
  final _authService = AuthService();
  final _supabase = Supabase.instance.client;

  RealtimeChannel? _postsChannel;
  RealtimeChannel? _postSupportsChannel;
  RealtimeChannel? _commentsChannel;
  Timer? _trendingRefreshDebounce;
  StreamSubscription<Uri>? _deepLinkSubscription;

  int _selectedIndex = 0;
  List<FeedPost> _posts = const [];
  List<FeedPost> _trendingPosts = const [];
  Set<int> _likedPostIds = const <int>{};

  /// Reportes aguardando a validação da comunidade.
  Set<int> _awaitingValidationIds = const <int>{};
  final _resolutionService = ResolutionService();

  /// Reportes com a curtida sendo enviada (evita toques repetidos).
  final Set<int> _pendingSupportIds = <int>{};
  List<CityOption> _cities = const [];
  int? _selectedCityId;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _hasShownTrendingWarning = false;

  @override
  void initState() {
    super.initState();
    _initializeCityFilter();
    _setupRealtimeSubscriptions();
    _setupDeepLinks();
  }

  Future<void> _initializeCityFilter() async {
    try {
      final results = await Future.wait<dynamic>([
        _cityService.fetchCities(),
        _cityService.fetchCurrentUserCityId(),
      ]);
      final cities = results[0] as List<CityOption>;
      final profileCityId = results[1] as int?;

      if (!mounted) return;
      setState(() {
        _cities = cities;
        _selectedCityId = cities.any((city) => city.id == profileCityId)
            ? profileCityId
            : null;
      });
    } catch (error) {
      if (mounted) {
        _showErrorSnackBar(friendlyError(error));
      }
    }

    await _loadFeed();
  }

  @override
  void dispose() {
    final postsChannel = _postsChannel;
    final postSupportsChannel = _postSupportsChannel;
    final commentsChannel = _commentsChannel;
    if (postsChannel != null) {
      _supabase.removeChannel(postsChannel);
    }
    if (postSupportsChannel != null) {
      _supabase.removeChannel(postSupportsChannel);
    }
    if (commentsChannel != null) {
      _supabase.removeChannel(commentsChannel);
    }
    _trendingRefreshDebounce?.cancel();
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  void _setupDeepLinks() {
    final appLinks = AppLinks();

    appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleDeepLink(uri);
    });

    _deepLinkSubscription = appLinks.uriLinkStream.listen(
      _handleDeepLink,
      onError: (_) {},
    );
  }

  Future<void> _handleDeepLink(Uri uri) async {
    if (uri.scheme != 'urbapp' || uri.host != 'posts') return;

    final rawId = uri.pathSegments.firstOrNull;
    final postId = int.tryParse(rawId ?? '');
    if (postId == null) return;

    final existing = [
      ..._posts,
      ..._trendingPosts,
    ].where((p) => p.id == postId).firstOrNull;

    if (existing != null) {
      if (!mounted) return;
      await _openPostDetail(existing);
      return;
    }

    final post = await _feedService.fetchPostById(postId);
    if (!mounted || post == null) return;
    await _openPostDetail(post);
  }

  void _setupRealtimeSubscriptions() {
    _postsChannel = _supabase
        .channel('feed-posts-sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'posts',
          callback: (payload) {
            final newRecord = payload.newRecord;
            final postId = (newRecord['id'] as num?)?.toInt();
            if (postId == null || !mounted) return;

            setState(() {
              _updatePostCollections(
                postId,
                (post) => post.copyWith(
                  status: newRecord['status'] as String?,
                  updatedAt: _parseDate(newRecord['updated_at']),
                  resolvedAt: _parseDate(newRecord['resolved_at']),
                  supportsCount: (newRecord['supports_count'] as num?)?.toInt(),
                  commentsCount: (newRecord['comments_count'] as num?)?.toInt(),
                ),
              );
            });
            _scheduleTrendingRefresh();
          },
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.channelError && mounted) {
            _loadFeed();
          }
        });

    _commentsChannel = _supabase
        .channel('feed-comments-sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'comments',
          callback: (payload) {
            final postId = (payload.newRecord['post_id'] as num?)?.toInt();
            if (postId == null || !mounted) return;
            _syncPostCommentsCount(postId);
            _scheduleTrendingRefresh();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'comments',
          callback: (payload) {
            final postId = (payload.oldRecord['post_id'] as num?)?.toInt();
            if (postId == null || !mounted) return;
            _syncPostCommentsCount(postId);
            _scheduleTrendingRefresh();
          },
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.channelError && mounted) {
            _loadFeed();
          }
        });

    final currentUserId = _authService.currentUser?.id;
    if (currentUserId == null) return;

    _postSupportsChannel = _supabase
        .channel('feed-post-supports-sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'post_supports',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: currentUserId,
          ),
          callback: (payload) {
            final postId = (payload.newRecord['post_id'] as num?)?.toInt();
            if (postId == null || !mounted) return;

            setState(() {
              _likedPostIds = {..._likedPostIds, postId};
            });
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'post_supports',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: currentUserId,
          ),
          callback: (payload) {
            final postId = (payload.oldRecord['post_id'] as num?)?.toInt();
            if (postId == null || !mounted) return;

            setState(() {
              _likedPostIds = _likedPostIds.where((id) => id != postId).toSet();
            });
          },
        )
        .subscribe();
  }

  Future<void> _loadFeed({bool refreshing = false}) async {
    if (refreshing) {
      setState(() => _isRefreshing = true);
    } else {
      setState(() => _isLoading = true);
    }

    try {
      final posts = await _feedService.fetchFeed(cityId: _selectedCityId);
      List<FeedPost> trendingPosts = const [];
      Object? trendingError;

      try {
        trendingPosts = await _feedService.fetchTrendingFeed(
          cityId: _selectedCityId,
        );
      } catch (error) {
        trendingError = error;
      }

      final postIds = _mergePostIds(posts: posts, trendingPosts: trendingPosts);
      final likedPostIds = await _feedService.fetchLikedPostIds(postIds);
      final awaitingIds = await _resolutionService.fetchAwaitingPostIds(
        postIds,
      );

      if (!mounted) return;
      setState(() {
        _posts = posts;
        _trendingPosts = trendingPosts;
        _likedPostIds = likedPostIds;
        _awaitingValidationIds = awaitingIds;
      });

      if (trendingError != null) {
        _showTrendingWarning(trendingError);
      }
    } catch (error) {
      if (!mounted) return;
      _showErrorSnackBar(friendlyError(error));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _changeCityFilter(int? cityId) async {
    if (cityId == _selectedCityId) return;
    setState(() => _selectedCityId = cityId);
    await _loadFeed();
  }

  Future<void> _openCityMap() async {
    if (_cities.isEmpty) {
      _showErrorSnackBar('Nenhuma cidade está disponível para exibir no mapa.');
      return;
    }

    await CityMapScreen.open(
      context,
      cities: _cities,
      initialCityId: _selectedCityId,
    );
  }

  Future<void> _openCreatePost() async {
    // Abre o "Novo reporte" como janela flutuante.
    final created = await CreatePostScreen.open(context);

    if (!mounted || created != true) return;

    setState(() => _selectedIndex = 0);
    await _loadFeed(refreshing: true);
  }

  Future<void> _openPostDetail(FeedPost post) async {
    final hasChanges = await PostDetailScreen.open(context, post);
    if (!mounted || hasChanges != true) return;

    await _loadFeed(refreshing: true);
  }

  Future<void> _syncPostCommentsCount(int postId) async {
    if (!_containsPost(postId)) return;

    try {
      final commentCounts = await _feedService.fetchCommentCounts([postId]);
      if (!mounted) return;

      setState(() {
        _updatePostCollections(
          postId,
          (post) => post.copyWith(commentsCount: commentCounts[postId] ?? 0),
        );
      });
    } catch (_) {
      // Evita quebrar a experiência do feed se a sincronização pontual falhar.
    }
  }

  Future<void> _refreshTrendingFeed() async {
    try {
      final trendingPosts = await _feedService.fetchTrendingFeed(
        cityId: _selectedCityId,
      );
      final likedPostIds = await _feedService.fetchLikedPostIds(
        _mergePostIds(posts: _posts, trendingPosts: trendingPosts),
      );

      if (!mounted) return;
      setState(() {
        _trendingPosts = trendingPosts;
        _likedPostIds = likedPostIds;
      });
    } catch (_) {
      // Mantem o feed principal utilizavel mesmo se o recálculo em alta falhar.
    }
  }

  void _scheduleTrendingRefresh() {
    _trendingRefreshDebounce?.cancel();
    _trendingRefreshDebounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _refreshTrendingFeed();
    });
  }

  void _showTrendingWarning(Object error) {
    if (!mounted || _hasShownTrendingWarning) return;

    final rawMessage = friendlyError(error);
    final message = _isMissingTrendingFunction(error)
        ? 'A aba Em Alta ainda não está disponível neste banco. '
              'Aplique a migration do ranking para habilitá-la.'
        : rawMessage;

    _hasShownTrendingWarning = true;
    _showErrorSnackBar(message);
  }

  bool _isMissingTrendingFunction(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('get_trending_feed_posts') &&
        message.contains('schema cache');
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _signOut() async {
    try {
      await _authService.signOut();
    } catch (error) {
      if (!mounted) return;
      _showErrorSnackBar(friendlyError(error));
    }
  }

  void _selectTab(int index) {
    setState(() => _selectedIndex = index);
  }

  bool _containsPost(int postId) {
    return _posts.any((post) => post.id == postId) ||
        _trendingPosts.any((post) => post.id == postId);
  }

  List<int> _mergePostIds({
    required List<FeedPost> posts,
    required List<FeedPost> trendingPosts,
  }) {
    return {
      ...posts.map((post) => post.id),
      ...trendingPosts.map((post) => post.id),
    }.toList();
  }

  /// Dá ou tira o apoio (curtida) direto do Início.
  /// A tela muda na hora e volta atrás se o envio falhar.
  Future<void> _toggleSupport(FeedPost post) async {
    final userId = _resolveCurrentUserId();
    if (userId == null || _pendingSupportIds.contains(post.id)) return;

    final wasLiked = _likedPostIds.contains(post.id);
    _pendingSupportIds.add(post.id);

    void apply(bool liked) {
      setState(() {
        _likedPostIds = liked
            ? {..._likedPostIds, post.id}
            : _likedPostIds.where((id) => id != post.id).toSet();
        _updatePostCollections(
          post.id,
          (current) => current.copyWith(
            supportsCount: liked
                ? current.supportsCount + 1
                : (current.supportsCount > 0 ? current.supportsCount - 1 : 0),
          ),
        );
      });
    }

    apply(!wasLiked);

    try {
      if (wasLiked) {
        await _supabase
            .from('post_supports')
            .delete()
            .eq('post_id', post.id)
            .eq('user_id', userId);
      } else {
        await _supabase.from('post_supports').insert({
          'post_id': post.id,
          'user_id': userId,
        });
      }
    } catch (error) {
      if (!mounted) return;
      apply(wasLiked);
      showUrbSnack(context, friendlyError(error), error: true);
    } finally {
      _pendingSupportIds.remove(post.id);
    }
  }

  void _updatePostCollections(
    int postId,
    FeedPost Function(FeedPost post) update,
  ) {
    _posts = _posts
        .map((post) => post.id == postId ? update(post) : post)
        .toList();
    _trendingPosts = _trendingPosts
        .map((post) => post.id == postId ? update(post) : post)
        .toList();
  }

  DateTime? _parseDate(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  String? _resolveCurrentUserId() {
    return _supabase.auth.currentSession?.user.id ??
        _authService.currentUser?.id;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _resolveCurrentUserId();

    return Scaffold(
      backgroundColor: UrbColors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useFramedLayout = constraints.maxWidth > 520;
            final shellWidth = constraints.maxWidth > 430
                ? 390.0
                : constraints.maxWidth;

            return Center(
              child: Container(
                width: shellWidth,
                margin: EdgeInsets.symmetric(
                  horizontal: useFramedLayout ? 16 : 0,
                  vertical: useFramedLayout ? 18 : 0,
                ),
                decoration: BoxDecoration(
                  color: UrbColors.surface,
                  borderRadius: BorderRadius.circular(useFramedLayout ? 34 : 0),
                  boxShadow: useFramedLayout
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 34,
                            offset: const Offset(0, 18),
                          ),
                        ]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IndexedStack(
                        index: _selectedIndex,
                        children: [
                          FeedScreen(
                            posts: _posts,
                            trendingPosts: _trendingPosts,
                            likedPostIds: _likedPostIds,
                            isLoading: _isLoading,
                            isRefreshing: _isRefreshing,
                            onOpenPost: _openPostDetail,
                            cities: _cities,
                            selectedCityId: _selectedCityId,
                            onCityChanged: _changeCityFilter,
                            onOpenMap: _openCityMap,
                            onToggleSupport: _toggleSupport,
                            awaitingValidationIds: _awaitingValidationIds,
                          ),
                          SearchScreen(
                            posts: _posts,
                            isLoading: _isLoading,
                            currentUserId: currentUserId,
                            cities: _cities,
                            selectedCityId: _selectedCityId,
                            onCityChanged: _changeCityFilter,
                            awaitingValidationIds: _awaitingValidationIds,
                          ),
                          NotificationsScreen(
                            currentUserId: currentUserId,
                            isActive: _selectedIndex == 2,
                            onOpenSearch: () => _selectTab(1),
                          ),
                          if (currentUserId != null)
                            ProfileScreen(
                              profileUserId: currentUserId,
                              currentUserId: currentUserId,
                              onSignOut: _signOut,
                              isActive: _selectedIndex == 3,
                            )
                          else
                            const _ProfileUnavailableState(),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 14,
                      child: UrbBottomBar(
                        selectedIndex: _selectedIndex,
                        onSelect: _selectTab,
                        onCreate: _openCreatePost,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProfileUnavailableState extends StatelessWidget {
  const _ProfileUnavailableState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(
              Icons.person_off_outlined,
              size: 42,
              color: AppColors.textHint,
            ),
            SizedBox(height: 14),
            Text(
              'Não foi possível identificar sua conta agora.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Tente fechar e abrir a aba novamente. Se persistir, entre na conta de novo.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
