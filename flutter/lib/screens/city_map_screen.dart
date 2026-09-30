import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../services/city_service.dart';
import '../services/feed_service.dart';
import '../services/post_service.dart';
import '../theme/urbapp_design.dart';
import '../utils/error_formatter.dart';
import '../widgets/city_picker_sheet.dart';
import '../widgets/city_skyline.dart';
import '../widgets/urb_dialog.dart';
import '../widgets/urb_post_image.dart';
import '../widgets/urb_primary_button.dart';
import '../widgets/urb_status_chip.dart';
import 'post_detail_screen.dart';

class CityMapScreen extends StatefulWidget {
  const CityMapScreen({super.key, required this.cities, this.initialCityId});

  final List<CityOption> cities;
  final int? initialCityId;

  static Future<void> open(
    BuildContext context, {
    required List<CityOption> cities,
    int? initialCityId,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            CityMapScreen(cities: cities, initialCityId: initialCityId),
      ),
    );
  }

  @override
  State<CityMapScreen> createState() => _CityMapScreenState();
}

class _CityMapScreenState extends State<CityMapScreen> {
  final _feedService = FeedService();
  final _postService = PostService();
  final _mapController = MapController();

  /// Busca de endereço ou bairro na barra de baixo.
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;
  List<_PlaceResult> _searchResults = const [];
  bool _isSearching = false;
  bool _searchDone = false;
  LatLng? _searchedPoint;

  /// Escala da pinça do touchpad no começo do gesto (para calcular o zoom).
  double _lastPanZoomScale = 1;

