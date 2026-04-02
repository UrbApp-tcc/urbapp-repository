import 'package:flutter/material.dart';

import '../services/feed_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.posts,
    required this.isLoading,
  });

  final List<FeedPost> posts;
  final bool isLoading;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<FeedPost> get _results {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.posts;

    return widget.posts.where((post) {
      final haystack = [
        post.title,
        post.description,
        post.categoryName,
        post.cityName,
        post.authorDisplayName,
        post.agencyName ?? '',
      ].join(' ').toLowerCase();

      return haystack.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final highlights = results.take(2).toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 132),
      children: [
        _SearchField(
          controller: _controller,
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 34),
        _SearchSectionTitle(title: 'Destaques', trailing: '${highlights.length}'),
        const SizedBox(height: 18),
        if (widget.isLoading)
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 2,
              separatorBuilder: (context, index) => const SizedBox(width: 24),
              itemBuilder: (context, index) => const _HighlightSkeleton(),
            ),
          )
        else if (highlights.isEmpty)
          const _EmptySearchState()
        else
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: highlights.length,
              separatorBuilder: (context, index) => const SizedBox(width: 24),
              itemBuilder: (context, index) => _SearchHighlightCard(post: highlights[index]),
            ),
          ),
        const SizedBox(height: 28),
        _SearchSectionTitle(title: 'Resultados', trailing: '${results.length}'),
        const SizedBox(height: 18),
        if (widget.isLoading)
          ...List.generate(
            5,
            (index) => Padding(
              padding: EdgeInsets.only(bottom: index == 4 ? 0 : 24),
              child: const _ResultSkeleton(),
            ),
          )
        else if (results.isEmpty)
          const _EmptySearchState()
        else
          ...results.asMap().entries.map(
                (entry) => Padding(
                  padding: EdgeInsets.only(bottom: entry.key == results.length - 1 ? 0 : 24),
                  child: Text(
                    entry.value.title,
                    style: const TextStyle(
                      color: Color(0xFF141E28),
                      fontSize: 16,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.only(left: 18, right: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF141E28),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF141E28).withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Pesquisar reportes',
                hintStyle: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.search_rounded, color: Color(0xFF141E28)),
          ),
        ],
      ),
    );
  }
}

class _SearchSectionTitle extends StatelessWidget {
  const _SearchSectionTitle({
    required this.title,
    required this.trailing,
  });

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

class _SearchHighlightCard extends StatelessWidget {
  const _SearchHighlightCard({
    required this.post,
  });

  final FeedPost post;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 224,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (post.primaryImageUrl != null && post.primaryImageUrl!.isNotEmpty)
              Image.network(
                post.primaryImageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFF141E28),
                    ),
                  );
                },
              )
            else
              const DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFF141E28),
                ),
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
            const Positioned(
              top: 16,
              left: 16,
              child: Icon(
                Icons.play_circle_outline_rounded,
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

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Nenhum reporte encontrado para essa busca.',
      style: TextStyle(
        color: Color(0xFF8F949D),
        fontSize: 15,
        height: 1.45,
      ),
    );
  }
}
