import 'package:flutter/material.dart';

import '../services/city_ranking_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_formatter.dart';
import 'profile_screen.dart';

class CityRankingScreen extends StatefulWidget {
  const CityRankingScreen({
    super.key,
    required this.currentUserId,
  });

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
        selectedCityId = await _rankingService.fetchCurrentUserCityId(widget.currentUserId!);
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

  Future<void> _loadRankingForCity(int cityId, {bool refreshing = false}) async {
    if (refreshing) {
      setState(() => _isRefreshing = true);
    } else {
      setState(() => _isLoading = true);
    }

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(friendlyError(error)),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    CityRankingCityOption? selectedCity;
    for (final city in _cities) {
      if (city.id == _selectedCityId) {
        selectedCity = city;
        break;
      }
    }

    CityRankingEntry? currentUserEntry;
    final currentUserId = widget.currentUserId;
    if (currentUserId != null) {
      for (final entry in _entries) {
        if (entry.profileId == currentUserId) {
          currentUserEntry = entry;
          break;
        }
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F8),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: _RankingTopBar(
                isRefreshing: _isRefreshing,
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  final cityId = _selectedCityId;
                  if (cityId == null) return;
                  await _loadRankingForCity(cityId, refreshing: true);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                  children: [
                    _RankingHero(
                      selectedCityName: selectedCity?.name,
                      currentUserEntry: currentUserEntry,
                    ),
                    const SizedBox(height: 20),
                    _CityPickerCard(
                      cities: _cities,
                      selectedCityId: _selectedCityId,
                      onChanged: (value) {
                        if (value == null || value == _selectedCityId) return;
                        _loadRankingForCity(value);
                      },
                    ),
                    const SizedBox(height: 20),
                    const _RankingRulesCard(),
                    const SizedBox(height: 24),
                    const _SectionHeader(
                      title: 'Líderes da cidade',
                      subtitle: 'Pontuação por reportes, apoios, comentários e resoluções',
                    ),
                    const SizedBox(height: 16),
                    if (_isLoading)
                      ...List.generate(
                        6,
                        (index) => Padding(
                          padding: EdgeInsets.only(bottom: index == 5 ? 0 : 12),
                          child: const _RankingEntrySkeleton(),
                        ),
                      )
                    else if (_selectedCityId == null)
                      const _RankingEmptyState(
                        title: 'Nenhuma cidade disponível',
                        subtitle: 'Cadastre ou vincule cidades no banco para habilitar o ranking.',
                      )
                    else if (_entries.isEmpty)
                      const _RankingEmptyState(
                        title: 'Ainda não há participantes nessa cidade',
                        subtitle: 'Assim que usuários vincularem o perfil e criarem reportes, o ranking começa a ganhar vida.',
                      )
                    else
                      ..._entries.asMap().entries.map(
                            (entry) => Padding(
                              padding: EdgeInsets.only(bottom: entry.key == _entries.length - 1 ? 0 : 12),
                              child: _RankingEntryCard(
                                entry: entry.value,
                                isCurrentUser: entry.value.profileId == widget.currentUserId,
                                currentUserId: widget.currentUserId,
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankingTopBar extends StatelessWidget {
  const _RankingTopBar({
    required this.isRefreshing,
    required this.onBack,
  });

  final bool isRefreshing;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const Spacer(),
        const Text(
          'Ranking da cidade',
          style: TextStyle(
            color: Color(0xFF141E28),
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        SizedBox(
          width: 40,
          height: 40,
          child: isRefreshing
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : const Icon(
                  Icons.emoji_events_outlined,
                  color: Color(0xFF141E28),
                ),
        ),
      ],
    );
  }
}

class _RankingHero extends StatelessWidget {
  const _RankingHero({
    required this.selectedCityName,
    required this.currentUserEntry,
  });

  final String? selectedCityName;
  final CityRankingEntry? currentUserEntry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1A2330),
            Color(0xFF2E3F57),
            Color(0xFF5778A3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A2330).withValues(alpha: 0.18),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              selectedCityName == null ? 'Sem cidade selecionada' : 'Em alta em $selectedCityName',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Quem mais movimenta a cidade agora',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            currentUserEntry == null
                ? 'A pontuação combina criação de reportes, engajamento recebido e problemas finalizados.'
                : 'Você está em #${currentUserEntry!.rankPosition} com ${currentUserEntry!.rankingScore} pontos de ranking.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (currentUserEntry != null) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                _HeroMetric(
                  label: 'Reportes',
                  value: '${currentUserEntry!.postsCount}',
                ),
                const SizedBox(width: 12),
                _HeroMetric(
                  label: 'Apoios',
                  value: '${currentUserEntry!.supportsReceived}',
                ),
                const SizedBox(width: 12),
                _HeroMetric(
                  label: 'Resolvidos',
                  value: '${currentUserEntry!.resolvedPostsCount}',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CityPickerCard extends StatelessWidget {
  const _CityPickerCard({
    required this.cities,
    required this.selectedCityId,
    required this.onChanged,
  });

  final List<CityRankingCityOption> cities;
  final int? selectedCityId;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3E8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cidade analisada',
            style: TextStyle(
              color: Color(0xFF141E28),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Troque a cidade para comparar a liderança local de participação cívica.',
            style: TextStyle(
              color: Color(0xFF8F949D),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            initialValue: selectedCityId,
            items: cities
                .map(
                  (city) => DropdownMenuItem<int>(
                    value: city.id,
                    child: Text(city.name),
                  ),
                )
                .toList(),
            onChanged: onChanged,
            decoration: const InputDecoration(
              labelText: 'Selecionar cidade',
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingRulesCard extends StatelessWidget {
  const _RankingRulesCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAF2),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF4DEC0)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Como a pontuação funciona',
            style: TextStyle(
              color: Color(0xFF8A4B00),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Cada reporte vale 50 pontos. Cada apoio recebido vale 15. Cada comentário recebido vale 5. Cada reporte concluído ou fechado vale 100.',
            style: TextStyle(
              color: Color(0xFF9A6A2F),
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF141E28),
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFF8F949D),
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _RankingEntryCard extends StatelessWidget {
  const _RankingEntryCard({
    required this.entry,
    required this.isCurrentUser,
    required this.currentUserId,
  });

  final CityRankingEntry entry;
  final bool isCurrentUser;
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final rankTone = switch (entry.rankPosition) {
      1 => const Color(0xFFF5C451),
      2 => const Color(0xFFC4CCD8),
      3 => const Color(0xFFD59661),
      _ => const Color(0xFF141E28),
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ProfileScreen.open(
          context,
          profileUserId: entry.profileId,
          currentUserId: currentUserId,
        ),
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          decoration: BoxDecoration(
            color: isCurrentUser ? const Color(0xFFF5F8FF) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isCurrentUser ? const Color(0xFFBFD2F8) : const Color(0xFFE5EAF0),
              width: isCurrentUser ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RankBadge(
                      rankPosition: entry.rankPosition,
                      color: rankTone,
                    ),
                    const SizedBox(width: 14),
                    _RankingAvatar(
                      avatarUrl: entry.avatarUrl,
                      label: entry.fullName,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.fullName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF141E28),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (isCurrentUser)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCE8FF),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Text(
                                    'Você',
                                    style: TextStyle(
                                      color: Color(0xFF315DA8),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '@${entry.username} · Nível ${entry.currentLevel}',
                            style: const TextStyle(
                              color: Color(0xFF8F949D),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${entry.rankingScore} pontos de ranking',
                            style: const TextStyle(
                              color: Color(0xFF141E28),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _MiniStat(
                      label: 'Reportes',
                      value: '${entry.postsCount}',
                    ),
                    const SizedBox(width: 8),
                    _MiniStat(
                      label: 'Apoios',
                      value: '${entry.supportsReceived}',
                    ),
                    const SizedBox(width: 8),
                    _MiniStat(
                      label: 'Comentários',
                      value: '${entry.commentsReceived}',
                    ),
                    const SizedBox(width: 8),
                    _MiniStat(
                      label: 'Resolvidos',
                      value: '${entry.resolvedPostsCount}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({
    required this.rankPosition,
    required this.color,
  });

  final int rankPosition;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Text(
        '#$rankPosition',
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RankingAvatar extends StatelessWidget {
  const _RankingAvatar({
    required this.avatarUrl,
    required this.label,
  });

  final String? avatarUrl;
  final String label;

  @override
  Widget build(BuildContext context) {
    final initials = label
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join()
        .toUpperCase();

    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundColor: const Color(0xFFE8ECF3),
        child: ClipOval(
          child: Image.network(
            avatarUrl!,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _fallback(initials),
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 24,
      backgroundColor: const Color(0xFFE8ECF3),
      child: _fallback(initials),
    );
  }

  Widget _fallback(String initials) {
    return Text(
      initials.isEmpty ? 'U' : initials,
      style: const TextStyle(
        color: Color(0xFF4B6078),
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF141E28),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF8F949D),
                fontSize: 9,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankingEntrySkeleton extends StatelessWidget {
  const _RankingEntrySkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 142,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
    );
  }
}

class _RankingEmptyState extends StatelessWidget {
  const _RankingEmptyState({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE5EAF0)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.location_city_outlined,
            size: 38,
            color: Color(0xFF8F949D),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF141E28),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF8F949D),
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
