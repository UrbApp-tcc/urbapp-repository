import 'package:flutter/material.dart';

import '../services/city_ranking_service.dart';
import '../theme/urbapp_design.dart';
import '../utils/error_formatter.dart';
import '../widgets/city_skyline.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/urb_dialog.dart';
import '../widgets/urb_post_image.dart';
import 'profile_screen.dart';

class CityRankingScreen extends StatefulWidget {
  const CityRankingScreen({super.key, required this.currentUserId});

  final String? currentUserId;

  static Future<void> open(
    BuildContext context, {
    required String? currentUserId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CityRankingScreen(currentUserId: currentUserId),
      ),
    );
  }

  @override
  State<CityRankingScreen> createState() => _CityRankingScreenState();
}

class _CityRankingScreenState extends State<CityRankingScreen> {
  final _rankingService = CityRankingService();

  List<CityRankingCityOption> _cities = const [];
  List<CityRankingEntry> _entries = const [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  int? _selectedCityId;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);

    try {
      final cities = await _rankingService.fetchCities();
      int? selectedCityId;

      if (widget.currentUserId != null) {
        selectedCityId = await _rankingService.fetchCurrentUserCityId(
          widget.currentUserId!,
        );
      }

      selectedCityId ??= cities.isNotEmpty ? cities.first.id : null;

      final entries = selectedCityId == null
          ? const <CityRankingEntry>[]
          : await _rankingService.fetchCityRanking(cityId: selectedCityId);

      if (!mounted) return;
      setState(() {
        _cities = cities;
        _selectedCityId = selectedCityId;
        _entries = entries;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(error);
    }
  }

  Future<void> _loadRankingForCity(
    int cityId, {
    bool refreshing = false,
  }) async {
    setState(() {
      if (refreshing) {
        _isRefreshing = true;
      } else {
        _isLoading = true;
      }
    });

    try {
      final entries = await _rankingService.fetchCityRanking(cityId: cityId);
      if (!mounted) return;
      setState(() {
        _selectedCityId = cityId;
        _entries = entries;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    showUrbSnack(context, friendlyError(error), error: true);
  }

  Future<void> _chooseCity() async {
    final cityId = await showUrbDialog<int>(
      context: context,
      builder: (_) =>
          _CityListDialog(cities: _cities, selectedId: _selectedCityId),
    );
    if (!mounted || cityId == null || cityId == _selectedCityId) return;
    await _loadRankingForCity(cityId);
  }

  void _openProfile(CityRankingEntry entry) {
    ProfileScreen.open(
      context,
      profileUserId: entry.profileId,
      currentUserId: widget.currentUserId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCity = _cities
        .where((c) => c.id == _selectedCityId)
        .firstOrNull;
    final currentUserId = widget.currentUserId;
    final currentUserEntry = currentUserId == null
        ? null
        : _entries.where((e) => e.profileId == currentUserId).firstOrNull;
    final podium = _entries.take(3).toList();

    return Scaffold(
      backgroundColor: UrbColors.surface,
      body: RefreshIndicator(
        onRefresh: () async {
          final cityId = _selectedCityId;
          if (cityId == null) return;
          await _loadRankingForCity(cityId, refreshing: true);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            _RankingHero(
              cityName: selectedCity?.name,
              isRefreshing: _isRefreshing,
              onBack: () => Navigator.of(context).maybePop(),
              onChooseCity: _cities.isEmpty ? null : _chooseCity,
              podium: _isLoading ? const [] : podium,
              onOpenProfile: _openProfile,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_isLoading && currentUserEntry != null) ...[
                    FadeSlideIn(
                      child: _YourPositionCard(entry: currentUserEntry),
                    ),
                    const SizedBox(height: 22),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Líderes da cidade',
                          style: UrbText.display(
                            size: 20,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!_isLoading && _entries.isNotEmpty)
                        UrbCountBadge(label: '${_entries.length}'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pontuação por reportes, apoios, comentários e resoluções',
                    style: UrbText.body(
                      size: 13,
                      color: UrbColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_isLoading)
                    for (var i = 0; i < 5; i++) ...[
                      const _EntrySkeleton(),
                      const SizedBox(height: 10),
                    ]
                  else if (_selectedCityId == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: UrbEmptyState(
                        icon: Icons.location_city_rounded,
                        title: 'Nenhuma cidade disponível',
                        text:
                            'Cadastre ou vincule cidades no banco para habilitar o ranking.',
                      ),
                    )
                  else if (_entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: UrbEmptyState(
                        icon: Icons.emoji_events_outlined,
                        title: 'Ainda não há participantes nessa cidade',
                        text:
                            'Assim que usuários vincularem o perfil e criarem reportes, o ranking começa a ganhar vida.',
                      ),
                    )
                  else
                    for (var i = 0; i < _entries.length; i++) ...[
                      if (i < 8)
                        FadeSlideIn(
                          key: ValueKey(
                            'rank-$_selectedCityId-${_entries[i].profileId}',
                          ),
                          delay: Duration(milliseconds: 45 * i),
                          child: _EntryCard(
                            entry: _entries[i],
                            isCurrentUser:
                                _entries[i].profileId == currentUserId,
                            onTap: () => _openProfile(_entries[i]),
                          ),
                        )
                      else
                        _EntryCard(
                          entry: _entries[i],
                          isCurrentUser: _entries[i].profileId == currentUserId,
                          onTap: () => _openProfile(_entries[i]),
                        ),
                      const SizedBox(height: 10),
                    ],
                  const SizedBox(height: 12),
                  const _RulesCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
// Topo roxo com o pódio
// ──────────────────────────────────────────────────────────

const _medalGradients = {
  1: [Color(0xFFF6D365), Color(0xFFD4A017)],
  2: [Color(0xFFE3E7EC), Color(0xFF9AA3AD)],
  3: [Color(0xFFF0C08F), Color(0xFFB7773F)],
};

class _RankingHero extends StatelessWidget {
  const _RankingHero({
    required this.cityName,
    required this.isRefreshing,
    required this.onBack,
    required this.onChooseCity,
    required this.podium,
    required this.onOpenProfile,
  });

  final String? cityName;
  final bool isRefreshing;
  final VoidCallback onBack;
  final VoidCallback? onChooseCity;
  final List<CityRankingEntry> podium;
  final ValueChanged<CityRankingEntry> onOpenProfile;

  @override
  Widget build(BuildContext context) {
    // Ordem do pódio: 2º, 1º, 3º.
    final order = <int>[1, 0, 2].where((i) => i < podium.length).toList();
    const heights = [110.0, 80.0, 60.0];

    return Container(
      decoration: const BoxDecoration(
        color: UrbColors.hero,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(34)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 140,
            child: CitySkyline(),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      _GlassSquare(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Voltar',
                        onPressed: onBack,
                      ),
                      Expanded(
                        child: Text(
                          'Ranking da cidade',
                          textAlign: TextAlign.center,
                          style: UrbText.display(
                            size: 20,
                            weight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: isRefreshing
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.emoji_events_outlined,
                                color: Colors.white,
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Material(
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: InkWell(
                      onTap: onChooseCity,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              cityName ?? 'Escolher cidade',
                              style: UrbText.body(
                                size: 15,
                                weight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.expand_more_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Quem mais movimenta a cidade agora',
                    textAlign: TextAlign.center,
                    style: UrbText.body(
                      size: 14,
                      color: UrbColors.heroText,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: podium.isEmpty ? 40 : 230,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final i in order)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: _PodiumColumn(
                              entry: podium[i],
                              height: heights[i],
                              delay: Duration(
                                milliseconds: i == 0 ? 0 : 120 * i,
                              ),
                              onTap: () => onOpenProfile(podium[i]),
                            ),
                          ),
                      ],
                    ),
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

/// Coluna do pódio: a coluna "cresce" de baixo para cima ao abrir.
class _PodiumColumn extends StatelessWidget {
  const _PodiumColumn({
    required this.entry,
    required this.height,
    required this.delay,
    required this.onTap,
  });

  final CityRankingEntry entry;
  final double height;
  final Duration delay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final medal = _medalGradients[entry.rankPosition] ?? _medalGradients[3]!;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 98,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FadeSlideIn(
              delay: delay,
              offsetY: 14,
              child: Column(
                children: [
                  Container(
                    width: entry.rankPosition == 1 ? 64 : 56,
                    height: entry.rankPosition == 1 ? 64 : 56,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: medal,
                      ),
                    ),
                    child: _Avatar(
                      url: entry.avatarUrl,
                      label: entry.fullName,
                      size: 58,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '@${entry.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: UrbText.body(
                      size: 12,
                      weight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                  Text(
                    '${entry.rankingScore} pts',
                    style: UrbText.body(
                      size: 11,
                      color: UrbColors.heroText,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: height),
              duration: UrbMotion.of(
                context,
                const Duration(milliseconds: 650),
              ),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Container(
                height: value,
                width: 98,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  border: Border(
                    top: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                    left: BorderSide(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    right: BorderSide(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.only(top: 8),
                child: child,
              ),
              child: Text(
                '${entry.rankPosition}',
                style: UrbText.display(
                  size: 26,
                  weight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassSquare extends StatelessWidget {
  const _GlassSquare({
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

// ──────────────────────────────────────────────────────────
// Sua posição, lista e regras
// ──────────────────────────────────────────────────────────

class _YourPositionCard extends StatelessWidget {
  const _YourPositionCard({required this.entry});

  final CityRankingEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF18222E),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x3818222E),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: UrbGradients.gamification,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  '#${entry.rankPosition}',
                  style: UrbText.display(
                    size: 20,
                    weight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sua posição',
                      style: UrbText.body(
                        size: 13,
                        color: const Color(0xFFB9C4D4),
                        height: 1.3,
                      ),
                    ),
                    // Os pontos "sobem" contando ao abrir.
                    TweenAnimationBuilder<double>(
                      tween: Tween(
                        begin: 0,
                        end: entry.rankingScore.toDouble(),
                      ),
                      duration: UrbMotion.of(
                        context,
                        const Duration(milliseconds: 800),
                      ),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, _) => Text(
                        '${value.round()} pontos',
                        style: UrbText.display(
                          size: 22,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _DarkStat(value: entry.postsCount, label: 'Reportes'),
              const SizedBox(width: 8),
              _DarkStat(value: entry.supportsReceived, label: 'Apoios'),
              const SizedBox(width: 8),
              _DarkStat(value: entry.resolvedPostsCount, label: 'Resolvidos'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DarkStat extends StatelessWidget {
  const _DarkStat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: UrbText.display(
                size: 18,
                weight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              style: UrbText.body(
                size: 12,
                color: const Color(0xFFB9C4D4),
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.isCurrentUser,
    required this.onTap,
  });

  final CityRankingEntry entry;
  final bool isCurrentUser;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final medal = _medalGradients[entry.rankPosition];

    return Material(
      color: isCurrentUser ? UrbColors.lavender : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: isCurrentUser
                ? Border.all(
                    color: UrbColors.violet.withValues(alpha: 0.4),
                    width: 1.5,
                  )
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: medal == null
                    ? null
                    : BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: medal,
                        ),
                      ),
                child: Text(
                  '${entry.rankPosition}',
                  style: UrbText.display(
                    size: 15,
                    weight: FontWeight.w800,
                    color: medal == null ? UrbColors.textMuted : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _Avatar(url: entry.avatarUrl, label: entry.fullName, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '@${entry.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: UrbText.body(
                              size: 15,
                              weight: FontWeight.w700,
                              color: UrbColors.ink,
                              height: 1.3,
                            ),
                          ),
                        ),
                        if (isCurrentUser) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: UrbColors.violet,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              'Você',
                              style: UrbText.body(
                                size: 11,
                                weight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${entry.postsCount} reportes · ${entry.supportsReceived} apoios · ${entry.resolvedPostsCount} resolvidos',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: UrbText.body(
                        size: 12,
                        color: UrbColors.textMuted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${entry.rankingScore}',
                    style: UrbText.display(
                      size: 17,
                      weight: FontWeight.w700,
                      color: UrbColors.violetDeep,
                    ),
                  ),
                  Text(
                    'pts',
                    style: UrbText.body(
                      size: 11,
                      color: UrbColors.textMuted,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.label, required this.size});

  final String? url;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final parts = label
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .take(2)
        .toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
        ? parts.first.substring(0, 1).toUpperCase()
        : '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    final fallback = Text(
      initials,
      style: UrbText.display(
        size: size * 0.36,
        weight: FontWeight.w700,
        color: UrbColors.violetDeep,
      ),
    );
    final imageUrl = url;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFEDE7FB), Color(0xFFDDF1FD)],
        ),
      ),
      child: imageUrl == null || imageUrl.isEmpty
          ? fallback
          : ClipOval(
              child: Image.network(
                imageUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
    );
  }
}

class _RulesCard extends StatelessWidget {
  const _RulesCard();

  @override
  Widget build(BuildContext context) {
    Widget rule(IconData icon, String text, String points) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: UrbColors.lavender,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 18, color: UrbColors.violetDeep),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: UrbText.body(size: 14, color: UrbColors.ink, height: 1.3),
            ),
          ),
          Text(
            points,
            style: UrbText.body(
              size: 14,
              weight: FontWeight.w700,
              color: UrbColors.violetDeep,
              height: 1.3,
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Como a pontuação funciona',
            textAlign: TextAlign.center,
            style: UrbText.display(size: 17, weight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          rule(Icons.add_location_alt_outlined, 'Cada reporte criado', '+50'),
          rule(Icons.favorite_border_rounded, 'Cada apoio recebido', '+15'),
          rule(
            Icons.chat_bubble_outline_rounded,
            'Cada comentário recebido',
            '+5',
          ),
          rule(
            Icons.task_alt_rounded,
            'Cada reporte concluído ou fechado',
            '+100',
          ),
        ],
      ),
    );
  }
}

class _EntrySkeleton extends StatelessWidget {
  const _EntrySkeleton();

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
          UrbSkeleton(width: 34, height: 34, radius: 17),
          SizedBox(width: 10),
          UrbSkeleton(width: 42, height: 42, radius: 21),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UrbSkeleton(height: 13),
                SizedBox(height: 8),
                UrbSkeleton(width: 140, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Janela flutuante com a lista de cidades do ranking.
class _CityListDialog extends StatefulWidget {
  const _CityListDialog({required this.cities, required this.selectedId});

  final List<CityRankingCityOption> cities;
  final int? selectedId;

  @override
  State<_CityListDialog> createState() => _CityListDialogState();
}

class _CityListDialogState extends State<_CityListDialog> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final filter = _filter.trim().toLowerCase();
    final cities = widget.cities
        .where((c) => filter.isEmpty || c.name.toLowerCase().contains(filter))
        .toList();

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
              icon: Icons.location_on_outlined,
              title: 'Cidade analisada',
              subtitle: 'Compare a liderança de participação de cada cidade.',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 14),
            TextField(
              onChanged: (value) => setState(() => _filter = value),
              textAlign: TextAlign.center,
              style: UrbText.body(size: 15, color: UrbColors.ink, height: 1.3),
              decoration: InputDecoration(
                hintText: 'Buscar cidade',
                hintStyle: UrbText.body(
                  size: 15,
                  color: UrbColors.textMuted,
                  height: 1.3,
                ),
                filled: true,
                fillColor: UrbColors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: UrbColors.textMuted,
                  size: 20,
                ),
                suffixIcon: const SizedBox(width: 48),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: UrbColors.border,
                    width: 1.5,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: UrbColors.border,
                    width: 1.5,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: UrbColors.violet,
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final city in cities)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(city.id),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: city.id == widget.selectedId
                                ? UrbColors.lavender
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: city.id == widget.selectedId
                                  ? UrbColors.violet.withValues(alpha: 0.45)
                                  : UrbColors.border,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_city_outlined,
                                size: 20,
                                color: city.id == widget.selectedId
                                    ? UrbColors.violetDeep
                                    : UrbColors.textMuted,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  city.name,
                                  style: UrbText.body(
                                    size: 15,
                                    weight: FontWeight.w700,
                                    color: city.id == widget.selectedId
                                        ? UrbColors.violetDeep
                                        : UrbColors.ink,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              if (city.id == widget.selectedId)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: UrbColors.violetDeep,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (cities.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Nada encontrado. Tente outro nome.',
                        textAlign: TextAlign.center,
                        style: UrbText.body(
                          size: 14,
                          color: UrbColors.textMuted,
                        ),
                      ),
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
