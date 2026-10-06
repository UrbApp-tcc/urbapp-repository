import 'package:flutter/material.dart';

import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/urb/urb_components.dart';
import '../../widgets/urb/urb_icon.dart';

/// Conquistas: insígnias por nível (conquistadas, em progresso, bloqueadas).
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key, required this.badges, required this.profile});

  final List<ProfileBadge> badges;
  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final level = profile.levelProgress.level;
    final earned = badges.where((badge) => badge.earned).toList();
    final next = badges.where((badge) => !badge.earned && (badge.minLevel ?? 0) == level + 1).toList();
    final locked = badges.where((badge) => !badge.earned && !next.contains(badge)).toList();
    return Scaffold(
      backgroundColor: UrbColors.canvas,
      appBar: const UrbSubscreenHeader(title: 'Conquistas'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          if (earned.isNotEmpty) ...[
            const UrbGroupLabel('Conquistadas'),
            for (final badge in earned) _row(badge, _BadgeState.earned),
          ],
          if (next.isNotEmpty) ...[
            const UrbGroupLabel('Em progresso'),
            for (final badge in next) _row(badge, _BadgeState.progress),
          ],
          if (locked.isNotEmpty) ...[
            const UrbGroupLabel('Bloqueadas'),
            for (final badge in locked) _row(badge, _BadgeState.locked),
          ],
          if (badges.isEmpty)
            const UrbEmptyState(icon: UrbIcons.check, title: 'Sem conquistas cadastradas', message: 'As insígnias aparecerão aqui.'),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Pontos e XP vêm de contribuições úteis: relatos válidos, apoios e comentários recebidos, validações e ocorrências resolvidas. '
              'Conteúdos invalidados pela moderação podem ter a pontuação revertida.',
              style: UrbText.caption,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(ProfileBadge badge, _BadgeState state) {
    final progress = profile.levelProgress;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: UrbColors.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: switch (state) {
                _BadgeState.earned => UrbColors.blue,
                _BadgeState.progress => const Color(0xFFD8E8F8),
                _BadgeState.locked => UrbColors.line,
              },
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: switch (state) {
              _BadgeState.earned => const UrbIcon(UrbIcons.check, size: 15, color: Colors.white, strokeWidth: 2.5),
              _BadgeState.progress => Text('${badge.minLevel ?? ''}', style: UrbText.label.copyWith(color: const Color(0xFF3A6EA0), fontWeight: FontWeight.w800)),
              _BadgeState.locked => const UrbIcon(UrbIcons.lock, size: 14, color: Color(0xFF9AAAB8)),
            },
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge.name,
                  style: UrbText.titleSmall.copyWith(color: state == _BadgeState.locked ? const Color(0xFF9AAAB8) : UrbColors.navy),
                ),
                const SizedBox(height: 2),
                Text(
                  badge.description.isEmpty ? 'Alcance o nível ${badge.minLevel ?? ''}.' : badge.description,
                  style: UrbText.caption.copyWith(color: state == _BadgeState.locked ? const Color(0xFFB5C0CC) : UrbColors.muted),
                ),
                if (state == _BadgeState.progress && !progress.isMaxLevel) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 130,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(value: progress.fraction, minHeight: 3, color: UrbColors.blue),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('${progress.xpIntoLevel} / ${progress.xpForLevel} XP', style: UrbText.caption.copyWith(color: UrbColors.blue, fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _BadgeState { earned, progress, locked }
