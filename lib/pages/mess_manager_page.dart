import 'package:flutter/material.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:pi_qbank/widgets/delete_confirmation_dialog.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pi_qbank/models/mess_manager_models.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

class MessManagerPage extends StatefulWidget {
  const MessManagerPage({super.key});

  @override
  State<MessManagerPage> createState() => _MessManagerPageState();
}

class _MessManagerPageState extends State<MessManagerPage> {
  // State variables
  final List<Member> _members = [];
  final List<Meal> _meals = [];
  final List<ManagerExpense> _managerExpenses = [];
  final List<MiscExpense> _miscExpenses = [];
  final List<MemberExpense> _memberExpenses = [];
  final List<Deposit> _deposits = [];

  // Share keys
  final GlobalKey _finalReportKey = GlobalKey();
  final Map<String, GlobalKey> _memberCardKeys = {};
  final GlobalKey _summaryKey = GlobalKey();
  final GlobalKey _expenseListKey = GlobalKey();

  // Selected member IDs
  String _selectedExpenseMemberId = '';

  // Controllers
  final TextEditingController _expenseAmountController =
      TextEditingController();
  final TextEditingController _expenseDescriptionController =
      TextEditingController();

  // Getters

  // Manager cash after expenses (based on initial deposits only)
  double get _totalInitialDeposits =>
      _members.fold(0.0, (sum, m) => sum + m.initialDeposit);
  double get _managerCashInHand =>
      _totalInitialDeposits - (_totalManagerExpenses + _totalMiscExpenses);

  // Controllers for input fields
  final TextEditingController _newMemberNameController =
      TextEditingController();
  final TextEditingController _initialDepositController =
      TextEditingController();
  final TextEditingController _managerExpenseAmountController =
      TextEditingController();
  final TextEditingController _managerExpenseDescriptionController =
      TextEditingController();
  final TextEditingController _miscExpenseAmountController =
      TextEditingController();
  final TextEditingController _miscExpenseDescriptionController =
      TextEditingController();
  final TextEditingController _memberExpenseAmountController =
      TextEditingController();
  final TextEditingController _memberExpenseDescriptionController =
      TextEditingController();

  // Persistence keys
  static const String _kMembers = 'mm_members';
  static const String _kMeals = 'mm_meals';
  static const String _kManagerExpenses = 'mm_manager_expenses';
  static const String _kMiscExpenses = 'mm_misc_expenses';
  static const String _kMemberExpenses = 'mm_member_expenses';
  static const String _kDeposits = 'mm_deposits';
  static const String _kAppsScriptUrl = 'mm_apps_script_url';

  // External sync endpoint
  String _appsScriptUrl = '';

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  void _handleAddMiscExpense() {
    final amount = _parseAmount(_miscExpenseAmountController.text);
    final description = _miscExpenseDescriptionController.text.trim();

    if (amount != null && amount > 0 && description.isNotEmpty) {
      setState(() {
        _miscExpenses.add(MiscExpense(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          amount: amount,
          description: description,
        ));
        _miscExpenseAmountController.clear();
        _miscExpenseDescriptionController.clear();
      });
      _saveState();
      _showSnackBar('বিবিধ খরচ যোগ করা হয়েছে।', Colors.green);
    } else {
      _showSnackBar('সঠিক পরিমাণ এবং বিবরণ দিন।', Colors.red);
    }
  }

