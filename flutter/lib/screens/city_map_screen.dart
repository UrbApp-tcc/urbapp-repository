import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: fallbackCenter,
                initialZoom: 12,
                minZoom: 4,
                maxZoom: 19,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'br.com.urbapp.app',
                ),
                MarkerLayer(
                  markers: [
                    for (var i = 0; i < _posts.length; i++)
                      Marker(
                        point: LatLng(_posts[i].latitude, _posts[i].longitude),
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
          if (!_isLoading && _posts.isNotEmpty)
            Positioned(
              right: 16,
              bottom: 24 + MediaQuery.paddingOf(context).bottom,
              child: _RoundMapButton(
                icon: Icons.center_focus_strong_rounded,
                tooltip: 'Ver todos os reportes',
                onPressed: () => _centerMap(_posts),
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
