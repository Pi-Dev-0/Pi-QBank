import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pi_qbank/services/study_routine_service.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';

class StudyRoutinePage extends StatefulWidget {
  const StudyRoutinePage({super.key});

  @override
  State<StudyRoutinePage> createState() => _StudyRoutinePageState();
}

class _StudyRoutinePageState extends State<StudyRoutinePage> {
  List<StudySession> _sessions = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await StudyRoutineService.loadRoutine();
    if (!mounted) return;
    setState(() {
      _sessions = sessions..sort(_compareSessions);
      _loading = false;
    });
  }

  int _compareSessions(StudySession a, StudySession b) =>
      a.startMinute.compareTo(b.startMinute);

  Future<void> _editSession([StudySession? existing]) async {
    final session = await showDialog<StudySession>(
      context: context,
      builder: (_) => _StudySessionDialog(existing: existing),
    );
    if (session == null || !mounted) return;
    final duplicate = _sessions.any(
        (item) => item.id != session.id && _sessionsOverlap(item, session));
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('This time overlaps another session on a selected day.')),
      );
      return;
    }
    setState(() {
      final index = _sessions.indexWhere((item) => item.id == session.id);
      if (index < 0) {
        _sessions.add(session);
      } else {
        _sessions[index] = session;
      }
      _sessions.sort(_compareSessions);
    });
    await _save();
  }

  bool _sessionsOverlap(StudySession first, StudySession second) {
    const minutesPerDay = 24 * 60;
    const minutesPerWeek = 7 * minutesPerDay;
    int duration(StudySession session) =>
        (session.endMinute - session.startMinute + minutesPerDay) %
        minutesPerDay;

    for (final firstDay in first.weekdays) {
      final firstStart = (firstDay - 1) * minutesPerDay + first.startMinute;
      final firstEnd = firstStart + duration(first);
      for (final secondDay in second.weekdays) {
        final secondStart =
            (secondDay - 1) * minutesPerDay + second.startMinute;
        final secondEnd = secondStart + duration(second);
        for (final weekOffset in [-minutesPerWeek, 0, minutesPerWeek]) {
          final shiftedStart = secondStart + weekOffset;
          final shiftedEnd = secondEnd + weekOffset;
          if (firstStart < shiftedEnd && shiftedStart < firstEnd) return true;
        }
      }
    }
    return false;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await StudyRoutineService.saveRoutine(_sessions);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Routine saved. Study reminders are set.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(StudySession session) async {
    setState(() => _sessions.removeWhere((item) => item.id == session.id));
    await _save();
  }

  String _range(StudySession session) {
    final start = TimeOfDay(
      hour: session.startMinute ~/ 60,
      minute: session.startMinute % 60,
    );
    final end = TimeOfDay(
      hour: session.endMinute ~/ 60,
      minute: session.endMinute % 60,
    );
    final range =
        '${MaterialLocalizations.of(context).formatTimeOfDay(start)} – '
        '${MaterialLocalizations.of(context).formatTimeOfDay(end)}';
    final overnight =
        session.endMinute < session.startMinute ? ' (+1 day)' : '';
    final durationMinutes =
        (session.endMinute - session.startMinute + 24 * 60) % (24 * 60);
    final hours = durationMinutes ~/ 60;
    final minutes = durationMinutes % 60;
    final duration = [
      if (hours > 0) '${hours}h',
      if (minutes > 0) '${minutes}m',
      if (hours == 0 && minutes == 0) '0m',
    ].join(' ');
    return '$range$overnight · $duration';
  }

  String _days(StudySession session) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (session.weekdays.length == 7) return 'Every day';
    return session.weekdays.map((day) => names[day - 1]).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FC),
      appBar: const CustomAppBar(title: 'Routine Maker'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _editSession(),
        icon: const Icon(Icons.add),
        label: const Text('Add session'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4657CE), Color(0xFF7B61D1)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.notifications_active_outlined,
                          color: Colors.white, size: 30),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Plan your study blocks. Pi-QBank will remind you when it’s time to switch subjects.',
                          style: TextStyle(color: Colors.white, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _sessions.isEmpty
                      ? _emptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: _sessions.length,
                          itemBuilder: (context, index) =>
                              _sessionCard(_sessions[index]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_month_outlined,
                  size: 60, color: Colors.indigo.shade200),
              const SizedBox(height: 14),
              const Text('Your routine is empty',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text(
                  'Add a subject and time period to start getting reminders.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      );

  Widget _sessionCard(StudySession session) => Card(
        margin: const EdgeInsets.symmetric(vertical: 7),
        elevation: 1,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _editSession(session),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFECEBFF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.menu_book_rounded,
                      color: Color(0xFF5850B8)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.subject,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      Text(_range(session),
                          style: const TextStyle(
                              color: Color(0xFF4945A2),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(_days(session),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete session',
                  onPressed: () => _delete(session),
                  icon:
                      const Icon(Icons.delete_outline, color: Colors.redAccent),
                ),
              ],
            ),
          ),
        ),
      );
}

