import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../services/study_timer_service.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/delete_confirmation_dialog.dart';

enum ReportPeriod { today, week, month, all }

class StudyTimerReportPage extends StatefulWidget {
  const StudyTimerReportPage({super.key});

  @override
  State<StudyTimerReportPage> createState() => _StudyTimerReportPageState();
}

class _StudyTimerReportPageState extends State<StudyTimerReportPage>
    with WidgetsBindingObserver {
  StudyTimerSnapshot? _snapshot;
  bool _loading = true;
  Timer? _tickerTimer;
  Timer? _syncTimer;

  ReportPeriod _selectedPeriod = ReportPeriod.week;
  int? _selectedChartDayIndex;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  static const List<String> _motivationalTips = [
    'The 50/10 Rule: 50 minutes of deep focus followed by a 10-minute active break maximizes memory retention.',
    'Active Recall beats passive re-reading every time. Test yourself right after studying!',
    'Small steps daily beat all-nighters. Keep your study streak alive today!',
    'Stay hydrated! Even a 2% drop in hydration can reduce focus and cognitive stamina.',
    'Spaced Repetition: Review topics after 1 day, 3 days, and 1 week for long-term retention.',
  ];
  int _currentTipIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadReport();

    // 1-second live ticker for running stopwatch
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_snapshot?.isRunning == true && mounted) {
        setState(() {});
      }
    });

    // 15-second background sync to align with Android home widget if toggled outside
    _syncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _loadReport(silent: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadReport(silent: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickerTimer?.cancel();
    _syncTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadReport({bool silent = false}) async {
    if (!silent) {
      setState(() => _loading = true);
    }
    final snapshot = await StudyTimerService.loadSnapshot();
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _loading = false;
    });
  }

  Future<void> _startTimer() async {
    HapticFeedback.mediumImpact();
    await StudyTimerService.startTimer(
      subject: _snapshot?.activeSubject,
    );
    await _loadReport(silent: true);
  }

  Future<void> _pauseTimer() async {
    HapticFeedback.lightImpact();
    await StudyTimerService.pauseTimer();
    await _loadReport(silent: true);
  }

  Future<void> _stopTimer() async {
    HapticFeedback.heavyImpact();
    await StudyTimerService.pauseTimer();
    await _loadReport(silent: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text('Session saved to study history!'),
          ],
        ),
        backgroundColor: const Color(0xFF4338CA),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _confirmResetTimer() async {
    final confirmed = await showDeleteConfirmationDialog(
      context: context,
      title: 'Reset Today\'s Timer',
      message: 'This will reset today\'s active stopwatch to zero. Past history will remain safe.',
    );
    if (confirmed == true) {
      await StudyTimerService.resetTodayTimer();
      await _loadReport(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Today\'s stopwatch reset to 0.')),
      );
    }
  }

  Future<void> _selectSubject() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SubjectPickerSheet(
        currentSubject: _snapshot?.activeSubject ?? StudyTimerService.defaultSubject,
      ),
    );
    if (chosen != null && chosen.isNotEmpty) {
      await StudyTimerService.setActiveSubject(chosen);
      await _loadReport(silent: true);
    }
  }

  Future<void> _openGoalSheet() async {
    final newGoal = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _GoalPickerSheet(
        currentGoalMinutes:
            _snapshot?.dailyGoalMinutes ?? StudyTimerService.defaultDailyGoalMinutes,
      ),
    );
    if (newGoal != null && newGoal > 0) {
      await StudyTimerService.setDailyGoalMinutes(newGoal);
      await _loadReport(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Daily target updated to ${StudyTimerService.formatDuration(Duration(minutes: newGoal))}.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openManualEntryDialog() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _ManualSessionDialog(),
    );
    if (added == true) {
      await _loadReport(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline study session recorded successfully!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteSession(StudyTimerRecord record) async {
    final confirmed = await showDeleteConfirmationDialog(
      context: context,
      title: 'Delete Session',
      message: 'Delete this study session from history?',
      paperTitle: record.subject ?? 'Study Session',
      paperSubtitle: '${DateFormat.yMMMd().format(record.startedAt)} • ${StudyTimerService.formatDuration(record.duration)}',
    );
    if (confirmed == true) {
      await StudyTimerService.deleteSession(record.id);
      await _loadReport(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Study session deleted.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDeleteConfirmationDialog(
      context: context,
      title: 'Clear All History',
      message: 'Are you sure you want to delete all study history and reset records? This cannot be undone.',
    );
    if (confirmed == true) {
      await StudyTimerService.clearAllHistory();
      await _loadReport(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All study history cleared.')),
      );
    }
  }

  void _shareReportSummary() {
    if (_snapshot == null) return;
    final now = DateTime.now();
    final todayDuration = _snapshot!.computeCurrentDuration(now);
    final streak = StudyTimerService.calculateCurrentStreak(_snapshot!.history, now);
    final weekStart = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final weekDuration = StudyTimerService.totalInRange(_snapshot!.history, weekStart, now);
    final goalPercent = ((todayDuration.inSeconds / (_snapshot!.dailyGoalMinutes * 60)) * 100).toInt();

    final text = StringBuffer()
      ..writeln('📊 *My Study Report on Pi-QBank*')
      ..writeln('━━━━━━━━━━━━━━━━━━━━━━━')
      ..writeln('🔥 Current Streak: $streak Day${streak == 1 ? '' : 's'}')
      ..writeln('🎯 Today: ${StudyTimerService.formatDuration(todayDuration)} ($goalPercent% of daily goal)')
      ..writeln('📈 Last 7 Days: ${StudyTimerService.formatDuration(weekDuration)}')
      ..writeln('📚 Total Sessions: ${_snapshot!.history.length}')
      ..writeln('━━━━━━━━━━━━━━━━━━━━━━━')
      ..writeln('“Success is the sum of small efforts repeated day in and day out.” 🚀');

    Share.share(text.toString(), subject: 'My Study Report');
  }

  void _showHelpInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Color(0xFF4F46E5)),
            SizedBox(width: 8),
            Text('About Study Timer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '• Home Screen Widget:\nYou can add the Pi-QBank Study Timer widget to your Android home screen to start and pause study sessions with a single tap!',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 10),
            Text(
              '• Study Streak:\nStudy consistently every day to grow your streak flame 🔥. Missing a day resets the active streak.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            SizedBox(height: 10),
            Text(
              '• Offline Sessions:\nStudied from textbooks or at coaching? Tap "+ Log Offline" to add study sessions manually.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF0F1117) : const Color(0xFFF6F8FD);

    if (_loading && _snapshot == null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: const CustomAppBar(title: 'Study Time Report'),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final snapshot = _snapshot!;
    final now = DateTime.now();
    final todayDuration = snapshot.computeCurrentDuration(now);
    final history = snapshot.history;

    // Filter calculations according to selected tab
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(const Duration(days: 6));
    final monthStart = todayStart.subtract(const Duration(days: 29));

    late final Duration periodDuration;
    late final List<StudyTimerRecord> periodRecords;
    int chartDays = 7;
    DateTime chartStartDate = weekStart;

    switch (_selectedPeriod) {
      case ReportPeriod.today:
        periodDuration = todayDuration;
        periodRecords = history
            .where((r) => r.startedAt.isAfter(todayStart.subtract(const Duration(seconds: 1))))
            .toList();
        chartDays = 1;
        chartStartDate = todayStart;
        break;
      case ReportPeriod.week:
        periodDuration = StudyTimerService.totalInRange(history, weekStart, now);
        periodRecords = history
            .where((r) => r.startedAt.isAfter(weekStart.subtract(const Duration(seconds: 1))))
            .toList();
        chartDays = 7;
        chartStartDate = weekStart;
        break;
      case ReportPeriod.month:
        periodDuration = StudyTimerService.totalInRange(history, monthStart, now);
        periodRecords = history
            .where((r) => r.startedAt.isAfter(monthStart.subtract(const Duration(seconds: 1))))
            .toList();
        chartDays = 30;
        chartStartDate = monthStart;
        break;
      case ReportPeriod.all:
        periodDuration = StudyTimerService.totalDuration(history);
        periodRecords = history;
        chartDays = 7;
        chartStartDate = weekStart;
        break;
    }

    final currentStreak = StudyTimerService.calculateCurrentStreak(history, now);
    final longestStreak = StudyTimerService.calculateLongestStreak(history);
    final timeOfDay = StudyTimerService.getTimeOfDayBreakdown(periodRecords);
    final dailyTotals = StudyTimerService.getDailyTotals(history, chartStartDate, chartDays);

    // Filter history list by search query
    final filteredHistory = history.where((r) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final subjectMatch = (r.subject ?? '').toLowerCase().contains(q);
      final noteMatch = (r.note ?? '').toLowerCase().contains(q);
      return subjectMatch || noteMatch;
    }).toList();

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: CustomAppBar(
        title: 'Study Time Report',
        actions: [
          IconButton(
            tooltip: 'Share Report',
            icon: const Icon(Icons.share_outlined),
            onPressed: _shareReportSummary,
          ),
          IconButton(
            tooltip: 'About Timer & Widget',
            icon: const Icon(Icons.info_outline),
            onPressed: _showHelpInfo,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (val) {
              if (val == 'log') _openManualEntryDialog();
              if (val == 'goal') _openGoalSheet();
              if (val == 'reset') _confirmResetTimer();
              if (val == 'clear') _confirmClearAll();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'log',
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline, color: Color(0xFF4F46E5), size: 20),
                    SizedBox(width: 10),
                    Text('Log Offline Study'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'goal',
                child: Row(
                  children: [
                    Icon(Icons.track_changes_rounded, color: Colors.teal, size: 20),
                    SizedBox(width: 10),
                    Text('Adjust Daily Goal'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    Icon(Icons.restart_alt_rounded, color: Colors.orange, size: 20),
                    SizedBox(width: 10),
                    Text('Reset Today\'s Timer'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    SizedBox(width: 10),
                    Text('Clear All History', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadReport,
        color: const Color(0xFF4F46E5),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          children: [
            // 1. Interactive Live Stopwatch Hero Card
            _LiveStopwatchHero(
              isRunning: snapshot.isRunning,
              todayDuration: todayDuration,
              activeSubject: snapshot.activeSubject,
              dailyGoalMinutes: snapshot.dailyGoalMinutes,
              onStart: _startTimer,
              onPause: _pauseTimer,
              onStop: _stopTimer,
              onReset: _confirmResetTimer,
              onSelectSubject: _selectSubject,
            ),
            const SizedBox(height: 14),

            // 2. Daily Goal Progress Card
            _DailyGoalCard(
              todayDuration: todayDuration,
              dailyGoalMinutes: snapshot.dailyGoalMinutes,
              onAdjustGoal: _openGoalSheet,
            ),
            const SizedBox(height: 18),

            // 3. Motivational Study Tips Carousel Card
            _MotivationalTipsCard(
              tip: _motivationalTips[_currentTipIndex],
              onNextTip: () {
                setState(() {
                  _currentTipIndex = (_currentTipIndex + 1) % _motivationalTips.length;
                });
              },
            ),
            const SizedBox(height: 20),

            // 4. Period Filter Selector
            _PeriodFilterBar(
              selectedPeriod: _selectedPeriod,
              onSelectPeriod: (p) {
                setState(() {
                  _selectedPeriod = p;
                  _selectedChartDayIndex = null;
                });
              },
            ),
            const SizedBox(height: 14),

            // 5. Key Metrics 2x2 Bento Grid
            _MetricsGrid(
              period: _selectedPeriod,
              totalDuration: periodDuration,
              sessionCount: periodRecords.length,
              currentStreak: currentStreak,
              longestStreak: longestStreak,
              isDark: isDark,
            ),
            const SizedBox(height: 18),

            // 6. Interactive Visual Bar Chart
            if (_selectedPeriod == ReportPeriod.week || _selectedPeriod == ReportPeriod.month) ...[
              _InteractiveStudyChartCard(
                dailyTotals: dailyTotals,
                dailyGoalMinutes: snapshot.dailyGoalMinutes,
                isDark: isDark,
                selectedIndex: _selectedChartDayIndex,
                onSelectDay: (idx) {
                  setState(() => _selectedChartDayIndex = idx);
                },
              ),
              const SizedBox(height: 18),
            ],

            // 7. Productivity Rhythm (Time of Day Breakdown)
            _ProductivityRhythmCard(
              breakdown: timeOfDay,
              total: periodDuration,
              isDark: isDark,
            ),
            const SizedBox(height: 22),

            // 8. Session History Section Header & Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.history_rounded, size: 22, color: Color(0xFF4F46E5)),
                    const SizedBox(width: 8),
                    const Text(
                      'Study History',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${history.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: _openManualEntryDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Log Offline', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF4F46E5),
                    backgroundColor: const Color(0xFF4F46E5).withOpacity(0.08),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Search filter if sessions > 3
            if (history.length > 3) ...[
              TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search sessions by subject or note...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1B1E2B) : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 9. History List or Empty state
            if (filteredHistory.isEmpty)
              _EmptyHistoryCard(
                hasHistoryAtAll: history.isNotEmpty,
                isDark: isDark,
                onStartSession: _startTimer,
                onLogManual: _openManualEntryDialog,
              )
            else
              ...filteredHistory.map(
                (rec) => _SessionHistoryCard(
                  record: rec,
                  isDark: isDark,
                  onDelete: () => _deleteSession(rec),
                ),
              ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 1. Live Stopwatch Hero Card
// ==========================================
class _LiveStopwatchHero extends StatefulWidget {
  const _LiveStopwatchHero({
    required this.isRunning,
    required this.todayDuration,
    required this.activeSubject,
    required this.dailyGoalMinutes,
    required this.onStart,
    required this.onPause,
    required this.onStop,
    required this.onReset,
    required this.onSelectSubject,
  });

  final bool isRunning;
  final Duration todayDuration;
  final String activeSubject;
  final int dailyGoalMinutes;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final VoidCallback onReset;
  final VoidCallback onSelectSubject;

  @override
  State<_LiveStopwatchHero> createState() => _LiveStopwatchHeroState();
}

class _LiveStopwatchHeroState extends State<_LiveStopwatchHero>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF3730A3), // Indigo 800
            Color(0xFF4F46E5), // Indigo 600
            Color(0xFF7C3AED), // Violet 600
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top row: Status Badge & Subject selector chip
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Pulse status pill
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: widget.isRunning
                          ? const Color(0xFF10B981).withOpacity(0.25)
                          : Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: widget.isRunning
                            ? Colors.greenAccent.withOpacity(0.4 + _pulseController.value * 0.4)
                            : Colors.white.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.isRunning ? Colors.greenAccent : Colors.white60,
                            boxShadow: widget.isRunning
                                ? [
                                    BoxShadow(
                                      color: Colors.greenAccent.withOpacity(0.8),
                                      blurRadius: 6 * _pulseController.value,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.isRunning ? 'STUDYING NOW' : 'READY TO FOCUS',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Subject Chip
              InkWell(
                onTap: widget.onSelectSubject,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bookmark_outline, size: 14, color: Colors.white),
                      const SizedBox(width: 5),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: Text(
                          widget.activeSubject,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Digital Stopwatch Clock
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                StudyTimerService.formatStopwatch(widget.todayDuration),
                style: const TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 2,
                  fontFeatures: [FontFeature.tabularFigures()],
                  shadows: [
                    Shadow(
                      color: Colors.black26,
                      offset: Offset(0, 3),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Text(
              widget.isRunning ? 'Today\'s Total Focus Time' : 'Today\'s Focus Time',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Main Controls
          Row(
            children: [
              if (!widget.isRunning) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: widget.onStart,
                    icon: const Icon(Icons.play_arrow_rounded, size: 24),
                    label: const Text(
                      'Start Studying',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: const Color(0xFF3730A3),
                      backgroundColor: Colors.white,
                      elevation: 4,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                if (widget.todayDuration.inSeconds > 0) ...[
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: widget.onReset,
                    tooltip: 'Reset Today',
                    icon: const Icon(Icons.restart_alt_rounded, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.18),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ] else ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: widget.onPause,
                    icon: const Icon(Icons.pause_rounded, size: 22),
                    label: const Text(
                      'Pause',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: const Color(0xFF3730A3),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onStop,
                    icon: const Icon(Icons.stop_rounded, size: 22, color: Colors.white),
                    label: const Text(
                      'Finish & Save',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 2. Daily Goal Progress Card
// ==========================================
class _DailyGoalCard extends StatelessWidget {
  const _DailyGoalCard({
    required this.todayDuration,
    required this.dailyGoalMinutes,
    required this.onAdjustGoal,
  });

  final Duration todayDuration;
  final int dailyGoalMinutes;
  final VoidCallback onAdjustGoal;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final targetSeconds = dailyGoalMinutes * 60;
    final progress = (todayDuration.inSeconds / (targetSeconds == 0 ? 1 : targetSeconds))
        .clamp(0.0, 1.0);
    final percent = (progress * 100).toInt();
    final remainingMinutes = (dailyGoalMinutes - todayDuration.inMinutes).clamp(0, dailyGoalMinutes);
    final achieved = todayDuration.inMinutes >= dailyGoalMinutes;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D29) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Circular Progress Indicator
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6.5,
                  backgroundColor: isDark
                      ? Colors.white12
                      : const Color(0xFFEEF2FF),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    achieved ? const Color(0xFF10B981) : const Color(0xFF6366F1),
                  ),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Text(
                achieved ? '100%' : '$percent%',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: achieved
                      ? const Color(0xFF10B981)
                      : (isDark ? Colors.white : const Color(0xFF1E293B)),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),

          // Goal Info & Status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Daily Study Target',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    InkWell(
                      onTap: onAdjustGoal,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text(
                          'Adjust',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF4F46E5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${StudyTimerService.formatDuration(todayDuration)} of ${StudyTimerService.formatDuration(Duration(minutes: dailyGoalMinutes))}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  achieved
                      ? '🎉 Target reached! Outstanding dedication!'
                      : (remainingMinutes > 0
                          ? '$remainingMinutes minutes left to reach your goal'
                          : 'Almost there! Keep going'),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: achieved
                        ? const Color(0xFF10B981)
                        : (isDark ? Colors.white54 : const Color(0xFF64748B)),
                    fontWeight: achieved ? FontWeight.w600 : FontWeight.normal,
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

// ==========================================
// 3. Motivational Tips Carousel Card
// ==========================================
class _MotivationalTipsCard extends StatelessWidget {
  const _MotivationalTipsCard({
    required this.tip,
    required this.onNextTip,
  });

  final String tip;
  final VoidCallback onNextTip;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1C2F) : const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF8B5CF6).withOpacity(0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.lightbulb_outline_rounded, size: 20, color: Color(0xFF7C3AED)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PRO TIP',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF7C3AED),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tip,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onNextTip,
            tooltip: 'Next Tip',
            icon: const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFF7C3AED)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 4. Period Filter Selector Bar
// ==========================================
class _PeriodFilterBar extends StatelessWidget {
  const _PeriodFilterBar({
    required this.selectedPeriod,
    required this.onSelectPeriod,
  });

  final ReportPeriod selectedPeriod;
  final ValueChanged<ReportPeriod> onSelectPeriod;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2130) : const Color(0xFFEAEEF7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _filterPill('Today', ReportPeriod.today, isDark),
          _filterPill('7 Days', ReportPeriod.week, isDark),
          _filterPill('30 Days', ReportPeriod.month, isDark),
          _filterPill('All Time', ReportPeriod.all, isDark),
        ],
      ),
    );
  }

  Widget _filterPill(String title, ReportPeriod period, bool isDark) {
    final selected = selectedPeriod == period;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelectPeriod(period),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? const Color(0xFF4F46E5) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected && !isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              color: selected
                  ? (isDark ? Colors.white : const Color(0xFF4F46E5))
                  : (isDark ? Colors.white60 : const Color(0xFF64748B)),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 5. Key Metrics 2x2 Bento Grid
// ==========================================
class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({
    required this.period,
    required this.totalDuration,
    required this.sessionCount,
    required this.currentStreak,
    required this.longestStreak,
    required this.isDark,
  });

  final ReportPeriod period;
  final Duration totalDuration;
  final int sessionCount;
  final int currentStreak;
  final int longestStreak;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final avgDuration = sessionCount > 0
        ? Duration(microseconds: totalDuration.inMicroseconds ~/ sessionCount)
        : Duration.zero;

    String periodLabel = 'This Week';
    if (period == ReportPeriod.today) periodLabel = 'Today';
    if (period == ReportPeriod.month) periodLabel = 'This Month';
    if (period == ReportPeriod.all) periodLabel = 'All Time';

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.45,
      children: [
        // 1. Total Focus Time
        _metricTile(
          icon: Icons.timer_outlined,
          iconColor: const Color(0xFF4F46E5),
          bgColor: const Color(0xFFEEF2FF),
          title: 'Total Focus',
          value: StudyTimerService.formatDuration(totalDuration),
          subtitle: periodLabel,
        ),

        // 2. Study Streak
        _metricTile(
          icon: Icons.local_fire_department_rounded,
          iconColor: const Color(0xFFF97316),
          bgColor: const Color(0xFFFFF7ED),
          title: 'Study Streak',
          value: '$currentStreak Day${currentStreak == 1 ? '' : 's'}',
          subtitle: 'Best: $longestStreak Days',
        ),

        // 3. Sessions Count
        _metricTile(
          icon: Icons.menu_book_rounded,
          iconColor: const Color(0xFF0284C7),
          bgColor: const Color(0xFFF0F9FF),
          title: 'Sessions',
          value: '$sessionCount',
          subtitle: 'Logged',
        ),

        // 4. Average Session
        _metricTile(
          icon: Icons.bolt_rounded,
          iconColor: const Color(0xFFEAB308),
          bgColor: const Color(0xFFFEFCE8),
          title: 'Avg Session',
          value: StudyTimerService.formatDuration(avgDuration),
          subtitle: 'Per study interval',
        ),
      ],
    );
  }

  Widget _metricTile({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D29) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white60 : const Color(0xFF64748B),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark ? iconColor.withOpacity(0.15) : bgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 6. Interactive Visual Bar Chart
// ==========================================
class _InteractiveStudyChartCard extends StatelessWidget {
  const _InteractiveStudyChartCard({
    required this.dailyTotals,
    required this.dailyGoalMinutes,
    required this.isDark,
    required this.selectedIndex,
    required this.onSelectDay,
  });

  final List<DailyStudyTotal> dailyTotals;
  final int dailyGoalMinutes;
  final bool isDark;
  final int? selectedIndex;
  final ValueChanged<int> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final maxDailySeconds = dailyTotals.fold<int>(
      dailyGoalMinutes * 60,
      (maxVal, item) => item.total.inSeconds > maxVal ? item.total.inSeconds : maxVal,
    );
    final targetHeightRatio = (dailyGoalMinutes * 60) / (maxDailySeconds == 0 ? 1 : maxDailySeconds);

    final selectedTotal =
        (selectedIndex != null && selectedIndex! < dailyTotals.length)
            ? dailyTotals[selectedIndex!]
            : null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D29) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily Study Trend',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Tap bars for details',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              // Target Line Legend
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.amber.shade700,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Goal (${StudyTimerService.formatDuration(Duration(minutes: dailyGoalMinutes))})',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Chart Display Area
          SizedBox(
            height: 140,
            child: Stack(
              children: [
                // Goal reference line
                if (targetHeightRatio > 0.05 && targetHeightRatio <= 0.95)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: (targetHeightRatio * 105) + 24,
                    child: Container(
                      height: 1.5,
                      color: Colors.amber.shade400.withOpacity(0.55),
                    ),
                  ),

                // Bars Row
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: dailyTotals.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final item = entry.value;
                      final isSelected = selectedIndex == idx;
                      final isToday = DateUtils.isSameDay(item.date, DateTime.now());
                      final ratio = maxDailySeconds == 0
                          ? 0.0
                          : (item.total.inSeconds / maxDailySeconds).clamp(0.02, 1.0);

                      final isGoalMet = item.total.inMinutes >= dailyGoalMinutes;

                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onSelectDay(idx),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Goal met indicator star or dot
                              if (isGoalMet)
                                const Icon(
                                  Icons.star_rounded,
                                  size: 10,
                                  color: Color(0xFFF59E0B),
                                )
                              else
                                const SizedBox(height: 10),

                              const SizedBox(height: 2),

                              // The Bar
                              Expanded(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    width: dailyTotals.length > 10 ? 6 : 22,
                                    height: 105 * ratio,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: isSelected
                                            ? [
                                                const Color(0xFF4338CA),
                                                const Color(0xFF818CF8),
                                              ]
                                            : (isToday
                                                ? [
                                                    const Color(0xFF4F46E5),
                                                    const Color(0xFF6366F1),
                                                  ]
                                                : [
                                                    isDark
                                                        ? const Color(0xFF2E334D)
                                                        : const Color(0xFFCBD5E1),
                                                    isDark
                                                        ? const Color(0xFF3F4668)
                                                        : const Color(0xFF94A3B8),
                                                  ]),
                                      ),
                                      border: isSelected
                                          ? Border.all(color: Colors.white, width: 1.5)
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Day label
                              Text(
                                dailyTotals.length > 7
                                    ? (idx % 5 == 0 ? '${item.date.day}' : '')
                                    : DateFormat.E().format(item.date).substring(0, 3),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: isToday || isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? const Color(0xFF4F46E5)
                                      : (isToday
                                          ? const Color(0xFF4F46E5)
                                          : (isDark ? Colors.white54 : Colors.black45)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),

          // Detail tooltip card when tapped
          if (selectedTotal != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF222638) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF4F46E5)),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat.yMMMd().format(selectedTotal.date),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  Text(
                    '${StudyTimerService.formatDuration(selectedTotal.total)} (${selectedTotal.sessionCount} sessions)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ==========================================
// 7. Productivity Rhythm Card (Time of Day)
// ==========================================
class _ProductivityRhythmCard extends StatelessWidget {
  const _ProductivityRhythmCard({
    required this.breakdown,
    required this.total,
    required this.isDark,
  });

  final Map<String, Duration> breakdown;
  final Duration total;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final totalSec = total.inSeconds == 0 ? 1 : total.inSeconds;

    // Find peak time
    String peakPeriod = 'Morning';
    int peakSec = 0;
    breakdown.forEach((key, dur) {
      if (dur.inSeconds > peakSec) {
        peakSec = dur.inSeconds;
        peakPeriod = key;
      }
    });

    final peakIcon = switch (peakPeriod) {
      'Morning' => '🌅',
      'Afternoon' => '☀️',
      'Evening' => '🌆',
      _ => '🌙',
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D29) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Productivity Rhythm',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (peakSec > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$peakIcon Most active in $peakPeriod',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4F46E5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          _phaseRow('Morning (06 AM – 12 PM)', Icons.wb_sunny_outlined, Colors.amber, breakdown['Morning'] ?? Duration.zero, totalSec),
          const SizedBox(height: 10),
          _phaseRow('Afternoon (12 PM – 05 PM)', Icons.light_mode_outlined, Colors.orange, breakdown['Afternoon'] ?? Duration.zero, totalSec),
          const SizedBox(height: 10),
          _phaseRow('Evening (05 PM – 09 PM)', Icons.nights_stay_outlined, Colors.indigo, breakdown['Evening'] ?? Duration.zero, totalSec),
          const SizedBox(height: 10),
          _phaseRow('Night (09 PM – 06 AM)', Icons.bedtime_outlined, Colors.deepPurple, breakdown['Night'] ?? Duration.zero, totalSec),
        ],
      ),
    );
  }

  Widget _phaseRow(String title, IconData icon, Color color, Duration dur, int totalSec) {
    final ratio = (dur.inSeconds / totalSec).clamp(0.0, 1.0);
    final pct = (ratio * 100).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : const Color(0xFF475569),
                ),
              ),
            ),
            Text(
              '${StudyTimerService.formatDuration(dur)} ($pct%)',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: isDark ? Colors.white10 : const Color(0xFFEEF2FF),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// 8. Session History Card
// ==========================================
class _SessionHistoryCard extends StatelessWidget {
  const _SessionHistoryCard({
    required this.record,
    required this.isDark,
    required this.onDelete,
  });

  final StudyTimerRecord record;
  final bool isDark;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final subject = record.subject ?? StudyTimerService.defaultSubject;
    final subjectColor = _getSubjectColor(subject);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D29) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.15 : 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Leading subject circle
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: subjectColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _getSubjectIcon(subject),
              color: subjectColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),

          // Session Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        subject,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        StudyTimerService.formatDuration(record.duration, showSeconds: true),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4F46E5),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${DateFormat.yMMMd().format(record.startedAt)} • ${DateFormat.jm().format(record.startedAt)} - ${DateFormat.jm().format(record.endedAt)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  ),
                ),
                if (record.note != null && record.note!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '“${record.note}”',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Delete Action Button
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: isDark ? Colors.white38 : Colors.black38,
            onPressed: onDelete,
            tooltip: 'Delete Session',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Color _getSubjectColor(String subj) {
    final s = subj.toLowerCase();
    if (s.contains('math')) return const Color(0xFF4F46E5);
    if (s.contains('physic')) return const Color(0xFF0284C7);
    if (s.contains('chem')) return const Color(0xFF0D9488);
    if (s.contains('bio')) return const Color(0xFF16A34A);
    if (s.contains('eng')) return const Color(0xFFE11D48);
    if (s.contains('bangla')) return const Color(0xFFD97706);
    if (s.contains('ict')) return const Color(0xFF7C3AED);
    return const Color(0xFF6366F1);
  }

  IconData _getSubjectIcon(String subj) {
    final s = subj.toLowerCase();
    if (s.contains('math')) return Icons.calculate_outlined;
    if (s.contains('physic')) return Icons.electric_bolt_outlined;
    if (s.contains('chem')) return Icons.science_outlined;
    if (s.contains('bio')) return Icons.eco_outlined;
    if (s.contains('eng') || s.contains('bangla')) return Icons.menu_book_outlined;
    if (s.contains('ict')) return Icons.computer_outlined;
    return Icons.timer_outlined;
  }
}

// ==========================================
// 9. Empty History Placeholder
// ==========================================
class _EmptyHistoryCard extends StatelessWidget {
  const _EmptyHistoryCard({
    required this.hasHistoryAtAll,
    required this.isDark,
    required this.onStartSession,
    required this.onLogManual,
  });

  final bool hasHistoryAtAll;
  final bool isDark;
  final VoidCallback onStartSession;
  final VoidCallback onLogManual;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D29) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.hourglass_empty_rounded,
              size: 38,
              color: Color(0xFF4F46E5),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            hasHistoryAtAll
                ? 'No matching study sessions found'
                : 'No study sessions recorded yet',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasHistoryAtAll
                ? 'Try a different search term or clear the filter.'
                : 'Start the live timer above or log past offline study to build your study report.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.white54 : const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: onStartSession,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Start Timer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onLogManual,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Log Offline'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4F46E5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 10. Manual Study Session Entry Dialog
// ==========================================
class _ManualSessionDialog extends StatefulWidget {
  const _ManualSessionDialog();

  @override
  State<_ManualSessionDialog> createState() => _ManualSessionDialogState();
}

class _ManualSessionDialogState extends State<_ManualSessionDialog> {
  DateTime _date = DateTime.now();
  TimeOfDay _startTime = TimeOfDay.fromDateTime(DateTime.now().subtract(const Duration(hours: 1)));
  TimeOfDay _endTime = TimeOfDay.fromDateTime(DateTime.now());
  String _subject = StudyTimerService.defaultSubject;
  final TextEditingController _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null) setState(() => _endTime = picked);
  }

  Future<void> _save() async {
    final start = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _startTime.hour,
      _startTime.minute,
    );
    final end = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _endTime.hour,
      _endTime.minute,
    );

    if (!end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be after start time.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await StudyTimerService.addManualSession(
      startedAt: start,
      endedAt: end,
      subject: _subject,
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
    );

    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.edit_calendar_rounded, color: Color(0xFF4F46E5)),
          SizedBox(width: 8),
          Text('Log Offline Study', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date Picker tile
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today, size: 20),
              title: const Text('Date', style: TextStyle(fontSize: 13, color: Colors.grey)),
              subtitle: Text(
                DateFormat.yMMMd().format(_date),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: _pickDate,
            ),
            const Divider(),

            // Times Row
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Start Time', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    subtitle: Text(
                      _startTime.format(context),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    onTap: _pickStartTime,
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('End Time', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    subtitle: Text(
                      _endTime.format(context),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    onTap: _pickEndTime,
                  ),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 6),

            // Subject Selector
            const Text('Subject', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              value: _subject,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: StudyTimerService.suggestedSubjects.map((s) {
                return DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 14)));
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _subject = val);
              },
            ),
            const SizedBox(height: 12),

            // Optional note
            TextField(
              controller: _noteController,
              decoration: InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'e.g. Solved 15 calculus problems',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4F46E5),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Save Session'),
        ),
      ],
    );
  }
}

// ==========================================
// 11. Goal Picker Bottom Sheet
// ==========================================
class _GoalPickerSheet extends StatefulWidget {
  const _GoalPickerSheet({required this.currentGoalMinutes});

  final int currentGoalMinutes;

  @override
  State<_GoalPickerSheet> createState() => _GoalPickerSheetState();
}

class _GoalPickerSheetState extends State<_GoalPickerSheet> {
  late int _selectedMinutes;
  static const List<int> _presets = [30, 60, 90, 120, 150, 180, 240, 300];

  @override
  void initState() {
    super.initState();
    _selectedMinutes = widget.currentGoalMinutes;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2230) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Set Daily Study Target',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Currently: ${StudyTimerService.formatDuration(Duration(minutes: _selectedMinutes))}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Color(0xFF4F46E5), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 18),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _presets.map((mins) {
              final isSelected = _selectedMinutes == mins;
              final dur = Duration(minutes: mins);
              return ChoiceChip(
                label: Text(StudyTimerService.formatDuration(dur)),
                selected: isSelected,
                selectedColor: const Color(0xFF4F46E5),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
                onSelected: (selected) {
                  if (selected) setState(() => _selectedMinutes = mins);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Slider for fine tuning
          Slider(
            value: _selectedMinutes.toDouble(),
            min: 15,
            max: 360,
            divisions: 23,
            activeColor: const Color(0xFF4F46E5),
            label: StudyTimerService.formatDuration(Duration(minutes: _selectedMinutes)),
            onChanged: (val) {
              setState(() => _selectedMinutes = val.round());
            },
          ),
          const SizedBox(height: 16),

          ElevatedButton(
            onPressed: () => Navigator.pop(context, _selectedMinutes),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Confirm Goal', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 12. Subject Picker Bottom Sheet
// ==========================================
class _SubjectPickerSheet extends StatefulWidget {
  const _SubjectPickerSheet({required this.currentSubject});

  final String currentSubject;

  @override
  State<_SubjectPickerSheet> createState() => _SubjectPickerSheetState();
}

class _SubjectPickerSheetState extends State<_SubjectPickerSheet> {
  final TextEditingController _customSubjectController = TextEditingController();

  @override
  void dispose() {
    _customSubjectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2230) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Select Study Subject',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: StudyTimerService.suggestedSubjects.map((s) {
              final isSelected = widget.currentSubject == s;
              return ChoiceChip(
                label: Text(s),
                selected: isSelected,
                selectedColor: const Color(0xFF4F46E5),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
                onSelected: (selected) {
                  if (selected) Navigator.pop(context, s);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customSubjectController,
                  decoration: InputDecoration(
                    hintText: 'Or type custom subject...',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final text = _customSubjectController.text.trim();
                  if (text.isNotEmpty) Navigator.pop(context, text);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                ),
                child: const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
