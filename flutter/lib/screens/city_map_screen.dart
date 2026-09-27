import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/city_service.dart';
import '../services/feed_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_formatter.dart';
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
  final _mapController = MapController();

  int? _selectedCityId;
  List<FeedPost> _posts = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedCityId = _resolveInitialCityId();
    _loadPosts();
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

  Future<void> _loadPosts() async {
    final cityId = _selectedCityId;
    if (cityId == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final posts = await _feedService.fetchAllCityPosts(cityId: cityId);
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _isLoading = false;
      });
      _centerMap(posts);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(error)),
          backgroundColor: AppColors.error,
        ),
      );
    }
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

  void _showPostPreview(FeedPost post) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              post.categoryName,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              post.title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (post.addressLabel.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                post.addressLabel,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _openPost(post);
                },
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Ver reporte'),
              ),
            ),
          ],
        ),
      ),
    );
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
            child: DropdownButtonFormField<int>(
              key: ValueKey(_selectedCityId),
              initialValue: _selectedCityId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Cidade exibida',
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
              items: widget.cities
                  .map(
                    (city) => DropdownMenuItem<int>(
                      value: city.id,
                      child: Text(city.name),
                    ),
                  )
                  .toList(),
              onChanged: _isLoading
                  ? null
                  : (cityId) {
                      if (cityId == null || cityId == _selectedCityId) return;
                      setState(() {
                        _selectedCityId = cityId;
                        _posts = const [];
                      });
                      _loadPosts();
                    },
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
                            : '${_posts.length} reportes em ${selectedCity?.name ?? 'cidade selecionada'}',
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