class _StudySessionDialog extends StatefulWidget {
  const _StudySessionDialog({this.existing});
  final StudySession? existing;

  @override
  State<_StudySessionDialog> createState() => _StudySessionDialogState();
}

class _StudySessionDialogState extends State<_StudySessionDialog> {
  late final TextEditingController _subjectController;
  late TimeOfDay _start;
  late TimeOfDay _end;
  late Set<int> _weekdays;

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _subjectController = TextEditingController(text: existing?.subject ?? '');
    _start = existing == null
        ? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay(
            hour: existing.startMinute ~/ 60,
            minute: existing.startMinute % 60);
    _end = existing == null
        ? const TimeOfDay(hour: 10, minute: 0)
        : TimeOfDay(
            hour: existing.endMinute ~/ 60, minute: existing.endMinute % 60);
    _weekdays = existing?.weekdays.toSet() ?? {1, 2, 3, 4, 5, 6, 7};
  }

  int _minutes(TimeOfDay time) => time.hour * 60 + time.minute;

  Future<void> _chooseTime(bool start) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
    );
    if (selected != null) {
      setState(() {
        if (start) {
          _start = selected;
        } else {
          _end = selected;
        }
      });
    }
  }

  void _submit() {
    final subject = _subjectController.text.trim();
    if (subject.isEmpty ||
        _weekdays.isEmpty ||
        _minutes(_end) == _minutes(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Enter a subject, choose days, and set a valid time period.')),
      );
      return;
    }
    final id =
        widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    Navigator.pop(
      context,
      StudySession(
        id: id,
        subject: subject,
        startMinute: _minutes(_start),
        endMinute: _minutes(_end),
        weekdays: _weekdays.toList()..sort(),
      ),
    );
  }

  @override
  void dispose() {
    _subjectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            widget.existing == null ? 'Add study session' : 'Edit session'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _subjectController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  hintText: 'e.g. Physics',
                  prefixIcon: Icon(Icons.book_outlined),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _timeButton('From', _start, true)),
                  const SizedBox(width: 10),
                  Expanded(child: _timeButton('Until', _end, false)),
                ],
              ),
              const SizedBox(height: 18),
              const Text('Repeat on',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                children: List.generate(7, (index) {
                  final day = index + 1;
                  return FilterChip(
                    label: Text(_dayLabels[index]),
                    selected: _weekdays.contains(day),
                    onSelected: (selected) => setState(() {
                      selected ? _weekdays.add(day) : _weekdays.remove(day);
                    }),
                  );
                }),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: const Text('Save')),
        ],
      );

  Widget _timeButton(String label, TimeOfDay value, bool start) =>
      OutlinedButton(
        onPressed: () => _chooseTime(start),
        style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
            const SizedBox(height: 3),
            Text(
                DateFormat.jm()
                    .format(DateTime(2020, 1, 1, value.hour, value.minute)),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
