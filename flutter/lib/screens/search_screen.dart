import 'dart:async';

import 'package:flutter/material.dart';

import '../services/city_service.dart';
import '../services/feed_service.dart';
import '../theme/urbapp_design.dart';
import '../widgets/city_picker_sheet.dart';
import '../widgets/city_skyline.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/urb_post_image.dart';
import '../widgets/urb_status_chip.dart';
import 'city_ranking_screen.dart';
import 'post_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.posts,
    required this.isLoading,
    required this.currentUserId,
    required this.cities,
    required this.selectedCityId,
    required this.onCityChanged,
  });

  final List<FeedPost> posts;
  final bool isLoading;
  final String? currentUserId;

  /// Cidades disponíveis e a cidade escolhida (a mesma do Início).
  final List<CityOption> cities;
  final int? selectedCityId;
  final ValueChanged<int?> onCityChanged;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _selectedStatus;
  _Occurrence? _selectedOccurrence;

  /// Atalhos para buscar pelo tipo de problema.
  /// As palavras ficam sem acento, igual ao texto normalizado da busca.
  static const List<_Occurrence> _occurrences = [
    _Occurrence('Alagamento', Icons.water_drop_outlined, [
      'alagamento',
      'alagad',
      'enchente',
      'inund',
    ]),
    _Occurrence('Buraco', Icons.construction_rounded, [
      'buraco',
      'cratera',
      'asfalto',
    ]),
    _Occurrence('Poste e iluminação', Icons.lightbulb_outline_rounded, [
      'poste',
      'iluminacao',
      'lampada',
      'apagad',
    ]),
    _Occurrence('Lixo', Icons.delete_outline_rounded, [
      'lixo',
      'entulho',
      'descarte',
    ]),
    _Occurrence('Queimada', Icons.local_fire_department_outlined, [
      'queimada',
      'fogo',
      'incendio',
    ]),
    _Occurrence('Esgoto', Icons.plumbing_rounded, [
      'esgoto',
      'bueiro',
      'vazamento',
    ]),
    _Occurrence('Árvore', Icons.park_outlined, ['arvore', 'galho', 'poda']),
    _Occurrence('Calçada', Icons.directions_walk_rounded, [
      'calcada',
      'passeio',
    ]),
    _Occurrence('Trânsito e sinalização', Icons.traffic_outlined, [
      'semaforo',
      'sinalizacao',
      'placa',
      'transito',
    ]),
  ];

  static const List<String> _statusOptions = [
    'open',
    'in_analysis',
    'in_progress',
    'completed',
    'closed',
    'expired',
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  static String _haystack(FeedPost post) {
    return _normalizeSearchText(
      [
        post.title,
        post.description,
        post.categoryName,
        post.cityName,
        post.street ?? '',
        post.neighborhood ?? '',
        post.authorDisplayName,
        post.agencyName ?? '',
      ].join(' '),
    );
  }

  static String _normalizeSearchText(String value) {
    const replacements = {
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
    };

    var normalized = value.trim().toLowerCase();
    replacements.forEach((source, target) {
      normalized = normalized.replaceAll(source, target);
    });
    return normalized;
  }

  bool get _hasActiveSearch =>
      _query.trim().isNotEmpty || _selectedOccurrence != null;

  CityOption? get _selectedCity {
    final id = widget.selectedCityId;
    if (id == null) return null;
    return widget.cities.where((city) => city.id == id).firstOrNull;
  }

  Future<void> _chooseCity() async {
    final result = await showCityPickerSheet(
      context,
      cities: widget.cities,
      selectedCityId: widget.selectedCityId,
      allowAllCities: true,
    );
    if (result == null || !mounted) return;
    widget.onCityChanged(result.cityId);
  }

  List<FeedPost> get _textResults {
    final raw = _normalizeSearchText(_query);
    final terms = raw.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final occurrence = _selectedOccurrence;

    if (terms.isEmpty && occurrence == null) return widget.posts;

    return widget.posts.where((post) {
      final haystack = _haystack(post);
      final matchesText = terms.every((term) => haystack.contains(term));
      final matchesOccurrence =
          occurrence == null || occurrence.keywords.any(haystack.contains);
      return matchesText && matchesOccurrence;
    }).toList();
  }

  List<FeedPost> get _results {
    final textResults = _textResults;
    if (!_hasActiveSearch || _selectedStatus == null) return textResults;
    return textResults.where((post) => post.status == _selectedStatus).toList();
  }

  void _onQueryChanged(String value) {
    setState(() {}); // atualiza o botão de limpar na hora
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _query = value;
        if (value.trim().isEmpty && _selectedOccurrence == null) {
          _selectedStatus = null;
        }
      });
    });
  }

  void _clearQuery() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _query = '';
      if (_selectedOccurrence == null) _selectedStatus = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final highlights = results.take(2).toList();
    final showEmpty = !widget.isLoading && results.isEmpty;

    return ColoredBox(
      color: UrbColors.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 132),
        children: [
          _SearchHeader(
            controller: _controller,
            onChanged: _onQueryChanged,
            onClear: _clearQuery,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FadeSlideIn(
                  delay: const Duration(milliseconds: 60),
                  child: _CityFilterButton(
                    label: _selectedCity?.name ?? 'Todas as cidades',
                    onPressed: widget.cities.isEmpty ? null : _chooseCity,
                  ),
                ),
                const SizedBox(height: 22),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 120),
                  child: _OccurrenceBar(
                    occurrences: _occurrences,
                    selected: _selectedOccurrence,
                    onSelected: (occurrence) => setState(() {
                      _selectedOccurrence = _selectedOccurrence == occurrence
                          ? null
                          : occurrence;
                      if (!_hasActiveSearch) _selectedStatus = null;
                    }),
                  ),
                ),
                const SizedBox(height: 20),
                // Os filtros aparecem deslizando quando a pessoa começa a buscar.
                AnimatedSize(
                  duration: UrbMotion.of(context, UrbMotion.medium),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _hasActiveSearch
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: _StatusFilters(
                            options: _statusOptions,
                            selected: _selectedStatus,
                            onSelected: (status) => setState(() {
                              _selectedStatus = _selectedStatus == status
                                  ? null
                                  : status;
                            }),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                FadeSlideIn(
                  child: _RankingPromoCard(
                    onOpen: () => CityRankingScreen.open(
                      context,
                      currentUserId: widget.currentUserId,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                if (widget.isLoading) ...[
                  const _SectionTitle(title: 'Destaques', count: '—'),
                  const SizedBox(height: 14),
                  const Row(
                    children: [
                      Expanded(child: UrbSkeleton(height: 150, radius: 22)),
                      SizedBox(width: 14),
                      Expanded(child: UrbSkeleton(height: 150, radius: 22)),
                    ],
                  ),
                  const SizedBox(height: 28),
                  const _SectionTitle(title: 'Resultados', count: '—'),
                  const SizedBox(height: 14),
                  for (var i = 0; i < 4; i++) ...[
                    const _ResultSkeleton(),
                    const SizedBox(height: 12),
                  ],
                ] else if (showEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: FadeSlideIn(
                      child: UrbEmptyState(
                        icon: widget.posts.isEmpty
                            ? Icons.location_city_rounded
                            : Icons.search_off_rounded,
                        title: widget.posts.isEmpty
                            ? 'Nenhum reporte ainda'
                            : 'Nenhum resultado para essa busca',
                        text: widget.posts.isEmpty
                            ? 'Quando houver reportes na lista principal, você poderá pesquisar por título, cidade, categoria e mais. Toque no + para criar o primeiro.'
                            : 'Tente outras palavras ou verifique a ortografia.',
                      ),
                    ),
                  )
                else ...[
                  _SectionTitle(
                    title: 'Destaques',
                    count: '${highlights.length}',
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < 2; i++) ...[
                        if (i == 1) const SizedBox(width: 14),
                        Expanded(
                          child: i < highlights.length
                              ? FadeSlideIn(
                                  delay: Duration(milliseconds: 60 * i),
                                  child: _HighlightCard(
                                    post: highlights[i],
                                    onOpen: () => PostDetailScreen.open(
                                      context,
                                      highlights[i],
                                    ),
                                  ),
                                )
                              : const SizedBox(),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 28),
                  _SectionTitle(
                    title: 'Resultados',
                    count: '${results.length}',
                  ),
                  const SizedBox(height: 14),
                  for (var i = 0; i < results.length; i++) ...[
                    if (i < 6)
                      FadeSlideIn(
                        key: ValueKey('result-${results[i].id}'),
                        delay: Duration(milliseconds: 40 * i),
                        child: _ResultRow(
                          post: results[i],
                          onOpen: () =>
                              PostDetailScreen.open(context, results[i]),
                        ),
                      )
                    else
                      _ResultRow(
                        post: results[i],
                        onOpen: () =>
                            PostDetailScreen.open(context, results[i]),
                      ),
                    const SizedBox(height: 12),
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

// ──────────────────────────────────────────────────────────
// Topo com o campo de busca
// ──────────────────────────────────────────────────────────

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: UrbColors.hero,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 100,
            child: CitySkyline(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Buscar',
                  textAlign: TextAlign.center,
                  style: UrbText.display(
                    size: 26,
                    weight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Encontre reportes por título, rua, bairro ou categoria',
                  textAlign: TextAlign.center,
                  style: UrbText.body(
                    size: 14,
                    color: UrbColors.heroText,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x4D0D1520),
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    textInputAction: TextInputAction.search,
                    textAlign: TextAlign.center,
                    style: UrbText.body(
                      size: 15,
                      color: UrbColors.ink,
                      height: 1.3,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Pesquisar por reporte, rua ou bairro',
                      hintStyle: UrbText.body(
                        size: 15,
                        color: UrbColors.textMuted,
                        height: 1.3,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 18),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: UrbColors.textMuted,
                      ),
                      suffixIcon: AnimatedSwitcher(
                        duration: UrbMotion.of(context, UrbMotion.fast),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(scale: animation, child: child),
                        child: controller.text.isEmpty
                            ? const SizedBox(key: ValueKey('vazio'), width: 48)
                            : IconButton(
                                key: const ValueKey('limpar'),
                                tooltip: 'Limpar busca',
                                onPressed: onClear,
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: UrbColors.textMuted,
                                ),
                              ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(
                          color: Color(0xFF9A80D9),
                          width: 2,
                        ),
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

// ──────────────────────────────────────────────────────────
// Filtros por status
// ──────────────────────────────────────────────────────────

class _StatusFilters extends StatelessWidget {
  const _StatusFilters({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Filtrar por status',
          textAlign: TextAlign.center,
          style: UrbText.body(
            size: 13,
            weight: FontWeight.w700,
            color: const Color(0xFF374151),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final status in options)
              _FilterChip(
                label: UrbStatusChip.styleOf(status).label,
                selected: selected == status,
                onTap: () => onSelected(status),
              ),
          ],
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: UrbMotion.of(context, UrbMotion.fast),
          curve: Curves.easeOutCubic,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF18222E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF18222E) : UrbColors.border,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            style: UrbText.body(
              size: 13,
              weight: FontWeight.w700,
              color: selected ? Colors.white : const Color(0xFF374151),
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// Cartão do ranking
// ──────────────────────────────────────────────────────────

class _RankingPromoCard extends StatefulWidget {
  const _RankingPromoCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  State<_RankingPromoCard> createState() => _RankingPromoCardState();
}

class _RankingPromoCardState extends State<_RankingPromoCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onOpen,
      child: AnimatedScale(
        duration: UrbMotion.of(context, const Duration(milliseconds: 120)),
        scale: _pressed ? 0.97 : 1,
        child: Semantics(
          button: true,
          label: 'Ver ranking da sua cidade',
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF18222E),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x3818222E),
                  blurRadius: 30,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: UrbGradients.gamification,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ver ranking da sua cidade',
                        style: UrbText.display(
                          size: 17,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Compare participação, apoios e resoluções com os mais ativos.',
                        style: UrbText.body(
                          size: 13,
                          color: const Color(0xFFB9C4D4),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// Destaques e resultados
// ──────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final String count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: UrbText.display(size: 20, weight: FontWeight.w700),
          ),
        ),
        UrbCountBadge(label: count),
      ],
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.post, required this.onOpen});

  final FeedPost post;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: SizedBox(
          height: 150,
          child: Stack(
            fit: StackFit.expand,
            children: [
              UrbPostImage(url: post.primaryImageUrl, height: 150, radius: 22),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC0D1520)],
                    stops: [0.35, 1],
                  ),
                ),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: UrbStatusChip(status: post.status),
              ),
              if (post.imageCount > 1)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x990D1520),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.photo_library_outlined,
                          size: 13,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${post.imageCount}',
                          style: UrbText.body(
                            size: 12,
                            weight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Text(
                  post.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: UrbText.display(
                    size: 16,
                    weight: FontWeight.w700,
                    color: Colors.white,
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

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.post, required this.onOpen});

  final FeedPost post;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              UrbPostImage(
                url: post.primaryImageUrl,
                height: 68,
                width: 68,
                radius: 14,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.display(size: 16, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${post.isAnonymous ? 'Usuário anônimo' : post.authorLabel} · ${post.cityName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.body(
                        size: 12,
                        color: UrbColors.textMuted,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Flexible(child: UrbStatusChip(status: post.status)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            post.categoryName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: UrbText.body(
                              size: 12,
                              weight: FontWeight.w600,
                              color: UrbColors.textSecondary,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
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

class _ResultSkeleton extends StatelessWidget {
  const _ResultSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        children: [
          UrbSkeleton(width: 68, height: 68, radius: 14),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UrbSkeleton(height: 14),
                SizedBox(height: 8),
                UrbSkeleton(width: 120, height: 10),
                SizedBox(height: 8),
                UrbSkeleton(width: 80, height: 20, radius: 999),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// Filtro de cidade e atalhos por ocorrência
// ──────────────────────────────────────────────────────────

class _Occurrence {
  const _Occurrence(this.label, this.icon, this.keywords);

  final String label;
  final IconData icon;
  final List<String> keywords;
}

class _CityFilterButton extends StatelessWidget {
  const _CityFilterButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Cidade',
          textAlign: TextAlign.center,
          style: UrbText.body(
            size: 13,
            weight: FontWeight.w700,
            color: const Color(0xFF374151),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: UrbColors.border, width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: UrbColors.lavender,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.location_on_outlined,
                      color: UrbColors.violetDeep,
                      size: 19,
                    ),
                  ),
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
                          size: 15,
                          weight: FontWeight.w700,
                          color: UrbColors.ink,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(
                    width: 34,
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: UrbColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OccurrenceBar extends StatelessWidget {
  const _OccurrenceBar({
    required this.occurrences,
    required this.selected,
    required this.onSelected,
  });

  final List<_Occurrence> occurrences;
  final _Occurrence? selected;
  final ValueChanged<_Occurrence> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'O que aconteceu?',
          textAlign: TextAlign.center,
          style: UrbText.body(
            size: 13,
            weight: FontWeight.w700,
            color: const Color(0xFF374151),
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        // Barra que desliza para o lado com os tipos de ocorrência.
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: occurrences.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final occurrence = occurrences[index];
              final isSelected = identical(occurrence, selected);
              return Semantics(
                button: true,
                selected: isSelected,
                child: GestureDetector(
                  onTap: () => onSelected(occurrence),
                  child: AnimatedContainer(
                    duration: UrbMotion.of(context, UrbMotion.fast),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      gradient: isSelected ? UrbGradients.primary : null,
                      color: isSelected ? null : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? Colors.transparent
                            : UrbColors.border,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          occurrence.icon,
                          size: 18,
                          color: isSelected
                              ? Colors.white
                              : UrbColors.violetDeep,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          occurrence.label,
                          style: UrbText.body(
                            size: 14,
                            weight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF374151),
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