  int? _selectedCityId;
  int? _selectedCategoryId;
  List<LookupOption> _categories = const [];
  List<FeedPost> _posts = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedCityId = _resolveInitialCityId();
    _loadInitialData();
  }

  @override
  void dispose() {
    _mapController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  int? _resolveInitialCityId() {
    final requested = widget.initialCityId;
    if (requested != null &&
        widget.cities.any((city) => city.id == requested)) {
      return requested;
    }
    return widget.cities.firstOrNull?.id;
  }

  CityOption? get _selectedCity {
    final selectedId = _selectedCityId;
    if (selectedId == null) return null;
    return widget.cities.where((city) => city.id == selectedId).firstOrNull;
  }

  LookupOption? get _selectedCategory {
    final selectedId = _selectedCategoryId;
    if (selectedId == null) return null;
    return _categories
        .where((category) => category.id == selectedId)
        .firstOrNull;
  }

  Future<void> _loadInitialData() async {
    final cityId = _selectedCityId;
    if (cityId == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final categoriesFuture = _postService.fetchCategories();
      final postsFuture = _feedService.fetchAllCityPosts(
        cityId: cityId,
        status: 'open',
      );
      final categories = await categoriesFuture;
      final posts = await postsFuture;
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _posts = posts;
        _isLoading = false;
      });
      _centerMap(posts);
    } catch (error) {
      _handleLoadError(error);
    }
  }

  Future<void> _loadPosts() async {
    final cityId = _selectedCityId;
    if (cityId == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final posts = await _feedService.fetchAllCityPosts(
        cityId: cityId,
        categoryId: _selectedCategoryId,
        status: 'open',
      );
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _isLoading = false;
      });
      _centerMap(posts);
    } catch (error) {
      _handleLoadError(error);
    }
  }

  void _handleLoadError(Object error) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    showUrbSnack(context, friendlyError(error), error: true);
  }

  void _centerMap(List<FeedPost> posts) {
    if (posts.isEmpty) return;

    final latitude =
        posts
            .map((post) => post.latitude)
            .reduce((value, element) => value + element) /
        posts.length;
    final longitude =
        posts
            .map((post) => post.longitude)
            .reduce((value, element) => value + element) /
        posts.length;

    final minLatitude = posts
        .map((post) => post.latitude)
        .reduce((value, element) => value < element ? value : element);
    final maxLatitude = posts
        .map((post) => post.latitude)
        .reduce((value, element) => value > element ? value : element);
    final minLongitude = posts
        .map((post) => post.longitude)
        .reduce((value, element) => value < element ? value : element);
    final maxLongitude = posts
        .map((post) => post.longitude)
        .reduce((value, element) => value > element ? value : element);
    final span =
        (maxLatitude - minLatitude).abs() + (maxLongitude - minLongitude).abs();
    final zoom = switch (span) {
      < 0.02 => 14.5,
      < 0.08 => 12.5,
      < 0.20 => 11.0,
      _ => 9.5,
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(LatLng(latitude, longitude), zoom);
    });
  }

  Future<void> _openPost(FeedPost post) async {
    final changed = await PostDetailScreen.open(context, post);
    if (!mounted || changed != true) return;
    await _loadPosts();
  }

  Future<void> _chooseCity() async {
    final result = await showCityPickerSheet(
      context,
      cities: widget.cities,
      selectedCityId: _selectedCityId,
    );
    final cityId = result?.cityId;
    if (!mounted || cityId == null || cityId == _selectedCityId) return;
    setState(() {
      _selectedCityId = cityId;
      _posts = const [];
    });
    await _loadPosts();
  }

  Future<void> _chooseCategory() async {
    final selectedId = await showUrbDialog<int>(
      context: context,
      builder: (_) => _CategoryPickerDialog(
        categories: _categories,
        selectedId: _selectedCategoryId,
      ),
    );

    if (!mounted || selectedId == null) return;
    final categoryId = selectedId == 0 ? null : selectedId;
    if (categoryId == _selectedCategoryId) return;
    setState(() {
      _selectedCategoryId = categoryId;
      _posts = const [];
    });
    await _loadPosts();
  }

  Future<void> _showPostPreview(FeedPost post) async {
    final openPost = await showUrbDialog<bool>(
      context: context,
      builder: (_) => _PostPreviewDialog(post: post),
    );

    if (openPost == true && mounted) {
      await _openPost(post);
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _searchResults = const [];
        _isSearching = false;
        _searchDone = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    // Espera parar de digitar: o serviço de mapas aceita 1 consulta por segundo.
    _searchDebounce = Timer(
      const Duration(milliseconds: 700),
      () => _searchPlace(query),
    );
  }

  Future<void> _searchPlace(String query) async {
    LatLng center;
    try {
      center = _mapController.camera.center;
    } catch (_) {
      center = const LatLng(-23.55052, -46.63331);
    }

    final cityName = _selectedCity?.name;
    final fullQuery =
        cityName != null &&
            !query.toLowerCase().contains(cityName.toLowerCase())
        ? '$query, $cityName'
        : query;

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'q': fullQuery,
        'limit': '5',
        'countrycodes': 'br',
        'accept-language': 'pt-BR',
        'viewbox':
            '${center.longitude - 0.4},${center.latitude + 0.4},'
            '${center.longitude + 0.4},${center.latitude - 0.4}',
        'bounded': '0',
      });
      final response = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('Não foi possível buscar o endereço agora.');
      }

      final results = (jsonDecode(response.body) as List<dynamic>)
          .map((item) => item as Map<String, dynamic>)
          .map((item) {
            final lat = double.tryParse('${item['lat']}');
            final lon = double.tryParse('${item['lon']}');
            if (lat == null || lon == null) return null;
            return _PlaceResult(
              label: '${item['display_name'] ?? ''}',
              point: LatLng(lat, lon),
            );
          })
          .whereType<_PlaceResult>()
          .toList();

      if (!mounted || _searchController.text.trim() != query) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
        _searchDone = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchDone = true;
        _searchResults = const [];
      });
      showUrbSnack(context, friendlyError(error), error: true);
    }
  }

  void _goToPlace(_PlaceResult place) {
    _searchFocus.unfocus();
    _searchDebounce?.cancel();
    _searchController.text = place.label.split(',').take(2).join(',').trim();
    setState(() {
      _searchResults = const [];
      _searchDone = false;
      _searchedPoint = place.point;
    });
    try {
      _mapController.move(place.point, 16.5);
    } catch (_) {}
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchResults = const [];
      _isSearching = false;
      _searchDone = false;
      _searchedPoint = null;
    });
  }

  /// Pinça no touchpad do notebook e Ctrl + rodinha no navegador.
  /// O mapa já trata a pinça com os dedos na tela; estes eventos chegam
  /// de outro jeito e precisam ser convertidos em zoom aqui.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScaleEvent && event.scale > 0) {
      _zoomBy(math.log(event.scale) / math.ln2);
    }
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) => _lastPanZoomScale = 1;

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (event.scale <= 0 || _lastPanZoomScale <= 0) return;
    final factor = event.scale / _lastPanZoomScale;
    _lastPanZoomScale = event.scale;
    if ((factor - 1).abs() < 0.001) return;
    _zoomBy(math.log(factor) / math.ln2);
  }

  void _zoomBy(double delta) {
    try {
      final camera = _mapController.camera;
      final zoom = (camera.zoom + delta).clamp(4.0, 19.0);
      _mapController.move(camera.center, zoom);
    } catch (_) {
      // O mapa ainda não terminou de abrir.
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCity = _selectedCity;
    final fallbackCenter = _posts.isNotEmpty
        ? LatLng(_posts.first.latitude, _posts.first.longitude)
        : const LatLng(-23.55052, -46.63331);
    final cityName = selectedCity?.name ?? 'cidade selecionada';
    final countLabel = _isLoading
        ? 'Carregando reportes...'
        : _posts.length == 1
        ? '1 reporte aberto em $cityName'
        : '${_posts.length} reportes abertos em $cityName';

    return Scaffold(
      backgroundColor: UrbColors.surface,
      body: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              onPointerSignal: _onPointerSignal,
              onPointerPanZoomStart: _onPanZoomStart,
              onPointerPanZoomUpdate: _onPanZoomUpdate,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: fallbackCenter,
                  initialZoom: 12,
                  minZoom: 4,
                  maxZoom: 19,
                  // Pinça, dois toques e rodinha do mouse dão zoom.
                  // A rotação fica desligada para o mapa não girar sem querer na pinça.
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'br.com.urbapp.app',
                  ),
                  if (_searchedPoint != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _searchedPoint!,
                          width: 34,
                          height: 34,
                          child: const _SearchedPlaceDot(),
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      for (var i = 0; i < _posts.length; i++)
                        Marker(
                          point: LatLng(
                            _posts[i].latitude,
                            _posts[i].longitude,
                          ),
                          width: 52,
                          height: 58,
                          alignment: Alignment.topCenter,
                          child: _MapPin(
                            // A key faz os pinos "caírem" de novo ao trocar de filtro.
                            key: ValueKey(
                              'pin-$_selectedCityId-$_selectedCategoryId-${_posts[i].id}',
                            ),
                            post: _posts[i],
                            delay: Duration(milliseconds: 30 * (i % 12)),
                            onTap: () => _showPostPreview(_posts[i]),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _MapHeader(
              countLabel: countLabel,
              cityLabel: selectedCity == null
                  ? 'Cidade'
                  : '${selectedCity.name} · ${selectedCity.stateAbbreviation}',
              categoryLabel: _selectedCategory?.name ?? 'Todas as modalidades',
              categoryActive: _selectedCategoryId != null,
              onBack: () => Navigator.of(context).maybePop(),
              onChooseCity: _isLoading ? null : _chooseCity,
              onChooseCategory: _isLoading || _categories.isEmpty
                  ? null
                  : _chooseCategory,
            ),
          ),
          // Botões de zoom (para quem não consegue fazer a pinça, como no computador).
          Positioned(
            right: 16,
            bottom: 100 + MediaQuery.paddingOf(context).bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ZoomButtons(
                  onZoomIn: () => _zoomBy(1),
                  onZoomOut: () => _zoomBy(-1),
                ),
                if (!_isLoading && _posts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _RoundMapButton(
                    icon: Icons.center_focus_strong_rounded,
                    tooltip: 'Ver todos os reportes',
                    onPressed: () => _centerMap(_posts),
                  ),
                ],
              ],
            ),
          ),
          if (_isLoading)
            const Center(child: _LoadingPill())
          else if (_posts.isEmpty)
            Center(
              child: Container(
                margin: const EdgeInsets.all(28),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x2A0D1520),
                      blurRadius: 30,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: UrbColors.lavender,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.map_outlined,
                        color: UrbColors.violetDeep,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Nenhum reporte aberto aqui',
                      textAlign: TextAlign.center,
                      style: UrbText.display(size: 18, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ainda não há reportes com localização nesta cidade.',
                      textAlign: TextAlign.center,
                      style: UrbText.body(size: 14, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          // Barra de busca no rodapé, com as sugestões aparecendo por cima.
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
            child: _MapSearchBar(
              controller: _searchController,
              focusNode: _searchFocus,
              isSearching: _isSearching,
              showEmpty: _searchDone && !_isSearching && _searchResults.isEmpty,
              results: _searchResults,
              onChanged: _onSearchChanged,
              onClear: _clearSearch,
              onSelect: _goToPlace,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// Topo roxo com voltar, contagem e filtros
// ──────────────────────────────────────────────────────────

class _MapHeader extends StatelessWidget {
  const _MapHeader({
    required this.countLabel,
    required this.cityLabel,
    required this.categoryLabel,
    required this.categoryActive,
    required this.onBack,
    required this.onChooseCity,
    required this.onChooseCategory,
  });

  final String countLabel;
  final String cityLabel;
  final String categoryLabel;
  final bool categoryActive;
  final VoidCallback onBack;
  final VoidCallback? onChooseCity;
  final VoidCallback? onChooseCategory;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: UrbColors.hero,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Color(0x402A1B6B),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 90,
            child: CitySkyline(),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _GlassButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Voltar',
                        onPressed: onBack,
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              'Mapa da cidade',
                              textAlign: TextAlign.center,
                              style: UrbText.display(
                                size: 20,
                                weight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            AnimatedSwitcher(
                              duration: UrbMotion.of(context, UrbMotion.fast),
                              child: Text(
                                countLabel,
                                key: ValueKey(countLabel),
                                textAlign: TextAlign.center,
                                style: UrbText.body(
                                  size: 13,
                                  color: UrbColors.heroText,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 44),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _FilterButton(
                          icon: Icons.location_on_outlined,
                          label: cityLabel,
                          active: false,
                          onPressed: onChooseCity,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _FilterButton(
                          icon: Icons.category_outlined,
                          label: categoryLabel,
                          active: categoryActive,
                          onPressed: onChooseCategory,
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
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = active ? UrbColors.violetDeep : Colors.white;
    return AnimatedContainer(
      duration: UrbMotion.of(context, UrbMotion.fast),
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: active ? 1 : 0.28),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: UrbMotion.of(context, UrbMotion.fast),
                    child: Text(
                      label,
                      key: ValueKey(label),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.body(
                        size: 14,
                        weight: FontWeight.w700,
                        color: color,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
                Icon(Icons.expand_more_rounded, size: 18, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// Pino do mapa: "cai" e quica ao aparecer
// ──────────────────────────────────────────────────────────

class _MapPin extends StatefulWidget {
  const _MapPin({
    super.key,
    required this.post,
    required this.delay,
    required this.onTap,
  });

  final FeedPost post;
  final Duration delay;
  final VoidCallback onTap;

  @override
  State<_MapPin> createState() => _MapPinState();
}

class _MapPinState extends State<_MapPin> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final Animation<double> _drop = CurvedAnimation(
    parent: _controller,
    curve: Curves.bounceOut,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
        return;
      }
      await Future<void>.delayed(widget.delay);
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Abrir reporte ${widget.post.title}',
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _drop,
          builder: (context, child) => Opacity(
            opacity: _controller.value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, -24 * (1 - _drop.value)),
              child: child,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: UrbGradients.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x553B3FA0),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              // "Pontinha" do pino.
              Transform.translate(
                offset: const Offset(0, -3),
                child: Transform.rotate(
                  angle: 0.785398,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        bottomRight: Radius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundMapButton extends StatelessWidget {
  const _RoundMapButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: const Color(0x552A1B6B),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 54,
            height: 54,
            child: Icon(icon, color: UrbColors.violetDeep),
          ),
        ),
      ),
    );
  }
}

/// Resultado da busca de endereço.
class _PlaceResult {
  const _PlaceResult({required this.label, required this.point});

  final String label;
  final LatLng point;
}

/// Ponto roxo pulsando no lugar buscado.
class _SearchedPlaceDot extends StatelessWidget {
  const _SearchedPlaceDot();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: UrbMotion.of(context, const Duration(milliseconds: 500)),
      curve: Curves.elasticOut,
      builder: (context, value, child) =>
          Transform.scale(scale: value, child: child),
      child: Container(
        decoration: BoxDecoration(
          color: UrbColors.violet.withValues(alpha: 0.25),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: UrbColors.violet,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
        ),
      ),
    );
  }
}

/// Barra de busca de endereço ou bairro, no rodapé do mapa.
class _MapSearchBar extends StatelessWidget {
  const _MapSearchBar({
    required this.controller,
    required this.focusNode,
    required this.isSearching,
    required this.showEmpty,
    required this.results,
    required this.onChanged,
    required this.onClear,
    required this.onSelect,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSearching;
  final bool showEmpty;
  final List<_PlaceResult> results;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<_PlaceResult> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: UrbMotion.of(context, UrbMotion.fast),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: results.isEmpty && !showEmpty
              ? const SizedBox(width: double.infinity)
              : Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  constraints: const BoxConstraints(maxHeight: 260),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x332A1B6B),
                        blurRadius: 24,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: showEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Nenhum lugar encontrado. Tente com o nome da rua ou do bairro.',
                            textAlign: TextAlign.center,
                            style: UrbText.body(
                              size: 13,
                              color: UrbColors.textMuted,
                              height: 1.4,
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: results.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            indent: 48,
                            color: UrbColors.border,
                          ),
                          itemBuilder: (context, index) => InkWell(
                            onTap: () => onSelect(results[index]),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    color: UrbColors.violet,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      results[index].label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: UrbText.body(
                                        size: 13,
                                        color: UrbColors.ink,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
        ),
        Material(
          color: Colors.white,
          elevation: 8,
          shadowColor: const Color(0x552A1B6B),
          borderRadius: BorderRadius.circular(22),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            textAlign: TextAlign.center,
            style: UrbText.body(size: 15, color: UrbColors.ink, height: 1.3),
            decoration: InputDecoration(
              hintText: 'Buscar endereço ou bairro',
              hintStyle: UrbText.body(
                size: 15,
                color: UrbColors.textMuted,
                height: 1.3,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 18),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: UrbColors.violetDeep,
              ),
              suffixIcon: isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(15),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : controller.text.isEmpty
                  ? const SizedBox(width: 48)
                  : IconButton(
                      tooltip: 'Limpar busca',
                      onPressed: onClear,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: UrbColors.textMuted,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Botões "+" e "−" empilhados, num cartão branco.
class _ZoomButtons extends StatelessWidget {
  const _ZoomButtons({required this.onZoomIn, required this.onZoomOut});

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    Widget button(
      IconData icon,
      String tooltip,
      VoidCallback onTap,
      BorderRadius radius,
    ) => Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: SizedBox(
          width: 50,
          height: 50,
          child: Icon(icon, color: UrbColors.violetDeep),
        ),
      ),
    );

    return Material(
      color: Colors.white,
      elevation: 6,
      shadowColor: const Color(0x552A1B6B),
      borderRadius: BorderRadius.circular(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            Icons.add_rounded,
            'Aproximar',
            onZoomIn,
            const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          Container(width: 30, height: 1, color: UrbColors.border),
          button(
            Icons.remove_rounded,
            'Afastar',
            onZoomOut,
            const BorderRadius.vertical(bottom: Radius.circular(18)),
          ),
        ],
      ),
    );
  }
}

class _LoadingPill extends StatelessWidget {
  const _LoadingPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2A0D1520),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 10),
          Text(
            'Carregando reportes...',
            style: UrbText.body(
              size: 14,
              weight: FontWeight.w700,
              color: UrbColors.ink,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// Janelas flutuantes: modalidade e prévia do reporte
// ──────────────────────────────────────────────────────────

class _CategoryPickerDialog extends StatelessWidget {
  const _CategoryPickerDialog({
    required this.categories,
    required this.selectedId,
  });

  final List<LookupOption> categories;
  final int? selectedId;

  @override
  Widget build(BuildContext context) {
    Widget option(String label, int value, bool selected, IconData icon) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: () => Navigator.of(context).pop(value),
          borderRadius: BorderRadius.circular(16),
          child: Container(
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
                Icon(
                  icon,
                  size: 20,
                  color: selected ? UrbColors.violetDeep : UrbColors.textMuted,
                ),
                const SizedBox(width: 12),
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
                if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: UrbColors.violetDeep,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UrbDialogHeader(
              icon: Icons.category_outlined,
              title: 'Modalidade do reporte',
              subtitle: 'Mostre só um tipo de problema no mapa.',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  option(
                    'Todas as modalidades',
                    0,
                    selectedId == null,
                    Icons.apps_rounded,
                  ),
                  for (final category in categories)
                    option(
                      category.name,
                      category.id,
                      category.id == selectedId,
                      Icons.sell_outlined,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostPreviewDialog extends StatelessWidget {
  const _PostPreviewDialog({required this.post});

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    final neighborhood = post.neighborhood?.trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              UrbPostImage(url: post.primaryImageUrl, height: 190, radius: 0),
              Positioned(
                left: 14,
                top: 14,
                child: UrbStatusChip(status: post.status),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: Material(
                  color: const Color(0x660D1520),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(13),
                    child: const SizedBox(
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  post.title,
                  textAlign: TextAlign.center,
                  style: UrbText.display(size: 20, weight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: UrbColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          neighborhood != null && neighborhood.isNotEmpty
                              ? neighborhood
                              : 'Bairro não informado',
                          style: UrbText.body(size: 13, height: 1.3),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.sell_outlined,
                          size: 15,
                          color: UrbColors.violet,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          post.categoryName,
                          style: UrbText.body(size: 13, height: 1.3),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.favorite_rounded,
                          size: 15,
                          color: UrbColors.heart,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${post.supportsCount}',
                          style: UrbText.body(
                            size: 13,
                            weight: FontWeight.w700,
                            color: const Color(0xFFB0164F),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                UrbPrimaryButton(
                  label: 'Ver reporte',
                  icon: Icons.open_in_new_rounded,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
