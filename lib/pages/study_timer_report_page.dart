import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudyTimerReportPage extends StatefulWidget {
  const StudyTimerReportPage({super.key});

  @override
  State<StudyTimerReportPage> createState() => _StudyTimerReportPageState();
}

class _StudyTimerReportPageState extends State<StudyTimerReportPage> {
  static const _historyKey = 'study_timer_history_v1';
  static const _runningKey = 'study_timer_running';
  static const _segmentStartKey = 'study_timer_segment_start_epoch';

  List<_TimerInterval> _intervals = [];
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadReport();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => _loadReport());
  }

  Future<void> _loadReport() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final raw = prefs.getString(_historyKey) ?? '[]';
    final intervals = <_TimerInterval>[];
    try {
      for (final item in jsonDecode(raw) as List<dynamic>) {
        final map = item as Map<String, dynamic>;
        intervals.add(_TimerInterval(
          startedAt:
              DateTime.fromMillisecondsSinceEpoch(map['startedAt'] as int),
          endedAt: DateTime.fromMillisecondsSinceEpoch(map['endedAt'] as int),
        ));
      }
    } catch (_) {
      // Ignore old or malformed history entries.
    }
    if (prefs.getBool(_runningKey) ?? false) {
      final startedAt = DateTime.fromMillisecondsSinceEpoch(
        prefs.getInt(_segmentStartKey) ?? now.millisecondsSinceEpoch,
      );
      intervals.add(_TimerInterval(startedAt: startedAt, endedAt: now));
    }
    intervals.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    if (!mounted) return;
    setState(() {
      _intervals = intervals;
      _loading = false;
    });
  }

  Duration _total(Iterable<_TimerInterval> intervals) => intervals.fold(
        Duration.zero,
        (total, interval) => total + interval.duration,
      );

  Duration _totalInRange(
    Iterable<_TimerInterval> intervals,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) =>
      intervals.fold(Duration.zero, (total, interval) {
        final start = interval.startedAt.isAfter(rangeStart)
            ? interval.startedAt
            : rangeStart;
        final end =
            interval.endedAt.isBefore(rangeEnd) ? interval.endedAt : rangeEnd;
        return end.isAfter(start) ? total + end.difference(start) : total;
      });

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(const Duration(days: 6));
    final todayTotal = _totalInRange(_intervals, todayStart, now);
    final weekTotal = _totalInRange(_intervals, weekStart, now);
    final totalIntervals = _intervals;
    final dailyTotals = List.generate(7, (index) {
      final date = weekStart.add(Duration(days: index));
      final dayStart = DateTime(date.year, date.month, date.day);
      final nextDay = dayStart.add(const Duration(days: 1));
      final rangeEnd = nextDay.isBefore(now) ? nextDay : now;
      return (
        date: dayStart,
        total: _totalInRange(_intervals, dayStart, rangeEnd)
      );
    });
    final peakDailySeconds = dailyTotals
        .map((item) => item.total.inSeconds)
        .fold<int>(0, (peak, value) => value > peak ? value : peak);
    final averageInterval = totalIntervals.isEmpty
        ? Duration.zero
        : Duration(
            microseconds:
                _total(totalIntervals).inMicroseconds ~/ totalIntervals.length,
          );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FC),
      appBar: const CustomAppBar(title: 'Study Time Report'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReport,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4657CE), Color(0xFF7B61D1)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.timer_outlined,
                            size: 34, color: Colors.white),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Focused study time',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _summaryCard('Today', todayTotal)),
                      const SizedBox(width: 10),
                      Expanded(child: _summaryCard('Last 7 days', weekTotal)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _summaryCard(
                          'All time',
                          _total(totalIntervals),
                          subtitle: '${totalIntervals.length} intervals',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _summaryCard(
                          'Average interval',
                          averageInterval,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const Text('Daily breakdown',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: dailyTotals.map((item) {
                          final ratio = peakDailySeconds == 0
                              ? 0.0
                              : item.total.inSeconds / peakDailySeconds;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 48,
                                  child: Text(
                                    DateFormat.E().format(item.date),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value: ratio,
                                      minHeight: 9,
                                      backgroundColor: const Color(0xFFECEBFF),
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                        Color(0xFF6A5ACD),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 76,
                                  child: Text(
                                    _formatDuration(item.total),
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text('Session history',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_intervals.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                            'Start the timer widget to build your study report.'),
                      ),
                    )
                  else
                    ..._intervals.map(_historyCard),
                ],
              ),
            ),
    );
  }

  Widget _summaryCard(String title, Duration total, {String? subtitle}) => Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(color: Colors.black54, fontSize: 12)),
              const SizedBox(height: 8),
              Text(_formatDuration(total),
                  style: const TextStyle(
                      fontSize: 21, fontWeight: FontWeight.bold)),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle,
                    style:
                        const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ],
          ),
        ),
      );

  Widget _historyCard(_TimerInterval interval) => Card(
        elevation: 0,
        color: Colors.white,
        margin: const EdgeInsets.symmetric(vertical: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFECEBFF),
            child: Icon(
              Icons.menu_book_rounded,
              color: const Color(0xFF5850B8),
            ),
          ),
          title: Text(DateFormat.yMMMd().format(interval.startedAt)),
          subtitle: Text(
            '${DateFormat.jm().format(interval.startedAt)} – ${DateFormat.jm().format(interval.endedAt)}',
          ),
          trailing: Text(_formatDuration(interval.duration),
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
}

class _TimerInterval {
  const _TimerInterval({
    required this.startedAt,
    required this.endedAt,
  });

  final DateTime startedAt;
  final DateTime endedAt;
  Duration get duration => endedAt.difference(startedAt);
}
