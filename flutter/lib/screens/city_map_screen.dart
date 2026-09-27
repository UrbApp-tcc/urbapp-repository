import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/city_service.dart';
import '../services/feed_service.dart';
import '../services/post_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_formatter.dart';
import '../widgets/city_picker_sheet.dart';
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

  ButtonStyle get _filterButtonStyle => OutlinedButton.styleFrom(
    visualDensity: VisualDensity.compact,
    minimumSize: const Size(0, 36),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
  );

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(friendlyError(error)),
        backgroundColor: AppColors.error,
      ),
    );
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
    final selectedId = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.68,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 22, 24, 12),
                child: Text(
                  'Modalidade do reporte',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    ListTile(
                      onTap: () => Navigator.of(context).pop(0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      leading: Icon(
                        _selectedCategoryId == null
                            ? Icons.check_circle_rounded
                            : Icons.category_outlined,
                        color: _selectedCategoryId == null
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      title: const Text('Todas as modalidades'),
                    ),
                    ..._categories.map(
                      (category) => ListTile(
                        onTap: () => Navigator.of(context).pop(category.id),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        leading: Icon(
                          category.id == _selectedCategoryId
                              ? Icons.check_circle_rounded
                              : Icons.label_outline_rounded,
                          color: category.id == _selectedCategoryId
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        title: Text(category.name),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
    final openPost = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (post.primaryImageUrl case final imageUrl?)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: AppColors.background,
                        child: Center(
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: AppColors.textHint,
                            size: 36,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          color: AppColors.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            post.neighborhood?.trim().isNotEmpty == true
                                ? post.neighborhood!.trim()
                                : 'Bairro não informado',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.favorite_border_rounded,
                          color: AppColors.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${post.supportsCount}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      post.categoryName,
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Ir para o reporte'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (openPost == true && mounted) {
      await _openPost(post);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCity = _selectedCity;
    final fallbackCenter = _posts.isNotEmpty
        ? LatLng(_posts.first.latitude, _posts.first.longitude)
        : const LatLng(-23.55052, -46.63331);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Mapa da cidade')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _chooseCity,
                    icon: const Icon(Icons.location_on_outlined, size: 17),
                    label: Text(
                      selectedCity == null
                          ? 'Cidade'
                          : '${selectedCity.name} · ${selectedCity.stateAbbreviation}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: _filterButtonStyle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading || _categories.isEmpty
                        ? null
                        : _chooseCategory,
                    icon: const Icon(Icons.category_outlined, size: 17),
                    label: Text(
                      _selectedCategory?.name ?? 'Todas',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: _filterButtonStyle,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: fallbackCenter,
                    initialZoom: 12,
                    minZoom: 4,
                    maxZoom: 19,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'br.com.urbapp.app',
                    ),
                    MarkerLayer(
                      markers: _posts
                          .map(
                            (post) => Marker(
                              point: LatLng(post.latitude, post.longitude),
                              width: 48,
                              height: 48,
                              child: Semantics(
                                button: true,
                                label: 'Abrir reporte ${post.title}',
                                child: GestureDetector(
                                  onTap: () => _showPostPreview(post),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF18222E),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 3,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x33000000),
                                          blurRadius: 8,
                                          offset: Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.location_on_rounded,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 12,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 14,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Text(
                        _isLoading
                            ? 'Carregando reportes...'
                            : '${_posts.length} reportes abertos em ${selectedCity?.name ?? 'cidade selecionada'}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (_posts.isEmpty)
                  Center(
                    child: Container(
                      margin: const EdgeInsets.all(28),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Text(
                        'Ainda não há reportes com localização nesta cidade.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                          height: 1.4,
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
