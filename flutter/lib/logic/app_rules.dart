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
