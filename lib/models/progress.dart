/// Tracks cross-app progress that isn't part of any single project: XP,
/// creation streaks, today's daily-goal counters, and whether the user has
/// ever successfully exported (used by the "First Export" achievement,
/// since exporting doesn't otherwise change any project data).
class Progress {
  int totalXp;
  int currentStreak;
  int longestStreak;
  DateTime? lastActiveDate;
  bool everExported;

  DateTime? dailyTrackedDate;
  bool hasDrawnToday;
  int framesAddedToday;
  int shotsCompletedToday;
  int shotsExportedToday;

  Progress({
    this.totalXp = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastActiveDate,
    this.everExported = false,
    this.dailyTrackedDate,
    this.hasDrawnToday = false,
    this.framesAddedToday = 0,
    this.shotsCompletedToday = 0,
    this.shotsExportedToday = 0,
  });

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Call whenever something creative happens. Handles XP, streak upkeep
  /// (including rolling over to a new day) and today's daily-goal counters
  /// all in one place.
  void recordActivity({
    int xp = 0,
    bool drewFrame = false,
    bool addedFrame = false,
    bool completedShot = false,
    bool exportedShot = false,
  }) {
    final today = _dateOnly(DateTime.now());

    if (dailyTrackedDate == null || dailyTrackedDate != today) {
      dailyTrackedDate = today;
      hasDrawnToday = false;
      framesAddedToday = 0;
      shotsCompletedToday = 0;
      shotsExportedToday = 0;
    }

    if (lastActiveDate == null || _dateOnly(lastActiveDate!) != today) {
      final yesterday = today.subtract(const Duration(days: 1));
      if (lastActiveDate != null && _dateOnly(lastActiveDate!) == yesterday) {
        currentStreak += 1;
      } else {
        currentStreak = 1;
      }
      if (currentStreak > longestStreak) longestStreak = currentStreak;
      lastActiveDate = today;
    }

    totalXp += xp;
    if (drewFrame) hasDrawnToday = true;
    if (addedFrame) framesAddedToday += 1;
    if (completedShot) shotsCompletedToday += 1;
    if (exportedShot) {
      shotsExportedToday += 1;
      everExported = true;
    }
  }

  Map<String, dynamic> toJson() => {
        'totalXp': totalXp,
        'currentStreak': currentStreak,
        'longestStreak': longestStreak,
        'lastActiveDate': lastActiveDate?.toIso8601String(),
        'everExported': everExported,
        'dailyTrackedDate': dailyTrackedDate?.toIso8601String(),
        'hasDrawnToday': hasDrawnToday,
        'framesAddedToday': framesAddedToday,
        'shotsCompletedToday': shotsCompletedToday,
        'shotsExportedToday': shotsExportedToday,
      };

  static Progress fromJson(Map<String, dynamic> json) => Progress(
        totalXp: json['totalXp'] as int? ?? 0,
        currentStreak: json['currentStreak'] as int? ?? 0,
        longestStreak: json['longestStreak'] as int? ?? 0,
        lastActiveDate: json['lastActiveDate'] != null ? DateTime.tryParse(json['lastActiveDate'] as String) : null,
        everExported: json['everExported'] as bool? ?? false,
        dailyTrackedDate:
            json['dailyTrackedDate'] != null ? DateTime.tryParse(json['dailyTrackedDate'] as String) : null,
        hasDrawnToday: json['hasDrawnToday'] as bool? ?? false,
        framesAddedToday: json['framesAddedToday'] as int? ?? 0,
        shotsCompletedToday: json['shotsCompletedToday'] as int? ?? 0,
        shotsExportedToday: json['shotsExportedToday'] as int? ?? 0,
      );
}
