// Scoring weights (must match get_city_ranking SQL function)
const int pointsPerPost = 50;
const int pointsPerSupportReceived = 15;
const int pointsPerCommentReceived = 5;
const int pointsPerResolvedPost = 100;

int calculateRankingScore({
  required int postsCount,
  required int supportsReceived,
  required int commentsReceived,
  required int resolvedPostsCount,
}) {
  return postsCount * pointsPerPost +
      supportsReceived * pointsPerSupportReceived +
      commentsReceived * pointsPerCommentReceived +
      resolvedPostsCount * pointsPerResolvedPost;
}

// Statuses that represent a closed lifecycle — no further interactions allowed.
const Set<String> finalStatuses = {'completed', 'closed', 'expired'};

bool isFinalStatus(String status) => finalStatuses.contains(status);

// Returns true when the acting user is the author of the post (self-support).
bool isSelfSupport(String currentUserId, String postAuthorId) =>
    currentUserId == postAuthorId;

/// Lightweight profile record used to sort/rank candidates client-side.
/// Mirrors the ORDER BY clause in the get_city_ranking SQL function.
class RankingCandidate {
  const RankingCandidate({
    required this.profileId,
    required this.rankingScore,
    required this.currentPoints,
    required this.currentXp,
    required this.createdAt,
  });

  final String profileId;
  final int rankingScore;
  final int currentPoints;
  final int currentXp;
  final DateTime createdAt;
}

/// Comparator that replicates the SQL dense_rank ordering:
///   1. ranking_score DESC
///   2. current_points DESC
///   3. current_xp DESC
///   4. created_at ASC  (older profile wins)
///   5. profile_id ASC  (alphabetical tiebreaker)
int rankingComparator(RankingCandidate a, RankingCandidate b) {
  if (a.rankingScore != b.rankingScore) {
    return b.rankingScore.compareTo(a.rankingScore);
  }
  if (a.currentPoints != b.currentPoints) {
    return b.currentPoints.compareTo(a.currentPoints);
  }
  if (a.currentXp != b.currentXp) {
    return b.currentXp.compareTo(a.currentXp);
  }
  final dateCmp = a.createdAt.compareTo(b.createdAt);
  if (dateCmp != 0) return dateCmp;
  return a.profileId.compareTo(b.profileId);
}

// ──────────────────────────────────────────────────────────
// Níveis de XP
// ──────────────────────────────────────────────────────────

/// Uma linha da tabela `levels` do banco.
class LevelThreshold {
  const LevelThreshold({
    required this.level,
    required this.minXp,
    required this.title,
  });

  final int level;
  final int minXp;
  final String title;
}

/// Progresso do usuário dentro do nível atual (usado na barra de XP).
class LevelProgress {
  const LevelProgress({
    required this.level,
    required this.title,
    required this.xpIntoLevel,
    required this.xpForLevel,
    this.nextLevelTitle,
  });

  final int level;
  final String title;

  /// XP ganho desde o início do nível atual.
  final int xpIntoLevel;

  /// XP total que o nível atual exige para passar ao próximo.
  /// 0 quando o usuário já está no nível máximo.
  final int xpForLevel;

  final String? nextLevelTitle;

  bool get isMaxLevel => xpForLevel == 0;

  int get xpToNextLevel => isMaxLevel ? 0 : xpForLevel - xpIntoLevel;

  double get fraction =>
      isMaxLevel ? 1.0 : (xpIntoLevel / xpForLevel).clamp(0.0, 1.0);
}

/// Calcula o progresso a partir do XP e da tabela de níveis.
/// Deve bater com a função SQL `level_for_xp`.
LevelProgress calculateLevelProgress(
  int currentXp,
  List<LevelThreshold> levels,
) {
  final xp = currentXp < 0 ? 0 : currentXp;

  if (levels.isEmpty) {
    return LevelProgress(level: 1, title: '', xpIntoLevel: xp, xpForLevel: 0);
  }

  final sorted = [...levels]..sort((a, b) => a.minXp.compareTo(b.minXp));

  var index = 0;
  for (var i = 0; i < sorted.length; i++) {
    if (sorted[i].minXp <= xp) index = i;
  }

  final current = sorted[index];
  final next = index + 1 < sorted.length ? sorted[index + 1] : null;

  return LevelProgress(
    level: current.level,
    title: current.title,
    xpIntoLevel: xp - current.minXp,
    xpForLevel: next == null ? 0 : next.minXp - current.minXp,
    nextLevelTitle: next?.title,
  );
}

/// Cópia dos níveis da migration `20260926120000_xp_and_levels.sql`.
/// Usada só se a tabela `levels` não puder ser lida.
const List<LevelThreshold> defaultLevels = [
  LevelThreshold(level: 1, minXp: 0, title: 'Observador'),
  LevelThreshold(level: 2, minXp: 100, title: 'Morador Atento'),
  LevelThreshold(level: 3, minXp: 300, title: 'Vizinho Ativo'),
  LevelThreshold(level: 4, minXp: 600, title: 'Fiscal do Bairro'),
  LevelThreshold(level: 5, minXp: 1000, title: 'Guardião da Cidade'),
];
