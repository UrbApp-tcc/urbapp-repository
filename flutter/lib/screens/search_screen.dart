import 'dart:async';

import 'package:flutter/material.dart';

import '../services/feed_service.dart';
import 'city_ranking_screen.dart';
import 'post_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.posts,
    required this.isLoading,
    required this.currentUserId,
  });

  final List<FeedPost> posts;
  final bool isLoading;
  final String? currentUserId;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _selectedStatus;

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
    return _normalizeSearchText([
      post.title,
      post.description,
      post.categoryName,
      post.cityName,
      post.street ?? '',
      post.neighborhood ?? '',
      post.authorDisplayName,
      post.agencyName ?? '',
    ].join(' '));
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

  bool get _hasActiveSearch => _query.trim().isNotEmpty;

  List<FeedPost> get _textResults {
    final raw = _normalizeSearchText(_query);
    if (raw.isEmpty) return widget.posts;

    final terms = raw.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (terms.isEmpty) return widget.posts;

    return widget.posts.where((post) {
      final haystack = _haystack(post);
      return terms.every((term) => haystack.contains(term));
    }).toList();
  }

  List<FeedPost> get _results {
    final textResults = _textResults;
    if (!_hasActiveSearch || _selectedStatus == null) return textResults;

    return textResults.where((post) => post.status == _selectedStatus).toList();
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
        return 'Concluído';
      case 'closed':
        return 'Encerrado';
      case 'expired':
        return 'Expirado';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final highlights = results.take(2).toList();
    final showEmpty = !widget.isLoading && results.isEmpty;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 132),
      children: [
        _SearchField(
          controller: _controller,
          onChanged: (value) {
            _debounce?.cancel();
            _debounce = Timer(
              const Duration(milliseconds: 300),
              () => setState(() {
                _query = value;
                if (value.trim().isEmpty) {
                  _selectedStatus = null;
                }
              }),
            );
          },
        ),
        if (_hasActiveSearch) ...[
          const SizedBox(height: 18),
          _StatusFilterBar(
            options: _statusOptions,
            selectedStatus: _selectedStatus,
            onSelected: (status) => setState(() {
              _selectedStatus = _selectedStatus == status ? null : status;
            }),
            statusLabelBuilder: _statusLabel,
          ),
        ],
        const SizedBox(height: 18),
        _CityRankingPromoCard(
          onOpen: () => CityRankingScreen.open(
            context,
            currentUserId: widget.currentUserId,
          ),
        ),
        const SizedBox(height: 34),
        if (widget.isLoading) ...[
          _SearchSectionTitle(title: 'Destaques', trailing: '—'),
          const SizedBox(height: 18),
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 2,
              separatorBuilder: (context, index) => const SizedBox(width: 24),
              itemBuilder: (context, index) => const _HighlightSkeleton(),
            ),
          ),
          const SizedBox(height: 28),
          _SearchSectionTitle(title: 'Resultados', trailing: '—'),
          const SizedBox(height: 18),
          ...List.generate(
            5,
            (index) => Padding(
              padding: EdgeInsets.only(bottom: index == 4 ? 0 : 24),
              child: const _ResultSkeleton(),
            ),
          ),
        ] else if (showEmpty)
          _SearchEmptyState(feedIsEmpty: widget.posts.isEmpty)
        else ...[
          _SearchSectionTitle(
            title: 'Destaques',
            trailing: '${highlights.length}',
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: highlights.length,
              separatorBuilder: (context, index) => const SizedBox(width: 24),
              itemBuilder: (context, index) => _SearchHighlightCard(
                post: highlights[index],
                onOpen: () => PostDetailScreen.open(context, highlights[index]),
              ),
            ),
          ),
          const SizedBox(height: 28),
          _SearchSectionTitle(
            title: 'Resultados',
            trailing: '${results.length}',
          ),
          const SizedBox(height: 18),
          ...results.asMap().entries.map(
            (entry) => Padding(
              padding: EdgeInsets.only(
                bottom: entry.key == results.length - 1 ? 0 : 24,
              ),
              child: _SearchResultRow(
                post: entry.value,
                onOpen: () => PostDetailScreen.open(context, entry.value),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CityRankingPromoCard extends StatelessWidget {
  const _CityRankingPromoCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF15202B), Color(0xFF26384C), Color(0xFF516E93)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF15202B).withValues(alpha: 0.14),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Em alta',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Ver ranking da sua cidade',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Compare participação, apoios e resoluções com os usuários mais ativos da comunidade.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE2E5EA)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF141E28).withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Icon(
              Icons.search_rounded,
              color: Color(0xFF8F949D),
              size: 22,
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                color: Color(0xFF141E28),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                hintText: 'Pesquisar por reporte, rua ou bairro',
                hintStyle: TextStyle(
                  color: Color(0xFF8F949D),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchSectionTitle extends StatelessWidget {
  const _SearchSectionTitle({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF141E28),
              fontSize: 26,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.5,
            ),
          ),
        ),
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFB9BEC6), width: 1.4),
          ),
          alignment: Alignment.center,
          child: Text(
            trailing,
            style: const TextStyle(
              color: Color(0xFF8F949D),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({
    required this.options,
    required this.selectedStatus,
    required this.onSelected,
    required this.statusLabelBuilder,
  });

  final List<String> options;
  final String? selectedStatus;
  final ValueChanged<String> onSelected;
  final String Function(String status) statusLabelBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Filtrar por status',
          style: TextStyle(
            color: Color(0xFF8F949D),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: options
                .map(
                  (status) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _StatusChip(
                      label: statusLabelBuilder(status),
                      isSelected: selectedStatus == status,
                      onTap: () => onSelected(status),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF141E28) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF141E28)
                  : const Color(0xFFE2E5EA),
            ),
            boxShadow: isSelected
                ? null
                : [
                    BoxShadow(
                      color: const Color(0xFF141E28).withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFF4B5563),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchHighlightCard extends StatelessWidget {
  const _SearchHighlightCard({required this.post, required this.onOpen});

  final FeedPost post;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onOpen,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 224,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (post.primaryImageUrl != null &&
                    post.primaryImageUrl!.isNotEmpty)
                  Image.network(
                    post.primaryImageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const DecoratedBox(
                        decoration: BoxDecoration(color: Color(0xFF141E28)),
                      );
                    },
                  )
                else
                  const DecoratedBox(
                    decoration: BoxDecoration(color: Color(0xFF141E28)),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.12),
                        Colors.black.withValues(alpha: 0.48),
                      ],
                    ),
                  ),
                ),
                if (post.imageCount > 1)
                  const Positioned(
                    top: 16,
                    left: 16,
                    child: Icon(
                      Icons.photo_library_outlined,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Text(
                    post.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({required this.post, required this.onOpen});

  final FeedPost post;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.title,
                  style: const TextStyle(
                    color: Color(0xFF141E28),
                    fontSize: 16,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${post.authorLabel} · ${post.cityName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8F949D),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HighlightSkeleton extends StatelessWidget {
  const _HighlightSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 224,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F6),
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

class _ResultSkeleton extends StatelessWidget {
  const _ResultSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F3F6),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.feedIsEmpty});

  final bool feedIsEmpty;

  @override
  Widget build(BuildContext context) {
    final title = feedIsEmpty
        ? 'Nenhum reporte ainda'
        : 'Nenhum resultado para essa busca';
    final subtitle = feedIsEmpty
        ? 'Quando houver reportes na lista principal, você poderá pesquisar por título, cidade, categoria e mais. Toque no + para criar o primeiro.'
        : 'Tente outras palavras ou verifique a ortografia.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF141E28),
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFF8F949D),
            fontSize: 15,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}
