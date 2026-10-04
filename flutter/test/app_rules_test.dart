import 'package:flutter_test/flutter_test.dart';

import 'package:meu_app/logic/app_rules.dart';

void main() {
  // ──────────────────────────────────────────────────────────
  // Pontuação / XP
  // ──────────────────────────────────────────────────────────
  group('calculateRankingScore', () {
    test('50 pontos por reporte criado', () {
      expect(
        calculateRankingScore(
          postsCount: 1,
          supportsReceived: 0,
          commentsReceived: 0,
          resolvedPostsCount: 0,
        ),
        50,
      );
    });

    test('15 pontos por apoio recebido', () {
      expect(
        calculateRankingScore(
          postsCount: 0,
          supportsReceived: 1,
          commentsReceived: 0,
          resolvedPostsCount: 0,
        ),
        15,
      );
    });

    test('5 pontos por comentário recebido', () {
      expect(
        calculateRankingScore(
          postsCount: 0,
          supportsReceived: 0,
          commentsReceived: 1,
          resolvedPostsCount: 0,
        ),
        5,
      );
    });

    test('100 pontos por reporte resolvido', () {
      expect(
        calculateRankingScore(
          postsCount: 0,
          supportsReceived: 0,
          commentsReceived: 0,
          resolvedPostsCount: 1,
        ),
        100,
      );
    });

    test('acumula todas as categorias corretamente', () {
      // 2 posts (100) + 4 apoios (60) + 3 comentários (15) + 1 resolvido (100) = 275
      expect(
        calculateRankingScore(
          postsCount: 2,
          supportsReceived: 4,
          commentsReceived: 3,
          resolvedPostsCount: 1,
        ),
        275,
      );
    });

    test('retorna 0 para usuário sem nenhuma atividade', () {
      expect(
        calculateRankingScore(
          postsCount: 0,
          supportsReceived: 0,
          commentsReceived: 0,
          resolvedPostsCount: 0,
        ),
        0,
      );
    });

    test('reporte resolvido vale o dobro de um reporte apenas criado', () {
      final resolved = calculateRankingScore(
        postsCount: 0,
        supportsReceived: 0,
        commentsReceived: 0,
        resolvedPostsCount: 1,
      );
      final onePost = calculateRankingScore(
        postsCount: 1,
        supportsReceived: 0,
        commentsReceived: 0,
        resolvedPostsCount: 0,
      );
      expect(resolved, greaterThan(onePost));
    });
  });

  // ──────────────────────────────────────────────────────────
  // Ranking / desempate
  // ──────────────────────────────────────────────────────────
  group('rankingComparator', () {
    final baseDate = DateTime(2024, 1, 1);

    RankingCandidate candidate({
      String profileId = 'x',
      int rankingScore = 0,
      int currentPoints = 0,
      int currentXp = 0,
      DateTime? createdAt,
    }) => RankingCandidate(
      profileId: profileId,
      rankingScore: rankingScore,
      currentPoints: currentPoints,
      currentXp: currentXp,
      createdAt: createdAt ?? baseDate,
    );

    test('quem tem maior ranking_score vem primeiro', () {
      final a = candidate(profileId: 'a', rankingScore: 300);
      final b = candidate(profileId: 'b', rankingScore: 100);
      final sorted = [b, a]..sort(rankingComparator);
      expect(sorted.first.profileId, 'a');
    });

    test('empate em score: desempata por current_points (maior primeiro)', () {
      final a = candidate(profileId: 'a', rankingScore: 100, currentPoints: 80);
      final b = candidate(profileId: 'b', rankingScore: 100, currentPoints: 40);
      final sorted = [b, a]..sort(rankingComparator);
      expect(sorted.first.profileId, 'a');
    });

    test(
      'empate em score e points: desempata por current_xp (maior primeiro)',
      () {
        final a = candidate(
          profileId: 'a',
          rankingScore: 100,
          currentPoints: 50,
          currentXp: 500,
        );
        final b = candidate(
          profileId: 'b',
          rankingScore: 100,
          currentPoints: 50,
          currentXp: 200,
        );
        final sorted = [b, a]..sort(rankingComparator);
        expect(sorted.first.profileId, 'a');
      },
    );

    test(
      'empate em score, points e xp: perfil mais antigo vem primeiro (created_at asc)',
      () {
        final a = candidate(
          profileId: 'a',
          rankingScore: 100,
          currentPoints: 50,
          currentXp: 200,
          createdAt: DateTime(2022, 3, 15),
        );
        final b = candidate(
          profileId: 'b',
          rankingScore: 100,
          currentPoints: 50,
          currentXp: 200,
          createdAt: DateTime(2024, 6, 1),
        );
        final sorted = [b, a]..sort(rankingComparator);
        expect(sorted.first.profileId, 'a');
      },
    );

    test('empate total: desempata por profile_id em ordem alfabética', () {
      final a = candidate(
        profileId: 'aaa-uuid',
        rankingScore: 100,
        currentPoints: 50,
        currentXp: 200,
      );
      final b = candidate(
        profileId: 'zzz-uuid',
        rankingScore: 100,
        currentPoints: 50,
        currentXp: 200,
      );
      final sorted = [b, a]..sort(rankingComparator);
      expect(sorted.first.profileId, 'aaa-uuid');
    });

    test('lista com vários candidatos fica na ordem correta', () {
      final candidates = [
        candidate(profileId: 'c', rankingScore: 50),
        candidate(profileId: 'a', rankingScore: 300),
        candidate(profileId: 'b', rankingScore: 150),
      ]..sort(rankingComparator);

      expect(candidates.map((e) => e.profileId).toList(), ['a', 'b', 'c']);
    });
  });

  // ──────────────────────────────────────────────────────────
  // Regras de negócio
  // ──────────────────────────────────────────────────────────
  group('isFinalStatus', () {
    test('completed é status final', () {
      expect(isFinalStatus('completed'), isTrue);
    });

    test('closed é status final', () {
      expect(isFinalStatus('closed'), isTrue);
    });

    test('expired é status final', () {
      expect(isFinalStatus('expired'), isTrue);
    });

    test('open não é status final', () {
      expect(isFinalStatus('open'), isFalse);
    });

    test('in_progress não é status final', () {
      expect(isFinalStatus('in_progress'), isFalse);
    });

    test('string vazia não é status final', () {
      expect(isFinalStatus(''), isFalse);
    });
  });

  group('canStartResolutionValidation', () {
    test('permite estados operacionais e reaberto', () {
      for (final status in ['open', 'in_analysis', 'in_progress', 'reopened']) {
        expect(canStartResolutionValidation(status), isTrue, reason: status);
      }
    });

    test('bloqueia validacao pendente e estados finais', () {
      for (final status in [
        'awaiting_validation',
        'completed',
        'closed',
        'expired',
      ]) {
        expect(canStartResolutionValidation(status), isFalse, reason: status);
      }
    });
  });

  group('isSelfSupport', () {
    test('usuário não pode apoiar o próprio post', () {
      expect(isSelfSupport('user-abc', 'user-abc'), isTrue);
    });

    test('usuários diferentes podem apoiar normalmente', () {
      expect(isSelfSupport('user-abc', 'user-xyz'), isFalse);
    });

    test('IDs distintos com prefixo comum não são considerados o mesmo', () {
      expect(isSelfSupport('user-1', 'user-10'), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────
  // Níveis de XP
  // ──────────────────────────────────────────────────────────
  group('calculateLevelProgress', () {
    test('0 XP fica no nível 1, sem progresso', () {
      final p = calculateLevelProgress(0, defaultLevels);
      expect(p.level, 1);
      expect(p.xpIntoLevel, 0);
      expect(p.xpForLevel, 100);
      expect(p.xpToNextLevel, 100);
      expect(p.nextLevelTitle, 'Morador Atento');
    });

    test('XP no meio do nível calcula o progresso relativo', () {
      final p = calculateLevelProgress(150, defaultLevels);
      expect(p.level, 2);
      expect(p.xpIntoLevel, 50);
      expect(p.xpForLevel, 200);
      expect(p.fraction, closeTo(0.25, 0.0001));
    });

    test('XP exatamente no limite já conta como o nível seguinte', () {
      expect(calculateLevelProgress(300, defaultLevels).level, 3);
      expect(calculateLevelProgress(299, defaultLevels).level, 2);
    });

    test('nível máximo não tem próximo nível', () {
      final p = calculateLevelProgress(5000, defaultLevels);
      expect(p.level, 5);
      expect(p.isMaxLevel, isTrue);
      expect(p.xpToNextLevel, 0);
      expect(p.fraction, 1.0);
      expect(p.nextLevelTitle, isNull);
    });

    test('XP negativo é tratado como zero', () {
      expect(calculateLevelProgress(-10, defaultLevels).level, 1);
    });

    test('a ordem da lista de níveis não importa', () {
      final shuffled = defaultLevels.reversed.toList();
      expect(calculateLevelProgress(650, shuffled).level, 4);
    });
  });
}
