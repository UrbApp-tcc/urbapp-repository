import 'package:flutter/material.dart';

import '../../app/app_session.dart';
import '../../app/routes.dart';
import '../../domain/models.dart';
import '../../logic/administration_workspace_loader.dart';
import '../../logic/administration_workspace_rules.dart';
import '../../services/institutional_service.dart';
import '../../services/notifications_service.dart';
import '../../services/occurrence_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_formatter.dart';
import '../../widgets/urb/city_picker.dart';
import '../../widgets/urb/occurrence_widgets.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';
import '../institutional/workspace_screen.dart';
import '../shell/app_shell.dart';
import '../../widgets/urb/urb_bottom_nav.dart';
import 'all_occurrences_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with OccurrenceListSync {
  final _service = OccurrenceService();
  final _session = AppSession.instance;

  bool _trending = false;
  bool _nearby = true;
  bool _loading = true;
  String? _error;
  List<Occurrence> _items = const [];
  Occurrence? _pendingValidation;
  InstitutionalAccess _access = const InstitutionalAccess();
  Map<int, CouncilorFollowingItem> _councilorFollowings = const {};
  List<OccurrenceReport> _featuredReporters = const [];
  int? _reportersFor;
  final Set<int> _startingCouncilorFollowing = {};
  int _loadRequest = 0;
  AdministrationQuickSummary? _administrationSummary;

  @override
  void initState() {
    super.initState();
    _session.city.addListener(_load);
    _session.contentRevision.addListener(_load);
    _session.position.addListener(_onPosition);
    _load();
    _loadInstitutionalAccess();
  }

  @override
  void dispose() {
    _session.city.removeListener(_load);
    _session.contentRevision.removeListener(_load);
    _session.position.removeListener(_onPosition);
    super.dispose();
  }

  void _onPosition() {
    _loadPendingValidation();
    if (_nearby) _load();
  }

  @override
  void onOccurrenceChanged(Occurrence occurrence) {
    setState(() => _items = replaceIn(_items, occurrence));
  }

  Future<void> _load() async {
    final request = ++_loadRequest;
    var city = _session.city.value;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      if (city == null) {
        await _session.init();
        city = _session.city.value;
      }
      if (city == null) {
        throw Exception(
          _session.initializationError ??
              'Não foi possível carregar as cidades. Tente novamente.',
        );
      }
      final position = _session.position.value;
      List<Occurrence> items;
      if (_trending) {
        items = await _service
            .fetchTrending(cityId: city.id, limit: 20)
            .timeout(const Duration(seconds: 15));
        if (_nearby && position != null) {
          items = items
              .where((item) => (_session.distanceTo(item) ?? 0) <= 10)
              .toList();
        }
      } else if (_nearby && position != null) {
        items = await _service
            .search(
              cityId: city.id,
              latitude: position.latitude,
              longitude: position.longitude,
              maxDistanceKm: 10,
              limit: 20,
            )
            .timeout(const Duration(seconds: 15));
      } else {
        items = await _service
            .fetchRecent(cityId: city.id, limit: 20)
            .timeout(const Duration(seconds: 15));
      }
      if (!mounted || request != _loadRequest) return;
      setState(() => _items = items);
      _loadFeaturedReporters(items.firstOrNull);
      _loadPendingValidation();
    } catch (error) {
      if (mounted && request == _loadRequest) {
        setState(() => _error = friendlyError(error));
      }
    } finally {
      if (mounted && request == _loadRequest) {
        setState(() => _loading = false);
      }
    }
  }

  /// Autores dos relatos do card em destaque, para as miniaturas.
  Future<void> _loadFeaturedReporters(Occurrence? featured) async {
    if (featured == null || _reportersFor == featured.id) return;
    try {
      final reports = await _service.fetchReports(featured.id);
      if (mounted) {
        setState(() {
          _featuredReporters = reports;
          _reportersFor = featured.id;
        });
      }
    } catch (_) {
      // As miniaturas são complementares; o card funciona sem elas.
    }
  }

  Future<void> _loadPendingValidation() async {
    final position = _session.position.value;
    if (position == null) return;
    try {
      final pending = await _service.fetchPendingValidationsNear(
        position.latitude,
        position.longitude,
      );
      if (mounted) setState(() => _pendingValidation = pending.firstOrNull);
    } catch (_) {
      // A chamada de validação é opcional na Home.
    }
  }

  Future<void> _toggleNearby() async {
    if (!_nearby && _session.position.value == null) {
      final position = await _session.requestPosition();
      if (position == null && mounted) {
        showUrbToast(
          context,
          'Permita o acesso à localização para ver ocorrências perto de você.',
        );
        return;
      }
    }
    setState(() => _nearby = !_nearby);
    _load();
  }

  Future<void> _pickCity() async {
    final picked = await showCityPicker(
      context,
      cities: _session.cities,
      selected: _session.city.value,
    );
    if (picked != null && picked.id != _session.city.value?.id) {
      _session.city.value = picked;
      if (mounted) showUrbToast(context, 'Cidade alterada para ${picked.name}');
    }
  }

  void _open(Occurrence occurrence, [DetailAnchor anchor = DetailAnchor.top]) =>
      openOccurrence(
        context,
        occurrenceId: occurrence.id,
        initial: occurrence,
        anchor: anchor,
      );

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
      await _loadAdministrationSummary(access);
    } catch (_) {
      // A Home cidadã continua funcional se o contexto institucional falhar.
    }
  }

  Future<void> _loadAdministrationSummary(InstitutionalAccess access) async {
    final administration = access.administrations.firstOrNull;
    if (administration == null) return;
    try {
      final items = await loadAdministrationDemandItems(administration.id);
      if (mounted) {
        setState(
          () => _administrationSummary = buildAdministrationQuickSummary(items),
        );
      }
    } catch (_) {
      // O resumo é complementar; o acesso à área institucional permanece.
    }
  }

  Future<void> _openAdministrationWorkspace() async {
    await Navigator.of(context).push(urbRoute(const WorkspaceScreen()));
    if (mounted) {
      await _loadAdministrationSummary(_access);
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
        showUrbToast(
          context,
          'Acompanhamento institucional iniciado. Registre sua primeira atuação.',
        );
      }
      await _loadInstitutionalAccess();
    } catch (error) {
      if (mounted) showUrbToast(context, friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _startingCouncilorFollowing.remove(occurrence.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final city = _session.city.value;
    final featured = _items.firstOrNull;
    final rest = _items.skip(1).take(6).toList();
    final hasPosition = _session.position.value != null;
    final nearbyActive = _nearby && hasPosition;

    return RefreshIndicator(
      color: UrbColors.blue,
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                const Positioned(
                  top: -90,
                  right: -55,
                  child: UrbBrandGeometry(large: false),
                ),
                Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: UrbColors.divider),
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    20,
                    MediaQuery.paddingOf(context).top + 22,
                    20,
                    17,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const UrbBrand(compact: true),
                          const Spacer(),
                          ValueListenableBuilder<int>(
                            valueListenable: NotificationsService.unreadCount,
                            builder: (context, count, _) => UrbBellButton(
                              unreadCount: count,
                              onPressed: () => openAlerts(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 23),
                      CitySelectorButton(city: city, onTap: _pickCity),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 30),
            sliver: SliverList.list(
              children: [
                if (_pendingValidation != null) ...[
                  UrbCallout(
                    eyebrow: 'Sua participação importa',
                    title: 'Uma ocorrência próxima aguarda validação',
                    message: 'Confirme se o problema foi realmente resolvido.',
                    onTap: () => openValidation(context, _pendingValidation!),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_access.hasInstitutionalRole) ...[
                  if (_access.administrations.isNotEmpty &&
                      _administrationSummary != null)
                    _AdministrationSummaryEntry(
                      summary: _administrationSummary!,
                      cityName:
                          _access.administrations.first.cityName ??
                          'sua cidade',
                      onOpen: _openAdministrationWorkspace,
                    )
                  else
                    _WorkspaceEntry(
                      access: _access,
                      followings: _councilorFollowings.values.toList(),
                    ),
                  const SizedBox(height: 12),
                ],
                UrbUnderlineTabs(
                  labels: const ['Recentes', 'Em Alta'],
                  selected: _trending ? 1 : 0,
                  onChanged: (index) {
                    setState(() {
                      _trending = index == 1;
                      _items = const [];
                    });
                    _load();
                  },
                ),
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _trending
                              ? 'Mobilizando a comunidade'
                              : (nearbyActive
                                    ? 'Ordenadas por distância'
                                    : 'Ordenadas por publicação'),
                          style: UrbText.meta,
                        ),
                      ),
                      UrbChip(
                        label: 'Perto de mim',
                        icon: UrbIcons.location,
                        selected: nearbyActive,
                        onTap: _toggleNearby,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                UrbSectionHeader(
                  eyebrow: nearbyActive
                      ? 'Perto de você'
                      : 'Agora em ${city?.name ?? 'sua cidade'}',
                  title: _trending ? 'Em alta na cidade' : 'Precisa de atenção',
                ),
                const SizedBox(height: 13),
                if (_loading)
                  const OccurrenceListSkeleton()
                else if (_error != null)
                  UrbErrorState(message: _error!, onRetry: _load)
                else if (featured == null)
                  UrbEmptyState(
                    icon: UrbIcons.location,
                    title: nearbyActive
                        ? 'Nenhuma ocorrência por perto'
                        : 'Nenhuma ocorrência registrada',
                    message: nearbyActive
                        ? 'Desative "Perto de mim" para ver toda a cidade ou relate um problema que você encontrou.'
                        : 'Seja a primeira pessoa a relatar um problema em ${city?.name ?? 'sua cidade'}.',
                    actionLabel: 'Relatar um problema',
                    onAction: () => openReportFlow(context),
                    secondaryLabel: nearbyActive ? 'Ver toda a cidade' : null,
                    onSecondary: nearbyActive ? _toggleNearby : null,
                  )
                else ...[
                  // Largura total da tela: sai do recuo lateral da lista.
                  LayoutBuilder(
                    builder: (context, constraints) => UnconstrainedBox(
                      constrainedAxis: Axis.vertical,
                      child: SizedBox(
                        width: constraints.maxWidth + 36,
                        child: FeaturedOccurrenceCard(
                          fullBleed: true,
                          occurrence: featured,
                          reporters: _reportersFor == featured.id
                              ? _featuredReporters
                              : const [],
                          distanceKm: _session.distanceTo(featured),
                          onOpen: () => _open(featured),
                          onReports: () =>
                              _open(featured, DetailAnchor.reports),
                          onComments: () =>
                              _open(featured, DetailAnchor.comments),
                          onSupport: () =>
                              _session.toggleSupport(context, featured),
                          onFollow: () =>
                              _session.toggleFollow(context, featured),
                          onShare: () => _session.share(context, featured),
                          councilorStatus:
                              _councilorFollowings[featured.id]?.status,
                          onCouncilorAction:
                              _access.isCouncilor &&
                                  featured.cityId ==
                                      _access.councilor?.cityId &&
                                  (!featured.status.isFinal ||
                                      _councilorFollowings.containsKey(
                                        featured.id,
                                      ))
                              ? () => _councilorAction(featured)
                              : null,
                        ),
                      ),
                    ),
                  ),
                  if (rest.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    UrbSectionHeader(
                      title: _trending
                          ? 'Em alta agora'
                          : 'Ocorrências recentes',
                      subtitle: _trending
                          ? 'Ocorrências com mobilização crescente'
                          : 'Acompanhe o que está acontecendo na cidade',
                      trailing: UrbSeeAll(
                        onPressed: () => Navigator.of(context).push(
                          urbRoute(AllOccurrencesScreen(trending: _trending)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (var index = 0; index < rest.length; index++)
                      FullBleed(
                        child: OccurrenceRow(
                          horizontalInset: 18,
                          occurrence: rest[index],
                          trending: _trending,
                          distanceKm: _session.distanceTo(rest[index]),
                          last: index == rest.length - 1,
                          onOpen: () => _open(rest[index]),
                          onReports: () =>
                              _open(rest[index], DetailAnchor.reports),
                          onComments: () =>
                              _open(rest[index], DetailAnchor.comments),
                          onSupport: () =>
                              _session.toggleSupport(context, rest[index]),
                          councilorStatus:
                              _councilorFollowings[rest[index].id]?.status,
                          onCouncilorAction:
                              _access.isCouncilor &&
                                  rest[index].cityId ==
                                      _access.councilor?.cityId &&
                                  (!rest[index].status.isFinal ||
                                      _councilorFollowings.containsKey(
                                        rest[index].id,
                                      ))
                              ? () => _councilorAction(rest[index])
                              : null,
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdministrationSummaryEntry extends StatelessWidget {
  const _AdministrationSummaryEntry({
    required this.summary,
    required this.cityName,
    required this.onOpen,
  });

  final AdministrationQuickSummary summary;
  final String cityName;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        '${summary.needsAttention}',
        'Precisam de atenção',
        const Color(0xFFF0F2FF),
        const Color(0xFFCAD0FF),
        UrbColors.blue,
      ),
      (
        '${summary.withoutManagementResponse}',
        'Sem manifestação',
        const Color(0xFFFFF7E8),
        const Color(0xFFF2D9A7),
        const Color(0xFF9A6400),
      ),
      (
        summary.forecastLabel(DateTime.now()),
        'Próxima previsão',
        const Color(0xFFEDF7F4),
        const Color(0xFFBFDCD3),
        const Color(0xFF20735E),
      ),
      (
        '${summary.prioritized}',
        'Priorizadas',
        const Color(0xFFF7F1FA),
        const Color(0xFFDDC6E8),
        const Color(0xFF7D4B91),
      ),
    ];
    return Column(
      children: [
        Text(
          'Resumo da atuação',
          textAlign: TextAlign.center,
          style: UrbText.titleSmall.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          'Gestão municipal · $cityName',
          textAlign: TextAlign.center,
          style: UrbText.caption,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              Expanded(
                child: Material(
                  color: items[index].$3,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: items[index].$4),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onOpen,
                    overlayColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.pressed)
                          ? items[index].$5.withValues(alpha: 0.10)
                          : Colors.transparent,
                    ),
                    child: SizedBox(
                      height: 82,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 9,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              items[index].$1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: UrbText.h3.copyWith(
                                color: items[index].$5,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              items[index].$2,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: UrbText.caption.copyWith(
                                fontSize: 10,
                                height: 1.15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (index != items.length - 1) const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }
}

/// Entrada discreta para a área de atuação de quem tem papel institucional.
class _WorkspaceEntry extends StatelessWidget {
  const _WorkspaceEntry({required this.access, required this.followings});

  final InstitutionalAccess access;
  final List<CouncilorFollowingItem> followings;

  @override
  Widget build(BuildContext context) {
    final roles = [
      if (access.isCouncilor) 'Vereador',
      if (access.agencies.isNotEmpty) access.agencies.first.name,
      if (access.administrations.isNotEmpty) 'Gestão municipal',
    ];
    final awaiting = followings
        .where((item) => item.status == 'awaiting_response')
        .length;
    final active = followings
        .where((item) => item.status != 'ended' && item.status != 'resolved')
        .length;
    final summary = access.isCouncilor
        ? [
            '$active acompanhando',
            if (awaiting > 0) '$awaiting aguardando retorno',
          ].join(' · ')
        : roles.join(' · ');
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          // Vereador: a atuação mora no próprio Perfil.
          final shell = AppShell.of(context);
          final councilorOnly =
              access.isCouncilor &&
              access.agencies.isEmpty &&
              access.administrations.isEmpty;
          if (councilorOnly && shell != null) {
            shell.selectTab(UrbTab.profile);
          } else {
            Navigator.of(context).push(urbRoute(const WorkspaceScreen()));
          }
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: UrbColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: UrbColors.blueSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: const UrbIcon(
                  UrbIcons.building,
                  size: 17,
                  color: UrbColors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sua atuação',
                      style: UrbText.titleSmall.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.caption.copyWith(
                        color: awaiting > 0
                            ? UrbColors.warning
                            : UrbColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const UrbIcon(UrbIcons.chevron, size: 16, color: UrbColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
