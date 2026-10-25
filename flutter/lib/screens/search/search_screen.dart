import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../app/app_session.dart';
import '../../app/routes.dart';
import '../../domain/labels.dart';
import '../../domain/models.dart';
import '../../services/notifications_service.dart';
import '../../services/institutional_service.dart';
import '../../services/occurrence_service.dart';
import '../../services/transparency_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/filter_sheet.dart';
import '../../widgets/urb/occurrence_map.dart';
import '../../widgets/urb/occurrence_widgets.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import '../institutional/workspace_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends State<SearchScreen> with OccurrenceListSync {
  final _service = OccurrenceService();
  final _transparency = TransparencyService();
  final _session = AppSession.instance;
  final _queryController = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  static final List<String> _recentSearches = [];

  bool _mapMode = false;
  bool _showAll = false;
  bool _loading = true;
  String? _error;
  OccurrenceFilters _filters = OccurrenceFilters.empty;
  List<CategoryOption> _categories = const [];
  List<Occurrence> _results = const [];
  List<InstitutionSearchResult> _institutions = const [];
  Occurrence? _selectedOnMap;
  InstitutionalAccess _access = const InstitutionalAccess();
  Map<int, CouncilorFollowingItem> _councilorFollowings = const {};
  final Set<int> _startingCouncilorFollowing = {};
  int _requestId = 0;

  String get _query => _queryController.text.trim();
  bool get _searching => _query.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    _session.city.addListener(_search);
    _session.contentRevision.addListener(_search);
    _service
        .fetchCategories()
        .then((value) {
          if (mounted) setState(() => _categories = value);
        })
        .catchError((_) {});
    _loadInstitutionalAccess();
    _search();
  }

  @override
  void dispose() {
    _session.city.removeListener(_search);
    _session.contentRevision.removeListener(_search);
    _debounce?.cancel();
    _queryController.dispose();
    _focus.dispose();
    super.dispose();
  }

  void showMap() => setState(() {
    _mapMode = true;
    _focus.unfocus();
  });

  @override
  void onOccurrenceChanged(Occurrence occurrence) {
    setState(() {
      _results = replaceIn(_results, occurrence);
      if (_selectedOnMap?.id == occurrence.id) _selectedOnMap = occurrence;
    });
  }

  void _onQueryChanged(String _) {
    setState(() => _selectedOnMap = null);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    final requestId = ++_requestId;
    final city = _session.city.value;
    final position = _session.position.value;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final useDistance =
          _filters.maxDistanceKm != null ||
          (!_searching && _filters.activeCount == 0);
      var results = await _service.search(
        text: _query,
        cityId: city?.id,
        categoryId: _filters.categoryId,
        statusCode: _filters.status?.code,
        neighborhood: _filters.neighborhood,
        latitude: useDistance ? position?.latitude : null,
        longitude: useDistance ? position?.longitude : null,
        maxDistanceKm: _filters.maxDistanceKm,
        limit: _mapMode ? 120 : 40,
      );
      if (_filters.councilorScope == CouncilorOccurrenceScope.mine &&
          _access.isCouncilor) {
        final mine = await InstitutionalService().fetchFollowingOccurrenceIds(
          results.map((item) => item.id),
          councilorProfileId: _access.councilor!.id,
        );
        results = results.where((item) => mine.contains(item.id)).toList();
      } else if (_filters.councilorScope ==
          CouncilorOccurrenceScope.unattended) {
        final attended = await InstitutionalService()
            .fetchFollowingOccurrenceIds(results.map((item) => item.id));
        results = results.where((item) => !attended.contains(item.id)).toList();
      }
      final institutions = _searching && city != null
          ? await _transparency.searchInstitutions(city.id, _query)
          : const <InstitutionSearchResult>[];
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = results;
        _institutions = institutions;
      });
    } catch (error) {
      if (mounted && requestId == _requestId) {
        setState(() => _error = friendlyError(error));
      }
    } finally {
      if (mounted && requestId == _requestId) setState(() => _loading = false);
    }
  }

  Future<void> _loadInstitutionalAccess() async {
    try {
      final service = InstitutionalService();
      final access = await service.fetchMyAccess();
      var followings = const <CouncilorFollowingItem>[];
      if (access.isCouncilor) {
        followings = await service.fetchCouncilorFollowings(
          access.councilor!.id,
          activeOnly: true,
        );
      }
      if (!mounted) return;
      setState(() {
        _access = access;
        _councilorFollowings = {
          for (final item in followings) item.occurrenceId: item,
        };
      });
    } catch (_) {
      // A busca pública permanece disponível sem o contexto institucional.
    }
  }

  /// "Acompanhando" desfaz o acompanhamento, com confirmação: o encerramento
  /// fica registrado no histórico público.
  Future<void> _endFollowing(Occurrence occurrence, int followingId) async {
    final confirmed = await UrbConfirmSheet.show(
      context,
      title: 'Encerrar acompanhamento?',
      message:
          'O encerramento fica registrado publicamente. Você poderá retomar se a ocorrência continuar aberta.',
      confirmLabel: 'Encerrar acompanhamento',
    );
    if (!confirmed || !mounted) return;
    try {
      await InstitutionalService().endCouncilorFollowing(
        followingId: followingId,
        description: 'Acompanhamento encerrado pelo vereador.',
      );
      if (mounted) showUrbToast(context, 'Acompanhamento encerrado.');
      await _loadInstitutionalAccess();
      if (_filters.councilorScope != null) await _search();
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    }
  }

  Future<void> _councilorAction(Occurrence occurrence) async {
    final following = _councilorFollowings[occurrence.id];
    if (following != null) {
      await _endFollowing(occurrence, following.followingId);
      return;
    }
    if (_startingCouncilorFollowing.contains(occurrence.id)) return;
    setState(() => _startingCouncilorFollowing.add(occurrence.id));
    try {
      await InstitutionalService().startCouncilorFollowing(occurrence.id);
      if (mounted) {
        showUrbToast(context, 'Acompanhamento institucional iniciado.');
      }
      await _loadInstitutionalAccess();
      if (_filters.councilorScope != null) await _search();
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _startingCouncilorFollowing.remove(occurrence.id));
      }
    }
  }

  void _submit(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    _recentSearches
      ..removeWhere((item) => item.toLowerCase() == query.toLowerCase())
      ..insert(0, query);
    if (_recentSearches.length > 5) _recentSearches.removeLast();
    _focus.unfocus();
    _search();
  }

  Future<void> _openFilters() async {
    final result = await showOccurrenceFilterSheet(
      context,
      current: _filters,
      categories: _categories,
      showCouncilorFilters: _access.isCouncilor,
    );
    if (result == null) return;
    if (result.maxDistanceKm != null && _session.position.value == null) {
      final position = await _session.requestPosition();
      if (position == null && mounted) {
        showUrbToast(
          context,
          'Permita o acesso à localização para filtrar por distância.',
        );
      }
    }
    setState(() {
      _filters = result;
      _selectedOnMap = null;
    });
    _search();
  }

  void _open(Occurrence occurrence, [DetailAnchor anchor = DetailAnchor.top]) =>
      openOccurrence(
        context,
        occurrenceId: occurrence.id,
        initial: occurrence,
        anchor: anchor,
      );

  @override
  Widget build(BuildContext context) {
    final city = _session.city.value;
    final focusedEmpty = _focus.hasFocus && !_searching;
    return Column(
      children: [
        UrbScreenHeader(
          title: 'Buscar',
          subtitle: 'Encontre problemas e acompanhe sua cidade',
          bordered: true,
          actions: [
            if (city != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: UrbColors.blueSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const UrbIcon(
                      UrbIcons.location,
                      size: 13,
                      color: UrbColors.blue,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      city.name,
                      style: UrbText.caption.copyWith(
                        color: UrbColors.blue,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ValueListenableBuilder<int>(
              valueListenable: NotificationsService.unreadCount,
              builder: (context, count, _) => UrbBellButton(
                unreadCount: count,
                onPressed: () => openAlerts(context),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 13, 18, 0),
          child: Row(
            children: [
              Expanded(child: _searchField()),
              if (!focusedEmpty) ...[
                const SizedBox(width: 7),
                _ToolbarButton(
                  icon: _mapMode ? UrbIcons.list : UrbIcons.map,
                  label: _mapMode ? 'Lista' : 'Mapa',
                  highlighted: true,
                  onTap: () {
                    setState(() {
                      _mapMode = !_mapMode;
                      _selectedOnMap = null;
                    });
                    _search();
                  },
                ),
                const SizedBox(width: 7),
                _ToolbarButton(
                  icon: UrbIcons.filter,
                  badge: _filters.activeCount,
                  highlighted: _filters.activeCount > 0,
                  tooltip: 'Filtros',
                  onTap: _openFilters,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: focusedEmpty && _recentSearches.isNotEmpty
              ? _recentList()
              : (_mapMode ? _mapView(city) : _listView()),
        ),
      ],
    );
  }

  Widget _searchField() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(UrbRadius.md),
        border: Border.all(
          color: _focus.hasFocus ? UrbColors.blue : const Color(0xFFD6DDE2),
        ),
        boxShadow: _focus.hasFocus
            ? [
                BoxShadow(
                  color: UrbColors.blue.withValues(alpha: 0.09),
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          const UrbIcon(UrbIcons.search, size: 17, color: Color(0xFF8792A0)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _queryController,
              focusNode: _focus,
              onChanged: _onQueryChanged,
              onSubmitted: _submit,
              textInputAction: TextInputAction.search,
              style: UrbText.bodySmall.copyWith(
                color: UrbColors.navy,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Buscar ocorrências, ruas, bairros…',
                hintStyle: UrbText.bodySmall.copyWith(
                  color: const Color(0xFF9AA5B0),
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_searching)
            UrbTextButton(
              'Limpar',
              onPressed: () {
                _queryController.clear();
                _search();
              },
            )
          else if (_focus.hasFocus)
            UrbTextButton('Cancelar', onPressed: () => _focus.unfocus()),
        ],
      ),
    );
  }

  Widget _recentList() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      children: [
        UrbSectionHeader(
          title: 'Buscas recentes',
          trailing: UrbTextButton(
            'Limpar buscas',
            onPressed: () => setState(_recentSearches.clear),
          ),
        ),
        const SizedBox(height: 8),
        for (final recent in List.of(_recentSearches))
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    _queryController.text = recent;
                    _submit(recent);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        const UrbIcon(
                          UrbIcons.search,
                          size: 14,
                          color: Color(0xFF526176),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          recent,
                          style: UrbText.bodySmall.copyWith(
                            color: const Color(0xFF526176),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remover busca $recent',
                onPressed: () => setState(() => _recentSearches.remove(recent)),
                icon: const UrbIcon(
                  UrbIcons.close,
                  size: 14,
                  color: Color(0xFF9AA3AD),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _listView() {
    final visible = _showAll || _searching || _filters.activeCount > 0
        ? _results
        : _results.take(5).toList();
    final nearbyLabel = _session.position.value != null
        ? 'Perto de você'
        : 'Recentes na cidade';
    return RefreshIndicator(
      onRefresh: _search,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
        children: [
          if (!_searching && _access.hasInstitutionalRole) ...[
            _institutionalShortcut(),
            const SizedBox(height: 16),
          ],
          UrbSectionHeader(
            title: _searching ? 'Resultados para “$_query”' : nearbyLabel,
            subtitle: _searching
                ? '${_results.length} ${_results.length == 1 ? 'ocorrência encontrada' : 'ocorrências encontradas'}'
                : 'Veja o que está acontecendo ao seu redor',
          ),
          if (_searching && _results.isNotEmpty) ...[
            const SizedBox(height: 12),
            _DuplicateCue(),
          ],
          if (_institutions.isNotEmpty) ...[
            const SizedBox(height: 14),
            const UrbEyebrow('Instituições', muted: true),
            const SizedBox(height: 4),
            for (var index = 0; index < _institutions.length; index++)
              UrbDotRow(
                title: _institutions[index].name,
                subtitle: _institutions[index].detail,
                dotColor: _institutions[index].kind == 'agency'
                    ? UrbColors.blue
                    : UrbColors.violet,
                last: index == _institutions.length - 1,
                onTap: () => _institutions[index].kind == 'agency'
                    ? openAgency(context, _institutions[index].id)
                    : openCouncilor(context, _institutions[index].id),
              ),
          ],
          const SizedBox(height: 4),
          if (_loading && _results.isEmpty)
            const OccurrenceListSkeleton()
          else if (_error != null)
            UrbErrorState(message: _error!, onRetry: _search)
          else if (_results.isEmpty)
            UrbEmptyState(
              title: _filters.maxDistanceKm != null && !_searching
                  ? 'Nenhuma ocorrência próxima'
                  : 'Nenhuma ocorrência encontrada',
              message: _filters.maxDistanceKm != null && !_searching
                  ? 'Tente aumentar a distância ou explorar outras regiões da cidade.'
                  : 'Não encontramos ocorrências para esta busca.',
              secondaryLabel: _searching ? 'Limpar busca' : null,
              onSecondary: () {
                _queryController.clear();
                _search();
              },
              actionLabel: _filters.activeCount > 0
                  ? 'Limpar filtros'
                  : 'Ajustar filtros',
              onAction: () {
                if (_filters.activeCount > 0) {
                  setState(() => _filters = OccurrenceFilters.empty);
                  _search();
                } else {
                  _openFilters();
                }
              },
            )
          else ...[
            for (var index = 0; index < visible.length; index++)
              FullBleed(
                child: OccurrenceRow(
                  horizontalInset: 18,
                  occurrence: visible[index],
                  distanceKm: _session.distanceTo(visible[index]),
                  last: index == visible.length - 1,
                  onOpen: () => _open(visible[index]),
                  onReports: () => _open(visible[index], DetailAnchor.reports),
                  onComments: () =>
                      _open(visible[index], DetailAnchor.comments),
                  onSupport: () =>
                      _session.toggleSupport(context, visible[index]),
                  councilorStatus:
                      _councilorFollowings[visible[index].id]?.status,
                  onCouncilorAction:
                      _access.isCouncilor &&
                          visible[index].cityId == _access.councilor?.cityId &&
                          !visible[index].status.isFinal
                      ? () => _councilorAction(visible[index])
                      : null,
                ),
              ),
            if (visible.length < _results.length)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: UrbButton(
                  label: 'Ver mais',
                  tone: UrbButtonTone.outline,
                  expand: true,
                  height: 42,
                  onPressed: () => setState(() => _showAll = true),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _institutionalShortcut() {
    final administration = _access.administrations.firstOrNull;
    final agency = _access.agencies.firstOrNull;
    final detail = administration != null
        ? '${administration.roleLabel} da Prefeitura · ${administration.cityName ?? administration.name}'
        : agency != null
        ? '${agency.roleLabel} · ${agency.name}'
        : 'Atuação parlamentar na cidade';
    return Material(
      color: const Color(0xFFF2F4FF),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            Navigator.of(context).push(urbRoute(const WorkspaceScreen())),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: const UrbIcon(
                  UrbIcons.building,
                  size: 18,
                  color: UrbColors.blue,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sua atuação institucional', style: UrbText.label),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const UrbIcon(UrbIcons.chevron, size: 16, color: UrbColors.blue),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mapView(CityOption? city) {
    final position = _session.position.value;
    final center = _results.isNotEmpty
        ? LatLng(_results.first.latitude, _results.first.longitude)
        : (position != null
              ? LatLng(position.latitude, position.longitude)
              : const LatLng(-23.5015, -47.4526));
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 14),
      child: Stack(
        children: [
          Positioned.fill(
            child: OccurrenceMap(
              key: ValueKey('map-${city?.id}-${_results.length}'),
              occurrences: _results,
              center: center,
              selectedId: _selectedOnMap?.id,
              label:
                  '${city?.name ?? 'Cidade'} · ${plural(_results.length, 'ocorrência', 'ocorrências')}',
              onSelect: (occurrence) =>
                  setState(() => _selectedOnMap = occurrence),
            ),
          ),
          if (_results.isEmpty && !_loading)
            Center(
              child: Container(
                width: 240,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Nenhuma ocorrência no mapa',
                      style: UrbText.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ajuste sua busca ou os filtros.',
                      style: UrbText.caption,
                    ),
                  ],
                ),
              ),
            ),
          if (_selectedOnMap != null)
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: _MapPreview(
                occurrence: _selectedOnMap!,
                distanceKm: _session.distanceTo(_selectedOnMap!),
                onOpen: () => _open(_selectedOnMap!),
                onSupport: () =>
                    _session.toggleSupport(context, _selectedOnMap!),
              ),
            ),
        ],
      ),
    );
  }
}

class _DuplicateCue extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4FF),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: UrbColors.lime,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const UrbIcon(
              UrbIcons.check,
              size: 15,
              color: UrbColors.navy,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Encontrou o mesmo problema?',
                  style: UrbText.label.copyWith(
                    fontWeight: FontWeight.w800,
                    color: UrbColors.navy,
                  ),
                ),
                Text(
                  'Abra a ocorrência e adicione seu relato em vez de criar uma nova.',
                  style: UrbText.caption.copyWith(
                    color: const Color(0xFF778394),
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

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.onTap,
    this.label,
    this.badge = 0,
    this.highlighted = false,
    this.tooltip,
  });

  final UrbIcons icon;
  final String? label;
  final int badge;
  final bool highlighted;
  final String? tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = highlighted ? UrbColors.blue : const Color(0xFF687687);
    return Tooltip(
      message: tooltip ?? label ?? '',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: highlighted ? UrbColors.blueSoft : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(UrbRadius.md),
              side: BorderSide(
                color: highlighted
                    ? UrbColors.blue.withValues(alpha: 0.18)
                    : const Color(0xFFDCE2E5),
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(UrbRadius.md),
              onTap: onTap,
              child: SizedBox(
                height: 48,
                width: label == null ? 48 : null,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: label == null ? 0 : 11,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      UrbIcon(icon, size: 16, color: foreground),
                      if (label != null) ...[
                        const SizedBox(width: 5),
                        Text(
                          label!,
                          style: UrbText.caption.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (badge > 0)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: UrbColors.blue,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$badge',
                  style: UrbText.caption.copyWith(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MapPreview extends StatelessWidget {
  const _MapPreview({
    required this.occurrence,
    required this.onOpen,
    required this.onSupport,
    this.distanceKm,
  });

  final Occurrence occurrence;
  final VoidCallback onOpen;
  final VoidCallback onSupport;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.97),
      elevation: 0,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFDDE3E3)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2B11233D),
                blurRadius: 32,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OccurrenceImage(
                url: occurrence.primaryImageUrl,
                categoryName: occurrence.categoryName,
                categorySlug: occurrence.categorySlug,
                width: 84,
                height: 116,
                radius: 9,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      occurrence.categoryName.toUpperCase(),
                      style: UrbText.eyebrow.copyWith(
                        fontSize: 10,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      occurrence.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.titleSmall.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        occurrence.locationLabel,
                        if (distanceKm != null) formatDistance(distanceKm!),
                      ].join(' · '),
                      style: UrbText.caption,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusPill(occurrence.status, compact: true),
                        Text(
                          plural(occurrence.reportsCount, 'relato', 'relatos'),
                          style: UrbText.caption,
                        ),
                        SocialMetaButton(
                          icon: UrbIcons.heart,
                          label: '${occurrence.supportsCount}',
                          active: occurrence.supportedByMe,
                          onTap: onSupport,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    UrbButton(
                      label: 'Ver ocorrência',
                      height: 34,
                      onPressed: onOpen,
                    ),
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
