import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

import '../services/qr_alarm_service.dart';

class QrAlarmPage extends StatefulWidget {
  const QrAlarmPage({super.key});

  @override
  State<QrAlarmPage> createState() => _QrAlarmPageState();
}

class _QrAlarmPageState extends State<QrAlarmPage> {
  List<QrAlarm> _alarms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final alarms = await QrAlarmService.loadAlarms();
    if (!mounted) return;
    setState(() {
      _alarms = alarms;
      _loading = false;
    });
  }

  Future<void> _addAlarm() async {
    final alarm = await Navigator.push<QrAlarm>(
      context,
      MaterialPageRoute(builder: (_) => const _CreateQrAlarmPage()),
    );
    if (alarm == null) return;
    final alarms = [..._alarms, alarm];
    await QrAlarmService.saveAlarms(alarms);
    if (!mounted) return;
    setState(() => _alarms = alarms);
  }

  Future<void> _toggle(QrAlarm alarm, bool enabled) async {
    final alarms = _alarms
        .map((item) => item.id == alarm.id
            ? QrAlarm(
                id: item.id,
                label: item.label,
                hour: item.hour,
                minute: item.minute,
                weekdays: item.weekdays,
                qrCodeName: item.qrCodeName,
                qrValue: item.qrValue,
                enabled: enabled,
              )
            : item)
        .toList();
    await QrAlarmService.saveAlarms(alarms);
    if (mounted) setState(() => _alarms = alarms);
  }

  Future<void> _delete(QrAlarm alarm) async {
    final alarms = _alarms.where((item) => item.id != alarm.id).toList();
    await QrAlarmService.saveAlarms(alarms);
    if (mounted) setState(() => _alarms = alarms);
  }

  Future<void> _openScanner() async {
    final dismissed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const QrAlarmScannerPage()),
    );
    if (dismissed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alarm dismissed by QR scan')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('QR Alarm')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addAlarm,
        icon: const Icon(Icons.add_alarm_rounded),
        label: const Text('Add alarm'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8A65), Color(0xFFFFB74D)],
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.qr_code_2_rounded,
                          size: 34, color: Colors.white),
                      SizedBox(height: 12),
                      Text(
                        'Wake up and walk to dismiss',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 19,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Choose a QR code you already have, place it away from your bed, then scan that same code to turn off the alarm.',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.emergency_outlined,
                        color: theme.colorScheme.error),
                    title: const Text('Emergency dismissal'),
                    subtitle: const Text(
                        'The ringing screen offers a confirmation to stop an alarm without scanning.'),
                  ),
                ),
                const SizedBox(height: 14),
                if (_alarms.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 46),
                    child: Column(
                      children: [
                        Icon(Icons.alarm_add_rounded,
                            size: 54, color: Colors.black38),
                        SizedBox(height: 12),
                        Text('No QR alarms yet'),
                        SizedBox(height: 4),
                        Text(
                            'Add an alarm and choose a QR code to dismiss it.'),
                      ],
                    ),
                  )
                else
                  ..._alarms.map((alarm) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding:
                              const EdgeInsets.fromLTRB(16, 8, 8, 8),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFFFF0E8),
                            child: Icon(Icons.alarm_rounded,
                                color: theme.colorScheme.primary),
                          ),
                          title: Text(alarm.label,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            '${TimeOfDay(hour: alarm.hour, minute: alarm.minute).format(context)} · ${alarm.weekdays.isEmpty ? 'Once' : _weekdayLabel(alarm.weekdays)}\nQR: ${alarm.qrCodeName}',
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: alarm.enabled,
                                onChanged: (value) => _toggle(alarm, value),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'delete') _delete(alarm);
                                  if (value == 'scan') _openScanner();
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'scan',
                                      child: Text('Scan to dismiss')),
                                  PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete alarm')),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )),
              ],
            ),
    );
  }

  String _weekdayLabel(List<int> weekdays) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays.map((day) => names[day - 1]).join(', ');
  }
}

class _CreateQrAlarmPage extends StatefulWidget {
  const _CreateQrAlarmPage();

  @override
  State<_CreateQrAlarmPage> createState() => _CreateQrAlarmPageState();
}