  @override
  void dispose() {
    _newMemberNameController.dispose();
    _initialDepositController.dispose();
    _managerExpenseAmountController.dispose();
    _managerExpenseDescriptionController.dispose();
    _miscExpenseAmountController.dispose();
    _miscExpenseDescriptionController.dispose();
    _memberExpenseAmountController.dispose();
    _memberExpenseDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kMembers, jsonEncode(_members.map((e) => e.toMap()).toList()));
      await prefs.setString(
          _kMeals, jsonEncode(_meals.map((e) => e.toMap()).toList()));
      await prefs.setString(_kManagerExpenses,
          jsonEncode(_managerExpenses.map((e) => e.toMap()).toList()));
      await prefs.setString(_kMiscExpenses,
          jsonEncode(_miscExpenses.map((e) => e.toMap()).toList()));
      await prefs.setString(_kMemberExpenses,
          jsonEncode(_memberExpenses.map((e) => e.toMap()).toList()));
      await prefs.setString(
          _kDeposits, jsonEncode(_deposits.map((e) => e.toMap()).toList()));
    } catch (e) {
      // Non-fatal: ignore save errors but log via snackbar once
    }
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final membersStr = prefs.getString(_kMembers);
      final mealsStr = prefs.getString(_kMeals);
      final mngExpStr = prefs.getString(_kManagerExpenses);
      final miscExpStr = prefs.getString(_kMiscExpenses);
      final mbrExpStr = prefs.getString(_kMemberExpenses);
      final depositsStr = prefs.getString(_kDeposits);
      _appsScriptUrl = prefs.getString(_kAppsScriptUrl) ?? '';

      if (membersStr != null) {
        final data = jsonDecode(membersStr) as List<dynamic>;
        _members.clear();
        _members
            .addAll(data.map((e) => Member.fromMap(e as Map<String, dynamic>)));
      }
      if (mealsStr != null) {
        final data = jsonDecode(mealsStr) as List<dynamic>;
        _meals.clear();
        _meals.addAll(data.map((e) => Meal.fromMap(e as Map<String, dynamic>)));
      }
      if (mngExpStr != null) {
        final data = jsonDecode(mngExpStr) as List<dynamic>;
        _managerExpenses.clear();
        _managerExpenses.addAll(
            data.map((e) => ManagerExpense.fromMap(e as Map<String, dynamic>)));
      }
      if (miscExpStr != null) {
        final data = jsonDecode(miscExpStr) as List<dynamic>;
        _miscExpenses.clear();
        _miscExpenses.addAll(
            data.map((e) => MiscExpense.fromMap(e as Map<String, dynamic>)));
      }
      if (mbrExpStr != null) {
        final data = jsonDecode(mbrExpStr) as List<dynamic>;
        _memberExpenses.clear();
        _memberExpenses.addAll(
            data.map((e) => MemberExpense.fromMap(e as Map<String, dynamic>)));
      }
      if (depositsStr != null) {
        final data = jsonDecode(depositsStr) as List<dynamic>;
        _deposits.clear();
        _deposits.addAll(
            data.map((e) => Deposit.fromMap(e as Map<String, dynamic>)));
      }

      if (mounted) setState(() {});
    } catch (e) {
      // If anything goes wrong, don't crash the UI; continue with empty state
    }
  }

  // Build export payload for Google Sheets sync
  Map<String, dynamic> _buildExportPayload() {
    return {
      'members': _members.map((e) => e.toMap()).toList(),
      'meals': _meals.map((e) => e.toMap()).toList(),
      'managerExpenses': _managerExpenses.map((e) => e.toMap()).toList(),
      'memberExpenses': _memberExpenses.map((e) => e.toMap()).toList(),
      'deposits': _deposits.map((e) => e.toMap()).toList(),
      'report': _reportData
          .map((r) => {
                'memberId': r.memberId,
                'memberName': r.memberName,
                'totalMeals': r.totalMeals,
                'initialDeposit': r.initialDeposit,
                'personalExpense': r.personalExpense,
                'mealCost': r.mealCost,
                'totalContribution': r.totalContribution,
                'balance': r.balance,
                'mealRate': r.mealRate,
              })
          .toList(),
      'generatedAt': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _promptForAppsScriptUrl() async {
    final controller = TextEditingController(text: _appsScriptUrl);
    final newUrl = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('প্রথমবার সেটআপ: Google Apps Script'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // URL input on top
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Apps Script ওয়েব অ্যাপ URL',
                      hintText: 'https://script.google.com/.../exec',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'সেটআপ নির্দেশনা (একবারই করতে হবে):',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '১) একটি নতুন Google Sheet খুলুন (নাম দিতে পারেন: "Mess Manager").\n'
                    '২) Extensions > Apps Script এ যান।\n'
                    '৩) নিচের কোডটি Code.gs এ পেস্ট করে সেভ করুন।\n'
                    '৪) Deploy > New deployment > Web app নির্বাচন করুন।\n'
                    '   Execute as: Me, Who has access: Anyone with the link দিন।\n'
                    '৫) Deploy করে প্রাপ্ত Web App URL টি উপরের ঘরে পেস্ট করে সেভ করুন।',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Apps Script কোড :',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: _appsScriptCode));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('কোড কপি হয়েছে।')));
                          }
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('কোড কপি করুন'),
                      )
                    ],
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: SelectableText(
                      _appsScriptCode,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('বাতিল'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(controller.text.trim());
              },
              child: const Text('সেভ'),
            ),
          ],
        );
      },
    );
    if (newUrl != null) {
      setState(() {
        _appsScriptUrl = newUrl;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAppsScriptUrl, _appsScriptUrl);
      _showSnackBar('Apps Script URL সংরক্ষণ করা হয়েছে।', Colors.green);
    }
  }

  String get _appsScriptCode => '''/* global ContentService, SpreadsheetApp */

function doGet(e) {
  return ContentService
    .createTextOutput(JSON.stringify({ status: 'ok', message: 'MessManager endpoint up' }))
    .setMimeType(ContentService.MimeType.JSON);
}

function doPost(e) {
  try {
    var payload = JSON.parse(e.postData.contents);

    if (!payload || payload.action !== 'sync' || !payload.payload) {
      return _json({ success: false, message: 'Invalid payload' }, 400);
    }

    var data = payload.payload;

    _writeTable('Members', ['id', 'name', 'initialDeposit'], data.members || [], function (m) {
      return [m.id, m.name, _num(m.initialDeposit)];
    });

    _writeTable('Meals', ['memberId', 'count'], data.meals || [], function (m) {
      return [m.memberId, _int(m.count)];
    });

    _writeTable('ManagerExpenses', ['id', 'amount', 'description', 'date'], data.managerExpenses || [], function (x) {
      return [x.id, _num(x.amount), x.description, _date(x.date)];
    });

    _writeTable('MemberExpenses', ['id', 'memberId', 'amount', 'description', 'date'], data.memberExpenses || [], function (x) {
      return [x.id, x.memberId, _num(x.amount), x.description, _date(x.date)];
    });

    _writeTable('Deposits', ['id', 'memberId', 'amount', 'date'], data.deposits || [], function (x) {
      return [x.id, x.memberId, _num(x.amount), _date(x.date)];
    });

    _writeTable('Report', [
      'memberId', 'memberName', 'totalMeals', 'initialDeposit', 'personalExpense',
      'mealCost', 'totalContribution', 'balance', 'mealRate', 'generatedAt'
    ], data.report || [], function (r) {
      return [
        r.memberId, r.memberName, _int(r.totalMeals), _num(r.initialDeposit),
        _num(r.personalExpense), _num(r.mealCost), _num(r.totalContribution),
        _num(r.balance), _num(r.mealRate), _date(data.generatedAt)
      ];
    });

    return _json({ success: true, message: 'Synced successfully' }, 200);
  } catch (err) {
    return _json({ success: false, message: String(err) }, 500);
  }
}

function _writeTable(sheetName, headers, items, mapRow) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(sheetName);
  if (!sheet) {
    sheet = ss.insertSheet(sheetName);
  } else {
    sheet.clear();
  }
  if (!items) items = [];

  sheet.getRange(1, 1, 1, headers.length).setValues([headers]);

  if (items.length === 0) return;

  var rows = [];
  for (var i = 0; i < items.length; i++) {
    rows.push(mapRow(items[i]));
  }
  sheet.getRange(2, 1, rows.length, headers.length).setValues(rows);

  _applyFormats(sheetName, headers);
}

function _applyFormats(sheetName, headers) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(sheetName);
  if (!sheet) return;

  for (var c = 0; c < headers.length; c++) {
    var h = headers[c].toLowerCase();
    if (h.indexOf('date') !== -1 || h === 'generatedat') {
      sheet.getRange(2, c + 1, Math.max(0, sheet.getLastRow() - 1), 1).setNumberFormat('yyyy-mm-dd hh:mm');
    } else if (['amount', 'initialdeposit', 'personalexpense', 'mealcost', 'totalcontribution', 'balance', 'mealrate'].indexOf(h) !== -1) {
      sheet.getRange(2, c + 1, Math.max(0, sheet.getLastRow() - 1), 1).setNumberFormat('#,##0.00');
    } else if (h.indexOf('count') !== -1 || h.indexOf('meals') !== -1 || h.indexOf('totalmeals') !== -1) {
      sheet.getRange(2, c + 1, Math.max(0, sheet.getLastRow() - 1), 1).setNumberFormat('0');
    }
  }
}

function _num(x) {
  var n = Number(x);
  return isNaN(n) ? 0 : n;
}
function _int(x) {
  var n = parseInt(x, 10);
  return isNaN(n) ? 0 : n;
}
function _date(s) {
  if (!s) return '';
  var d = new Date(s);
  return isNaN(d.getTime()) ? '' : d;
}

function _json(obj, code) {
  var out = ContentService.createTextOutput(JSON.stringify(obj));
  out.setMimeType(ContentService.MimeType.JSON);
  return out.setStatusCode(code || 200);
}
''';

  Future<void> _syncToGoogleSheets() async {
    try {
      if (_appsScriptUrl.isEmpty) {
        await _promptForAppsScriptUrl();
        if (_appsScriptUrl.isEmpty) return;
      }

      final uri = Uri.parse(_appsScriptUrl);
      final payload = {
        'action': 'sync',
        'payload': _buildExportPayload(),
      };

      _showSnackBar('সিঙ্ক শুরু হচ্ছে...', Colors.blueGrey);
      final resp = await http.post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (resp.statusCode == 200) {
        // Try to parse response JSON
        bool success = false;
        String? message;
        try {
          final data = jsonDecode(resp.body);
          success = (data['success'] == true) || (data['status'] == 'ok');
          message = data['message'] as String?;
        } catch (_) {
          // If not JSON, consider status 200 as success
          success = true;
        }
        if (success) {
          _showSnackBar(message ?? 'ডাটা সফলভাবে সিঙ্ক হয়েছে।', Colors.green);
        } else {
          _showSnackBar(message ?? 'সিঙ্ক ব্যর্থ হয়েছে।', Colors.red);
        }
      } else {
        _showSnackBar('সার্ভার ত্রুটি: ${resp.statusCode}', Colors.red);
      }
    } catch (e) {
      _showSnackBar('সিঙ্ক করতে সমস্যা: $e', Colors.red);
    }
  }

  // Handlers
  void _handleAddMember() {
    if (_newMemberNameController.text.trim().isNotEmpty) {
      final initialDeposit =
          double.tryParse(_initialDepositController.text) ?? 0.0;
      setState(() {
        final newMember = Member(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: _newMemberNameController.text.trim(),
          initialDeposit: initialDeposit,
        );
        _members.add(newMember);
        _meals.add(Meal(memberId: newMember.id, count: 0));
        _newMemberNameController.clear();
        _initialDepositController.clear();
      });
      _saveState();
      _showSnackBar('সদস্য সফলভাবে যোগ করা হয়েছে।', Colors.green);
    } else {
      _showSnackBar('সদস্যের নাম খালি রাখা যাবে না।', Colors.red);
    }
  }

  void _handleDeleteMember(String memberId) {
    setState(() {
      _members.removeWhere((m) => m.id == memberId);
      _meals.removeWhere((m) => m.memberId == memberId);
      _deposits.removeWhere((d) => d.memberId == memberId);
      _memberExpenses.removeWhere((e) => e.memberId == memberId);
    });
    _saveState();
    _showSnackBar('সদস্য মুছে ফেলা হয়েছে।', Colors.orange);
  }

  void _handleAddManagerExpense() {
    final amount = _parseAmount(_managerExpenseAmountController.text);
    final description = _managerExpenseDescriptionController.text.trim();

    if (amount != null && amount > 0 && description.isNotEmpty) {
      setState(() {
        _managerExpenses.add(ManagerExpense(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          amount: amount,
          description: description,
        ));
        _managerExpenseAmountController.clear();
        _managerExpenseDescriptionController.clear();
      });
      _saveState();
      _showSnackBar('ম্যানেজারের খরচ যোগ করা হয়েছে।', Colors.green);
    } else {
      _showSnackBar('সঠিক পরিমাণ এবং বিবরণ দিন।', Colors.red);
    }
  }

  void _handleAddMemberExpense() {
    final amount = _parseAmount(_expenseAmountController.text);
    final description = _expenseDescriptionController.text.trim();

    // Ensure a member is selected; default to first member if none selected
    if (_selectedExpenseMemberId.isEmpty && _members.isNotEmpty) {
      _selectedExpenseMemberId = _members.first.id;
    }

    if (amount != null &&
        amount > 0 &&
        description.isNotEmpty &&
        _selectedExpenseMemberId.isNotEmpty) {
      setState(() {
        _memberExpenses.add(MemberExpense(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          memberId: _selectedExpenseMemberId,
          amount: amount,
          description: description,
        ));
        _expenseAmountController.clear();
        _expenseDescriptionController.clear();
        _selectedExpenseMemberId = '';
      });
      _saveState();
      _showSnackBar('সদস্যের খরচ যোগ করা হয়েছে।', Colors.green);
    } else {
      _showSnackBar(
          'সদস্য নির্বাচন করুন, সঠিক পরিমাণ এবং বিবরণ দিন।', Colors.red);
    }
  }

  void _handleAddExpense() {
    // This is just a wrapper for _handleAddMemberExpense for backward compatibility
    _handleAddMemberExpense();
  }

  // Show SnackBar
  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Share a widget (by key) as image
  Future<void> _shareKeyAsImage(GlobalKey key, String fileName,
      {String? text}) async {
    // Allow UI to settle (e.g., ripple effects) before capturing
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;

    // Fetch context after the async gap
    BuildContext? ctx = key.currentContext;
    if (ctx == null) {
      _showSnackBar('শেয়ার করতে ব্যর্থ: কন্টেন্ট পাওয়া যায়নি।', Colors.red);
      return;
    }

    // Ensure the target is visible/painted
    if (!ctx.mounted) return;
    await Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 1), alignment: 0.5);
    await Future.delayed(const Duration(milliseconds: 16));
    // ignore: deprecated_member_use
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    // Re-fetch context again after async gaps
    ctx = key.currentContext;
    if (ctx == null) {
      _showSnackBar('শেয়ার করতে ব্যর্থ: কন্টেন্ট পাওয়া যায়নি।', Colors.red);
      return;
    }

    if (!ctx.mounted) return;
    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      _showSnackBar('শেয়ার করতে ব্যর্থ: রেন্ডারিং সমস্যা।', Colors.red);
      return;
    }
    final boundary = renderObject;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final image = await boundary.toImage(pixelRatio: (dpr * 2).clamp(2.0, 4.0));
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      _showSnackBar('শেয়ার করতে ব্যর্থ: ইমেজ তৈরি হয়নি।', Colors.red);
      return;
    }
    final pngBytes = byteData.buffer.asUint8List();
    // Use a unique filename and a temp file path to avoid preview caching
    final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$uniqueName';
    final file = File(filePath);
    await file.writeAsBytes(pngBytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png', name: uniqueName)],
      text: text,
    );
  }

  // Helpers: parse amounts with Bangla numerals and currency symbols
  String _normalizeDigits(String input) {
    const bangla = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
    final buffer = StringBuffer();
    for (final ch in input.trim().characters) {
      final idx = bangla.indexOf(ch);
      if (idx != -1) {
        buffer.write(idx.toString());
      } else {
        buffer.write(ch);
      }
    }
    return buffer.toString();
  }

  double? _parseAmount(String raw) {
    final normalized = _normalizeDigits(raw)
        .replaceAll('৳', '')
        .replaceAll('tk', '')
        .replaceAll('TK', '')
        .replaceAll(',', '')
        .trim();
    return double.tryParse(normalized);
  }

  // Edit initial deposit for a member
  Future<void> _showEditInitialDepositDialog(Member member) async {
    final controller =
        TextEditingController(text: member.initialDeposit.toStringAsFixed(2));
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('প্রাথমিক জমা সম্পাদনা'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'প্রাথমিক জমা',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixText: '৳ ',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('বন্ধ করুন'),
            ),
            ElevatedButton(
              onPressed: () {
                final val = double.tryParse(controller.text.trim());
                if (val == null || val < 0) {
                  _showSnackBar('সঠিক পরিমাণ দিন।', Colors.red);
                  return;
                }
                setState(() {
                  final idx = _members.indexWhere((m) => m.id == member.id);
                  if (idx != -1) {
                    _members[idx] = Member(
                      id: member.id,
                      name: member.name,
                      initialDeposit: val,
                    );
                  }
                });
                _saveState();
                Navigator.of(context).pop();
                _showSnackBar(
                    'প্রাথমিক জমা হালনাগাদ করা হয়েছে।', Colors.green);
              },
              child: const Text('সেভ করুন'),
            ),
          ],
        );
      },
    );
  }

  // Calculations
  double get _totalManagerExpenses =>
      _managerExpenses.fold(0.0, (sum, e) => sum + e.amount);
  double get _totalMemberExpenses =>
      _memberExpenses.fold(0.0, (sum, e) => sum + e.amount);
  double get _totalMiscExpenses =>
      _miscExpenses.fold(0.0, (sum, e) => sum + e.amount);
  // Meal-related total excludes misc expenses (misc split equally by headcount)
  double get _totalExpenses => _totalManagerExpenses + _totalMemberExpenses;
  int get _totalMeals => _meals.fold(0, (sum, m) => sum + m.count);
  double get _mealRate => _totalMeals > 0 ? _totalExpenses / _totalMeals : 0.0;

  List<ReportData> get _reportData {
    return _members.map((member) {
      final memberMeals = _meals
          .firstWhere((m) => m.memberId == member.id,
              orElse: () => Meal(memberId: member.id, count: 0))
          .count;
      final memberDeposit = member.initialDeposit;
      final personalExpense = _memberExpenses
          .where((e) => e.memberId == member.id)
          .fold(0.0, (sum, e) => sum + e.amount);
      final totalContribution = memberDeposit + personalExpense;
      final mealCost = memberMeals * _mealRate;
      final balance = totalContribution - mealCost;
      return ReportData(
        memberId: member.id,
        memberName: member.name,
        totalMeals: memberMeals,
        initialDeposit: memberDeposit,
        personalExpense: personalExpense,
        totalContribution: totalContribution,
        mealCost: mealCost,
        balance: balance,
        mealRate: _mealRate,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: CustomAppBar(
          title: 'মেস ম্যানেজার',
          actions: [
            IconButton(
              icon: const Icon(Icons.cloud_upload),
              onPressed: _syncToGoogleSheets,
              tooltip: 'Google Sheets এ সিঙ্ক করুন',
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary Section
              Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: RepaintBoundary(
                  key: _summaryKey,
                  child: Container(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header with share button inside the box
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildSectionTitle('মেস এর হিসাব'),
                              IconButton(
                                icon: const Icon(Icons.ios_share,
                                    color: Colors.blueGrey),
                                tooltip: 'মেস এর হিসাব শেয়ার করুন',
                                onPressed: () => _shareKeyAsImage(
                                    _summaryKey, 'summary_report.png',
                                    text: 'মেস এর হিসাব'),
                              ),
                            ],
                          ),
                          _buildCalculationRow('মোট জমা:',
                              '${_members.fold(0.0, (sum, m) => sum + m.initialDeposit).toStringAsFixed(2)} টাকা',
                              textColor: Colors.green),
                          _buildCalculationRow('মোট খরচ:',
                              '${_totalExpenses.toStringAsFixed(2)} টাকা',
                              textColor: Colors.red),
                          _buildCalculationRow('ম্যানেজারের খরচ:',
                              '${_totalManagerExpenses.toStringAsFixed(2)} টাকা',
                              textColor: Colors.red),
                          _buildCalculationRow('সদস্যদের খরচ:',
                              '${_totalMemberExpenses.toStringAsFixed(2)} টাকা',
                              textColor: Colors.red),
                          _buildCalculationRow('বিবিধ খরচ:',
                              '${_totalMiscExpenses.toStringAsFixed(2)} টাকা',
                              textColor: Colors.red),
                          if (_members.isNotEmpty)
                            _buildCalculationRow('প্রতি সদস্যের বিবিধ অংশ:',
                                '${(_totalMiscExpenses / _members.length).toStringAsFixed(2)} টাকা'),
                          _buildCalculationRow('ম্যানেজারের হাতে অবশিষ্ট:',
                              '${_managerCashInHand.toStringAsFixed(2)} টাকা',
                              textColor: _managerCashInHand >= 0
                                  ? Colors.green
                                  : Colors.red),
                          _buildCalculationRow(
                              'মোট মিল সংখ্যা:', '$_totalMeals টি'),
                          _buildCalculationRow('মিল রেট:',
                              '${_mealRate.toStringAsFixed(2)} টাকা'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Manager Expenses Section
              Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionTitle('ম্যানেজারের খরচ'),
                      TextField(
                        controller: _managerExpenseDescriptionController,
                        decoration: InputDecoration(
                          labelText: 'খরচের বিবরণ',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _managerExpenseAmountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'পরিমাণ',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          prefixText: '৳ ',
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _handleAddManagerExpense,
                          icon: const Icon(Icons.add),
                          label: const Text('খরচ যোগ করুন'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Misc Expenses Section
              Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionTitle('বিবিধ খরচ '),
                      TextField(
                        controller: _miscExpenseDescriptionController,
                        decoration: InputDecoration(
                          labelText: 'খরচের বিবরণ',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _miscExpenseAmountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'পরিমাণ',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          prefixText: '৳ ',
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _handleAddMiscExpense,
                          icon: const Icon(Icons.add),
                          label: const Text('বিবিধ খরচ যোগ করুন'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (_members.isNotEmpty)
                        Text(
                          'প্রতি সদস্যের বর্তমান বিবিধ অংশ: ৳ ${(_totalMiscExpenses / _members.length).toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.deepPurple),
                        ),
                    ],
                  ),
                ),
              ),

              // Member Expenses Section
              Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionTitle('সদস্যদের খরচ'),
                      if (_members.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          value: _selectedExpenseMemberId.isEmpty &&
                                  _members.isNotEmpty
                              ? _members.first.id
                              : _selectedExpenseMemberId,
                          decoration: InputDecoration(
                            labelText: 'সদস্য নির্বাচন করুন',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          items: _members
                              .map((member) => DropdownMenuItem(
                                    value: member.id,
                                    child: Text(member.name),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedExpenseMemberId = value ?? '';
                            });
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                      TextField(
                        controller: _expenseDescriptionController,
                        decoration: InputDecoration(
                          labelText: 'খরচের বিবরণ',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _expenseAmountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'পরিমাণ',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          prefixText: '৳ ',
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _handleAddExpense,
                          icon: const Icon(Icons.add),
                          label: const Text('খরচ যোগ করুন'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      // Removed extra member expenses list; shown in combined list below
                    ],
                  ),
                ),
              ),

              // Members and Meals Management
              Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionTitle('সদস্য ও মিল ব্যবস্থাপনা'),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextField(
                                  controller: _newMemberNameController,
                                  decoration: InputDecoration(
                                    labelText: 'নতুন সদস্যের নাম',
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _initialDepositController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'প্রাথমিক জমা',
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    prefixText: '৳ ',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: _handleAddMember,
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('যোগ করুন'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (_members.isEmpty)
                        const Text('কোনো সদস্য যোগ করা হয়নি।')
                      else
                        ..._members.map((member) {
                          final memberMeals = _meals
                              .firstWhere((m) => m.memberId == member.id,
                                  orElse: () =>
                                      Meal(memberId: member.id, count: 0))
                              .count;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    member.name,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Edit initial deposit
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      color: Colors.teal),
                                  tooltip: 'প্রাথমিক জমা সম্পাদনা',
                                  onPressed: () =>
                                      _showEditInitialDepositDialog(member),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    border:
                                        Border.all(color: Colors.grey.shade400),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove),
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                                width: 32, height: 32),
                                        onPressed: () {
                                          setState(() {
                                            final int newCount = memberMeals > 0
                                                ? memberMeals - 1
                                                : 0;
                                            final idx = _meals.indexWhere(
                                                (m) => m.memberId == member.id);
                                            if (idx != -1) {
                                              _meals[idx].count = newCount;
                                            } else {
                                              _meals.add(Meal(
                                                  memberId: member.id,
                                                  count: newCount));
                                            }
                                          });
                                          _saveState();
                                        },
                                      ),
                                      SizedBox(
                                        width: 36,
                                        child: Center(
                                          child: Text(
                                            memberMeals.toString(),
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add),
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                                width: 32, height: 32),
                                        onPressed: () {
                                          setState(() {
                                            final int newCount =
                                                memberMeals + 1;
                                            final idx = _meals.indexWhere(
                                                (m) => m.memberId == member.id);
                                            if (idx != -1) {
                                              _meals[idx].count = newCount;
                                            } else {
                                              _meals.add(Meal(
                                                  memberId: member.id,
                                                  count: newCount));
                                            }
                                          });
                                          _saveState();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () async {
                                    final confirmed =
                                        await showDeleteConfirmationDialog(
                                      context: context,
                                      title: 'সদস্য ডিলিট',
                                      message:
                                          'আপনি কি নিশ্চিতভাবে এই সদস্যকে ডিলিট করতে চান? এই কাজটি পূর্বাবস্থায় ফেরানো যাবে না।',
                                      paperTitle: member.name,
                                      paperSubtitle:
                                          'প্রাথমিক জমা: ৳ ${member.initialDeposit.toStringAsFixed(2)}',
                                    );
                                    if (confirmed == true) {
                                      _handleDeleteMember(member.id);
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),

              // Deposit Form removed as per requirement

              // Members' Accounts Report
              Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: RepaintBoundary(
                  key: _finalReportKey,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_reportData.isNotEmpty)
                          _buildSectionTitle('ফাইনাল হিসাব'),
                        if (_reportData.isEmpty)
                          _emptyBox('কোনো সদস্য যোগ করা হয়নি।'),
                        if (_reportData.isEmpty)
                          _emptyBox('কোনো ডাটা পাওয়া যায়নি।')
                        else
                          ..._reportData.map((data) {
                            final key = _memberCardKeys.putIfAbsent(
                                data.memberId, () => GlobalKey());
                            return RepaintBoundary(
                              key: key,
                              child: Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            data.memberName,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.ios_share,
                                                color: Colors.blueGrey),
                                            tooltip: 'শেয়ার',
                                            onPressed: () => _shareKeyAsImage(
                                                key,
                                                '${data.memberName}_ হিসাব.png',
                                                text:
                                                    '${data.memberName} - ফাইনাল হিসাব'),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      _buildCalculationRow('প্রাথমিক জমা:',
                                          '${data.initialDeposit.toStringAsFixed(2)} টাকা',
                                          textColor: Colors.green),
                                      _buildCalculationRow('ব্যক্তিগত খরচ:',
                                          '${data.personalExpense.toStringAsFixed(2)} টাকা',
                                          textColor: Colors.red),
                                      _buildCalculationRow('মোট জমা:',
                                          '${data.totalContribution.toStringAsFixed(2)} টাকা'),
                                      _buildCalculationRow(
                                          'মোট মিল:', '${data.totalMeals} টি'),
                                      _buildCalculationRow('মিল রেট:',
                                          '${data.mealRate.toStringAsFixed(2)} টাকা'),
                                      _buildCalculationRow('মিল খরচ:',
                                          '${data.mealCost.toStringAsFixed(2)} টাকা',
                                          textColor: Colors.red),
                                      _buildCalculationRow('বিবিধ খরচের অংশ:',
                                          '${(_members.isNotEmpty ? (_totalMiscExpenses / _members.length) : 0).toStringAsFixed(2)} টাকা',
                                          textColor: Colors.red),
                                      _buildCalculationRow('মোট খরচ:',
                                          '${(data.mealCost + (_members.isNotEmpty ? (_totalMiscExpenses / _members.length) : 0)).toStringAsFixed(2)} টাকা',
                                          textColor: Colors.red),
                                      const Divider(),
                                      _buildCalculationRow('ব্যালেন্স:',
                                          '${(data.totalContribution - (data.mealCost + (_members.isNotEmpty ? (_totalMiscExpenses / _members.length) : 0))).toStringAsFixed(2)} টাকা',
                                          textColor: (data.totalContribution - (data.mealCost + (_members.isNotEmpty ? (_totalMiscExpenses / _members.length) : 0))) >= 0
                                              ? Colors.green
                                              : Colors.red),
                                      if ((data.totalContribution - (data.mealCost + (_members.isNotEmpty ? (_totalMiscExpenses / _members.length) : 0))) > 0)
                                        Text(
                                          '${data.memberName} ${(data.totalContribution - (data.mealCost + (_members.isNotEmpty ? (_totalMiscExpenses / _members.length) : 0))).toStringAsFixed(2)} টাকা ফেরত পাবেন',
                                          style: const TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold),
                                        )
                                      else if ((data.totalContribution - (data.mealCost + (_members.isNotEmpty ? (_totalMiscExpenses / _members.length) : 0))) < 0)
                                        Text(
                                          '${data.memberName} ${((data.mealCost + (_members.isNotEmpty ? (_totalMiscExpenses / _members.length) : 0)) - data.totalContribution).toStringAsFixed(2)} টাকা দিবেন',
                                          style: const TextStyle(
                                              color: Colors.red,
                                              fontWeight: FontWeight.bold),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
              ),

              // Expense List
              Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: RepaintBoundary(
                  key: _expenseListKey,
                  child: Container(
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildSectionTitle('খরচের তালিকা'),
                              IconButton(
                                icon: const Icon(Icons.ios_share,
                                    color: Colors.blueGrey),
                                tooltip: 'খরচের তালিকা শেয়ার করুন',
                                onPressed: () => _shareKeyAsImage(
                                    _expenseListKey, 'expenses_list.png',
                                    text: 'খরচের তালিকা'),
                              ),
                            ],
                          ),
                          if (_managerExpenses.isEmpty &&
                              _memberExpenses.isEmpty &&
                              _miscExpenses.isEmpty)
                            _emptyBox('কোনো খরচ যোগ করা হয়নি।')
                          else ...[
                            ..._managerExpenses.map((expense) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 4.0),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${expense.description} (ম্যানেজার)',
                                              style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.deepPurple),
                                              softWrap: true,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              DateFormat('dd MMM')
                                                  .format(expense.date),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                          '${expense.amount.toStringAsFixed(2)} টাকা',
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red)),
                                    ],
                                  ),
                                )),
                            ..._memberExpenses.map((expense) {
                              final memberName = _members
                                  .firstWhere((m) => m.id == expense.memberId,
                                      orElse: () =>
                                          Member(id: '', name: 'অজানা'))
                                  .name;
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4.0),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${expense.description} ($memberName)',
                                            style:
                                                const TextStyle(fontSize: 15),
                                            softWrap: true,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            DateFormat('dd MMM')
                                                .format(expense.date),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                        '${expense.amount.toStringAsFixed(2)} টাকা',
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red)),
                                  ],
                                ),
                              );
                            }),
                            ..._miscExpenses.map((expense) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 4.0),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${expense.description} (বিবিধ)',
                                              style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.deepPurple),
                                              softWrap: true,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              DateFormat('dd MMM')
                                                  .format(expense.date),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                          '${expense.amount.toStringAsFixed(2)} টাকা',
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.red)),
                                    ],
                                  ),
                                )),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ));
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.deepPurple,
        ),
      ),
    );
  }

  Widget _buildCalculationRow(String label, String value, {Color? textColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
          ),
        ],
      ),
    );
  }

  // UI helpers

  Widget _emptyBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, color: Colors.black54),
      ),
    );
  }
}
