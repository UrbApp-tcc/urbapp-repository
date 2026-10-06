import 'package:flutter/material.dart';

import '../../app/app_session.dart';
import '../../app/routes.dart';
import '../../domain/models.dart';
import '../../services/occurrence_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/filter_sheet.dart';
import '../../widgets/urb/occurrence_widgets.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';

/// "Ocorrências da cidade": lista completa com Recentes / Em Alta e filtros.
class AllOccurrencesScreen extends StatefulWidget {
  const AllOccurrencesScreen({
    super.key,
    this.trending = false,
    this.cityId,
    this.cityName,
  });

  final bool trending;

  /// Cidade da lista; sem valor, usa a cidade selecionada no app.
  final int? cityId;
  final String? cityName;

  @override
  State<AllOccurrencesScreen> createState() => _AllOccurrencesScreenState();
}

class _AllOccurrencesScreenState extends State<AllOccurrencesScreen>
    with OccurrenceListSync {
  final _service = OccurrenceService();
  final _session = AppSession.instance;
  final _scroll = ScrollController();

  late bool _trending = widget.trending;
  OccurrenceFilters _filters = OccurrenceFilters.empty;
  List<CategoryOption> _categories = const [];
  List<Occurrence> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  static const _pageSize = 25;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _loadMore();
    });
    _service
        .fetchCategories()
        .then((value) {
          if (mounted) setState(() => _categories = value);
        })
        .catchError((_) {});
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void onOccurrenceChanged(Occurrence occurrence) =>
      setState(() => _items = replaceIn(_items, occurrence));

  Future<List<Occurrence>> _page(int offset) {
    final cityId = widget.cityId ?? _session.city.value?.id;
    final position = _session.position.value;
    if (_trending && _filters.activeCount == 0) {
      return _service.fetchTrending(
        cityId: cityId,
        limit: _pageSize,
        offset: offset,
      );
    }
    return _service.search(
      cityId: cityId,
      categoryId: _filters.categoryId,
      statusCode: _filters.status?.code,
      neighborhood: _filters.neighborhood,
      latitude: _filters.maxDistanceKm == null ? null : position?.latitude,
      longitude: _filters.maxDistanceKm == null ? null : position?.longitude,
      maxDistanceKm: _filters.maxDistanceKm,
      limit: _pageSize,
      offset: offset,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _page(0);
      if (!mounted) return;
      setState(() {
        _items = _trending && _filters.activeCount > 0
            ? (List.of(items)
                ..sort((a, b) => b.supportsCount.compareTo(a.supportsCount)))
            : items;
        _hasMore = items.length == _pageSize;
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final items = await _page(_items.length);
      if (!mounted) return;
      setState(() {
        _items = [
          ..._items,
          ...items.where(
            (item) => !_items.any((existing) => existing.id == item.id),
          ),
        ];
        _hasMore = items.length == _pageSize;
      });
    } catch (_) {
      // Mantém a lista carregada; o usuário pode puxar para atualizar.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _openFilters() async {
    final result = await showOccurrenceFilterSheet(
      context,
      current: _filters,
      categories: _categories,
    );
    if (result == null) return;
    if (result.maxDistanceKm != null && _session.position.value == null) {
      await _session.requestPosition();
    }
    setState(() => _filters = result);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cityName = widget.cityId != null
        ? widget.cityName
        : _session.city.value?.name;
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Todas as ocorrências'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
          children: [
            UrbEyebrow(cityName ?? 'Sua cidade'),
            const SizedBox(height: 10),
            Text('Ocorrências da cidade', style: UrbText.h1),
            const SizedBox(height: 8),
            Text(
              'Explore problemas recentes e acompanhe a mobilização da comunidade.',
              style: UrbText.body,
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: UrbUnderlineTabs(
                    labels: const ['Recentes', 'Em Alta'],
                    selected: _trending ? 1 : 0,
                    onChanged: (index) {
                      setState(() => _trending = index == 1);
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 9),
                UrbChip(
                  label: _filters.activeCount == 0
                      ? 'Filtros'
                      : 'Filtros · ${_filters.activeCount}',
                  icon: UrbIcons.filter,
                  selected: _filters.activeCount > 0,
                  onTap: _openFilters,
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_loading)
              const OccurrenceListSkeleton(count: 5)
            else if (_error != null)
              UrbErrorState(message: _error!, onRetry: _load)
            else if (_items.isEmpty)
              UrbEmptyState(
                title: 'Nenhuma ocorrência encontrada',
                message:
                    'Tente ajustar os filtros para encontrar outras ocorrências.',
                actionLabel: _filters.activeCount > 0 ? 'Limpar filtros' : null,
                onAction: () {
                  setState(() => _filters = OccurrenceFilters.empty);
                  _load();
                },
              )
            else ...[
              for (var index = 0; index < _items.length; index++)
                FullBleed(
                  child: OccurrenceRow(
                    horizontalInset: 18,
                    occurrence: _items[index],
                    trending: _trending,
                    distanceKm: _session.distanceTo(_items[index]),
                    last: index == _items.length - 1,
                    onOpen: () => openOccurrence(
                      context,
                      occurrenceId: _items[index].id,
                      initial: _items[index],
                    ),
                    onReports: () => openOccurrence(
                      context,
                      occurrenceId: _items[index].id,
                      initial: _items[index],
                      anchor: DetailAnchor.reports,
                    ),
                    onComments: () => openOccurrence(
                      context,
                      occurrenceId: _items[index].id,
                      initial: _items[index],
                      anchor: DetailAnchor.comments,
                    ),
                    onSupport: () =>
                        _session.toggleSupport(context, _items[index]),
                  ),
                ),
              if (_loadingMore)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: UrbLoadingView(),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