class _CreateQrAlarmPageState extends State<_CreateQrAlarmPage> {
  final _nameController = TextEditingController();
  final _qrValueController = TextEditingController();
  final _qrNameController = TextEditingController();
  TimeOfDay _selectedTime = TimeOfDay.now();
  final Set<int> _selectedDays = {};
  List<SavedQrCode> _savedCodes = [];
  String? _selectedSavedCodeId;
  String? _qrError;
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _loadSavedCodes();
  }

  Future<void> _loadSavedCodes() async {
    final codes = await QrAlarmService.loadSavedQrCodes();
    if (mounted) setState(() => _savedCodes = codes);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _qrValueController.dispose();
    _qrNameController.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrCodeCapturePage()),
    );
    if (value == null || !mounted) return;
    setState(() {
      _qrValueController.text = value;
      _selectedSavedCodeId = null;
      _qrError = null;
      if (_qrNameController.text.trim().isEmpty) {
        _qrNameController.text = 'Scanned QR code ${_savedCodes.length + 1}';
      }
    });
  }

  void _selectSavedCode(String? id) {
    final selected = _savedCodes.where((code) => code.id == id).firstOrNull;
    setState(() {
      _selectedSavedCodeId = id;
      if (selected != null) {
        _qrValueController.text = selected.value;
        _qrNameController.text = selected.name;
        _qrError = null;
      }
    });
  }

  Future<void> _pickTime() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && mounted) setState(() => _selectedTime = picked);
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final qrValue = _qrValueController.text;
    if (qrValue.trim().isEmpty) {
      setState(() => _qrError = 'Scan, choose, or enter a QR code first.');
      return;
    }
    final name = _nameController.text.trim();
    final savedQrName = _qrNameController.text.trim().isEmpty
        ? 'Saved QR code'
        : _qrNameController.text.trim();
    final reusableCode = SavedQrCode(
      id: _selectedSavedCodeId ?? const Uuid().v4(),
      name: savedQrName,
      value: qrValue,
    );
    await QrAlarmService.saveQrCode(reusableCode);
    if (!mounted) return;
    Navigator.pop(
      context,
      QrAlarm(
        id: const Uuid().v4(),
        label: name.isEmpty ? 'QR Alarm' : name,
        hour: _selectedTime.hour,
        minute: _selectedTime.minute,
        weekdays: _selectedDays.toList()..sort(),
        qrCodeName: savedQrName,
        qrValue: qrValue,
        enabled: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create QR alarm')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Alarm name',
                hintText: 'Morning study',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              child: ListTile(
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('Alarm time'),
                subtitle: Text(_selectedTime.format(context)),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _pickTime,
              ),
            ),
            const SizedBox(height: 18),
            Text('Repeat on', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: List.generate(7, (index) {
                final day = index + 1;
                return FilterChip(
                  label: Text(_days[index]),
                  selected: _selectedDays.contains(day),
                  onSelected: (selected) => setState(() {
                    selected
                        ? _selectedDays.add(day)
                        : _selectedDays.remove(day);
                  }),
                );
              }),
            ),
            const SizedBox(height: 8),
            Text(
              'Leave all days unselected to create a one time alarm.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            Text('QR code to dismiss',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_savedCodes.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _selectedSavedCodeId,
                decoration: const InputDecoration(
                  labelText: 'Use a saved QR code',
                  border: OutlineInputBorder(),
                ),
                items: _savedCodes
                    .map((code) => DropdownMenuItem(
                          value: code.id,
                          child:
                              Text(code.name, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: _selectSavedCode,
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _scanQr,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan a QR code'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _qrNameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'QR code name for reuse',
                hintText: 'Bathroom QR',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _qrValueController,
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => setState(() {
                _selectedSavedCodeId = null;
                _qrError = null;
              }),
              decoration: InputDecoration(
                labelText: 'QR contents (or enter manually)',
                hintText: 'Scan a code or type its contents',
                border: const OutlineInputBorder(),
                errorText: _qrError,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Scanned codes are saved here so you can reuse them for other alarms.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.alarm_add_rounded),
              label: const Text('Save alarm'),
            ),
          ],
        ),
      );
}

class QrAlarmScannerPage extends StatefulWidget {
  const QrAlarmScannerPage({super.key});

  @override
  State<QrAlarmScannerPage> createState() => _QrAlarmScannerPageState();
}

class _QrAlarmScannerPageState extends State<QrAlarmScannerPage> {
  final _scannerController = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
  );
  bool _processing = false;
  String? _message;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final value = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (value == null || value.isEmpty) return;
    setState(() => _processing = true);
    final dismissed = await QrAlarmService.dismissByQr(value);
    if (!mounted) return;
    if (dismissed) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _processing = false;
        _message = 'This code does not match a ringing QR alarm.';
      });
    }
  }

  Future<void> _emergencyDismiss() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emergency dismissal?'),
        content: const Text(
            'This will stop the currently ringing QR alarm without scanning its code.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep scanning')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Dismiss alarm')),
        ],
      ),
    );
    if (approved != true) return;
    final dismissed = await QrAlarmService.dismissEmergency();
    if (!mounted) return;
    if (dismissed) {
      Navigator.pop(context, true);
    } else {
      setState(() => _message = 'No QR alarm is ringing right now.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan alarm QR code')),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _scannerController,
                    onDetect: _onDetect,
                  ),
                  Center(
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 4),
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                  if (_message != null)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        margin: const EdgeInsets.all(20),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_message!,
                            style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _emergencyDismiss,
                    icon: const Icon(Icons.emergency_outlined),
                    label: const Text('Emergency dismissal'),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class QrCodeCapturePage extends StatefulWidget {
  const QrCodeCapturePage({super.key});

  @override
  State<QrCodeCapturePage> createState() => _QrCodeCapturePageState();
}

class _QrCodeCapturePageState extends State<QrCodeCapturePage> {
  final _scannerController = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
  );
  bool _captured = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_captured) return;
    final value = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (value == null || value.isEmpty) return;
    _captured = true;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan QR for alarm')),
        body: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(controller: _scannerController, onDetect: _onDetect),
            Center(
              child: Container(
                width: 270,
                height: 270,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 4),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
            const Positioned(
              left: 24,
              right: 24,
              bottom: 36,
              child: Text(
                'Point the camera at the QR code you want this alarm to use.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
      );
}
