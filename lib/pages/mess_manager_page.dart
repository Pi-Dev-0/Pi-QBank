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
import 'package:url_launcher/url_launcher.dart';

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

  final Map<String, bool> _isSectionExpanded = {
    'summary': true,
    'managerExpense': true,
    'miscExpense': true,
    'memberExpense': true,
    'memberManagement': true,
    'memberList': true,
    'finalReport': true,
    'expenseList': true,
  };
  final Map<String, bool> _isMemberReportExpanded = {};

  // Share keys
  final Map<String, GlobalKey> _memberCardKeys = {};
  final GlobalKey _summaryKey = GlobalKey();
  final GlobalKey _expenseListKey = GlobalKey();
  final GlobalKey _membersListKey = GlobalKey();

  // Selected member IDs
  String _selectedExpenseMemberId = '';
  String _myMemberId = '';
  String _managerPassword = '';
  bool _isManager = false;

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
  static const String _kSectionExpanded = 'mm_section_expanded';
  static const String _kMemberReportExpanded = 'mm_member_report_expanded';
  static const String _kIsManager = 'mm_is_manager';
  static const String _kMyMemberId = 'mm_my_member_id';
  static const String _kManagerPassword = 'mm_manager_password';
  static const String _kSetupCompleted = 'mm_setup_completed';

  // External sync endpoint
  String _appsScriptUrl = '';

  @override
  void initState() {
    super.initState();
    _loadState().then((_) {
      _checkSetup();
    });
  }

  Future<void> _checkSetup() async {
    final prefs = await SharedPreferences.getInstance();
    final hasCompleted = prefs.getBool(_kSetupCompleted) ?? false;
    if (!hasCompleted) {
      _showWelcomeDialog();
    }
  }

  Future<void> _showSyncOptions() async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              if (_isManager) ...[
                ListTile(
                  leading: const Icon(Icons.cloud_upload, color: Colors.green),
                  title: const Text('Google Sheets এ আপলোড করুন'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _syncToGoogleSheets();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.cloud_download, color: Colors.blue),
                  title: const Text('Google Sheets থেকে ডাউনলোড করুন'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _syncFromGoogleSheets();
                  },
                ),
                const Divider(),
              ],
              ListTile(
                leading: const Icon(Icons.link, color: Colors.orange),
                title: Text(_isManager
                    ? 'Apps Script URL পরিবর্তন করুন'
                    : 'সার্ভার URL পরিবর্তন করুন'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _showWelcomeDialog(startStep: 2);
                },
              ),
              ListTile(
                leading: const Icon(Icons.refresh, color: Colors.red),
                title: const Text('নতুন করে শুরু করুন (Start Over)'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _startOver();
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showMemberSelectionDialog() {
    if (!mounted || _members.isEmpty) return;

    // Members who already have an expense
    final expendedMemberIds = _memberExpenses.map((e) => e.memberId).toSet();

    // Filter out members who have already had an expense added
    final availableMembers = _members
        .where((member) => !expendedMemberIds.contains(member.id))
        .toList();

    if (availableMembers.isEmpty) {
      _showSnackBar('সকল সদস্যের খরচ যোগ করা হয়েছে।', Colors.blue);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        elevation: 8,
        title: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Text(
              'সদস্য নির্বাচন করুন',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
        ),
        content: SingleChildScrollView(
          child: ListBody(
            children: availableMembers.map((member) {
              return GestureDetector(
                onTap: () {
                  Navigator.of(dialogContext).maybePop();
                  if (!mounted) return;
                  setState(() {
                    _selectedExpenseMemberId = member.id;
                  });
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  decoration: BoxDecoration(
                    color: _selectedExpenseMemberId == member.id
                        ? Colors.blue.shade100
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _selectedExpenseMemberId == member.id
                          ? Colors.blue
                          : Colors.grey.shade300,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    member.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: _selectedExpenseMemberId == member.id
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: _selectedExpenseMemberId == member.id
                          ? Colors.blue.shade900
                          : Colors.black87,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _syncFromGoogleSheets() async {
    try {
      if (_appsScriptUrl.isEmpty) {
        await _showWelcomeDialog(startStep: 2);
        if (_appsScriptUrl.isEmpty) return;
      }

      final uri = Uri.parse(_appsScriptUrl).replace(queryParameters: {
        'action': 'pull',
      });

      _showSnackBar('ডাটা টানা হচ্ছে...', Colors.blueGrey);
      final resp = await http.get(uri, headers: const {
        'Content-Type': 'application/json',
      });

      if (!mounted) return;

      if (resp.statusCode == 200) {
        try {
          final data = jsonDecode(resp.body);
          if (data['success'] != true || data['payload'] == null) {
            final errorMessage =
                data['message'] as String? ?? 'Unknown error from script.';
            _showSnackBar(
                'Error syncing from sheet: $errorMessage', Colors.red);
            return;
          }
          final payload = data['payload'] as Map<String, dynamic>;

          setState(() {
            _members
              ..clear()
              ..addAll(((payload['members'] as List<dynamic>?) ?? [])
                  .map((e) => Member.fromMap(e as Map<String, dynamic>)));
            _meals
              ..clear()
              ..addAll(((payload['meals'] as List<dynamic>?) ?? [])
                  .map((e) => Meal.fromMap(e as Map<String, dynamic>)));
            _managerExpenses
              ..clear()
              ..addAll(((payload['managerExpenses'] as List<dynamic>?) ?? [])
                  .map((e) =>
                      ManagerExpense.fromMap(e as Map<String, dynamic>)));
            _miscExpenses
              ..clear()
              ..addAll(((payload['miscExpenses'] as List<dynamic>?) ?? [])
                  .map((e) => MiscExpense.fromMap(e as Map<String, dynamic>)));
            _memberExpenses
              ..clear()
              ..addAll(((payload['memberExpenses'] as List<dynamic>?) ?? [])
                  .map(
                      (e) => MemberExpense.fromMap(e as Map<String, dynamic>)));
            _deposits
              ..clear()
              ..addAll(((payload['deposits'] as List<dynamic>?) ?? [])
                  .map((e) => Deposit.fromMap(e as Map<String, dynamic>)));
          });

          await _saveState();
          _showSnackBar('শিট থেকে ডাটা ইম্পোর্ট সম্পন্ন।', Colors.green);
        } on FormatException catch (e) {
          _showSnackBar('Error parsing data from sheet: $e', Colors.red);
        }
      } else {
        _showSnackBar('Server error: ${resp.statusCode}', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Failed to sync from sheet: $e', Colors.red);
    }
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
      await prefs.setString(_kSectionExpanded, jsonEncode(_isSectionExpanded));
      await prefs.setString(
          _kMemberReportExpanded, jsonEncode(_isMemberReportExpanded));
      await prefs.setBool(_kIsManager, _isManager);
      await prefs.setString(_kMyMemberId, _myMemberId);
      await prefs.setString(_kManagerPassword, _managerPassword);
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

      final sectionExpandedStr = prefs.getString(_kSectionExpanded);
      if (sectionExpandedStr != null) {
        final decodedMap =
            jsonDecode(sectionExpandedStr) as Map<String, dynamic>;
        decodedMap.forEach((key, value) {
          if (_isSectionExpanded.containsKey(key)) {
            _isSectionExpanded[key] = value as bool;
          }
        });
      }

      final memberReportExpandedStr = prefs.getString(_kMemberReportExpanded);
      if (memberReportExpandedStr != null) {
        final decodedMap =
            jsonDecode(memberReportExpandedStr) as Map<String, dynamic>;
        decodedMap.forEach((key, value) {
          _isMemberReportExpanded[key] = value as bool;
        });
      }

      _isManager = prefs.getBool(_kIsManager) ?? false;
      _myMemberId = prefs.getString(_kMyMemberId) ?? '';
      _managerPassword = prefs.getString(_kManagerPassword) ?? '';

      if (mounted) setState(() {});
    } catch (e) {
      // If anything goes wrong, don't crash the UI; continue with empty state
    }
  }

  // Build export payload for Google Sheets sync
  Map<String, dynamic> _buildExportPayload() {
    final report = _reportData
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
              'bigMarketMealRate': r.bigMarketMealRate,
              'rawMarketMealRate': r.rawMarketMealRate,
            })
        .toList();

    // This is the raw data that allows the app to be fully restored.
    final rawData = {
      'members': _members.map((e) => e.toMap()).toList(),
      'meals': _meals.map((e) => e.toMap()).toList(),
      'managerExpenses': _managerExpenses.map((e) => e.toMap()).toList(),
            'miscExpenses': _miscExpenses.map((e) => e.toMap()).toList(),
      'memberExpenses': _memberExpenses.map((e) => e.toMap()).toList(),
      'deposits': _deposits.map((e) => e.toMap()).toList(),
    };

    return {
      'report': report,
      'rawData': rawData,
      'generatedAt': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _startOver() async {
    final confirmed = await showDeleteConfirmationDialog(
      context: context,
      title: 'রিসেট করুন',
      message:
          'আপনি কি নিশ্চিত যে আপনি সবকিছু রিসেট করে আবার শুরু করতে চান? আপনার বর্তমান সকল লোকাল ডাটা মুছে যাবে।',
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      for (String key in allKeys) {
        if (key.startsWith('mm_')) {
          await prefs.remove(key);
        }
      }
      setState(() {
        _members.clear();
        _meals.clear();
        _managerExpenses.clear();
        _miscExpenses.clear();
        _memberExpenses.clear();
        _deposits.clear();
        _appsScriptUrl = '';
        _managerPassword = '';
        _isManager = false;
        _myMemberId = '';
      });
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _showWelcomeDialog({int startStep = 1}) async {
    if (!mounted) return;

    final completed = await showDialog<bool>(
      context: context,
      barrierDismissible: startStep == 2, // Allow dismissing if just updating
      builder: (context) => _SetupDialogContent(
        initialIsManager: _isManager,
        initialUrl: _appsScriptUrl,
        initialPass: _managerPassword,
        initialStep: startStep,
        onComplete: (isManager, url, pass) {
          setState(() {
            _isManager = isManager;
            _appsScriptUrl = url;
            _managerPassword = pass;
          });
          _saveState().then((_) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(_kSetupCompleted, true);
            if (!isManager && _appsScriptUrl.isNotEmpty) {
              _syncFromGoogleSheets();
            }
          });
          _showSnackBar('সেটিংস আপডেট করা হয়েছে!', Colors.green);
        },
      ),
    );

    if (completed != true && startStep == 1 && mounted) {
      Navigator.pop(context); // Close the page if initial setup cancelled
    }
  }

  Future<void> _syncToGoogleSheets() async {
    try {
      if (_appsScriptUrl.isEmpty) {
        await _showWelcomeDialog(startStep: 2);
        if (_appsScriptUrl.isEmpty) return;
      }

      final uri = Uri.parse(_appsScriptUrl);
      final payload = {
        'action': 'sync',
        'password': _managerPassword,
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

      if (!mounted) return;

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
        _showSnackBar('ডাটা সফলভাবে সিঙ্ক হয়েছে।', Colors.green);
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
        _meals.add(Meal(memberId: newMember.id, count: 0.0));
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

  void _handleDeleteExpense(dynamic expense) {
    setState(() {
      if (expense is ManagerExpense) {
        _managerExpenses.removeWhere((e) => e.id == expense.id);
      } else if (expense is MemberExpense) {
        _memberExpenses.removeWhere((e) => e.id == expense.id);
      } else if (expense is MiscExpense) {
        _miscExpenses.removeWhere((e) => e.id == expense.id);
      }
    });
    _saveState();
    _showSnackBar('খরচ মুছে ফেলা হয়েছে।', Colors.orange);
  }

  Future<void> _showEditExpenseDialog(dynamic expense) async {
    final descriptionController =
        TextEditingController(text: expense.description);
    final amountController =
        TextEditingController(text: expense.amount.toStringAsFixed(2));
    String? selectedMemberId =
        (expense is MemberExpense) ? expense.memberId : null;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('খরচ সম্পাদনা',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (expense is MemberExpense)
                    DropdownButtonFormField<String>(
                      value: selectedMemberId,
                      items: _members.map((member) {
                        return DropdownMenuItem(
                          value: member.id,
                          child: Text(member.name),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            selectedMemberId = value;
                          });
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'সদস্য',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descriptionController,
                    decoration: InputDecoration(
                      labelText: 'বিবরণ',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'পরিমাণ',
                      prefixText: '৳ ',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('বাতিল'),
            ),
            ElevatedButton(
              onPressed: () {
                final amount = _parseAmount(amountController.text);
                final description = descriptionController.text.trim();

                if (amount == null || amount <= 0 || description.isEmpty) {
                  _showSnackBar('সঠিক পরিমাণ এবং বিবরণ দিন।', Colors.red);
                  return;
                }

                setState(() {
                  if (expense is ManagerExpense) {
                    final index =
                        _managerExpenses.indexWhere((e) => e.id == expense.id);
                    if (index != -1) {
                      _managerExpenses[index] = ManagerExpense(
                        id: expense.id,
                        amount: amount,
                        description: description,
                        date: expense.date,
                      );
                    }
                  } else if (expense is MemberExpense) {
                    final index =
                        _memberExpenses.indexWhere((e) => e.id == expense.id);
                    if (index != -1) {
                      _memberExpenses[index] = MemberExpense(
                        id: expense.id,
                        memberId: selectedMemberId!,
                        amount: amount,
                        description: description,
                        date: expense.date,
                      );
                    }
                  } else if (expense is MiscExpense) {
                    final index =
                        _miscExpenses.indexWhere((e) => e.id == expense.id);
                    if (index != -1) {
                      _miscExpenses[index] = MiscExpense(
                        id: expense.id,
                        amount: amount,
                        description: description,
                        date: expense.date,
                      );
                    }
                  }
                });
                _saveState();
                Navigator.of(context).pop();
                _showSnackBar('খরচ হালনাগাদ করা হয়েছে।', Colors.green);
              },
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('সেভ'),
            ),
          ],
        );
      },
    );
  }

  void _showExpenseActionDialog(dynamic expense) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(expense.description,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ElevatedButton.icon(
                icon: const Icon(Icons.edit, color: Colors.white),
                label: const Text('সম্পাদনা',
                    style: TextStyle(color: Colors.white)),
                onPressed: () {
                  Navigator.of(context).pop();
                  _showEditExpenseDialog(expense);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.delete, color: Colors.red),
                label: const Text('ডিলিট', style: TextStyle(color: Colors.red)),
                onPressed: () async {
                  Navigator.of(context).pop();
                  final confirmed = await showDeleteConfirmationDialog(
                    context: context,
                    title: 'খরচ ডিলিট',
                    message: 'আপনি কি নিশ্চিতভাবে এই খরচটি ডিলিট করতে চান?',
                    paperTitle: expense.description,
                    paperSubtitle:
                        'পরিমাণ: ৳ ${expense.amount.toStringAsFixed(2)}',
                  );
                  if (confirmed == true) {
                    _handleDeleteExpense(expense);
                  }
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
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

  // Edit meal count for a member
  Future<void> _showEditMealDialog(Member member, double currentMeals) async {
    final controller = TextEditingController(
        text: currentMeals == 0 ? '' : currentMeals.toString());
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${member.name}-এর মিল সংখ্যা',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('সরাসরি মিল সংখ্যা ইনপুট দিন:'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'মিল সংখ্যা',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.restaurant_menu),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('বাতিল'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = _parseAmount(controller.text);
              if (val != null && val >= 0) {
                Navigator.pop(context, val);
              } else if (controller.text.isEmpty) {
                Navigator.pop(context, 0.0);
              } else {
                _showSnackBar('সঠিক সংখ্যা দিন', Colors.red);
              }
            },
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('সেভ'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        final idx = _meals.indexWhere((m) => m.memberId == member.id);
        if (idx != -1) {
          _meals[idx].count = result;
        } else {
          _meals.add(Meal(memberId: member.id, count: result));
        }
      });
      _saveState();
      _showSnackBar('${member.name}-এর মিল আপডেট করা হয়েছে।', Colors.green);
    }
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
  double get _totalMeals => _meals.fold(0.0, (sum, m) => sum + m.count);
  double get _mealRate => _totalMeals > 0 ? _totalExpenses / _totalMeals : 0.0;

  // New meal rate calculations
  double get _rawMarketMealRate {
    // Calculated without manager expenses and miscellaneous expenses
    final expensesWithoutManagerAndMisc = _totalMemberExpenses;
    return _totalMeals > 0 ? expensesWithoutManagerAndMisc / _totalMeals : 0.0;
  }

  double get _bigMarketMealRate {
    // Calculated by all expenses (manager, member, and miscellaneous)
    return _totalMeals > 0 ? _totalManagerExpenses / _totalMeals : 0.0;
  }

  List<ReportData> get _reportData {
    return _members.map((member) {
      final memberMeals = _meals
          .firstWhere((m) => m.memberId == member.id,
              orElse: () => Meal(memberId: member.id, count: 0.0))
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
        bigMarketMealRate: _bigMarketMealRate,
        rawMarketMealRate: _rawMarketMealRate,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: CustomAppBar(
          title: _isManager ? 'মেস ম্যানেজার' : 'মেস মেম্বার',
          actions: [
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: _showSyncOptions,
              tooltip: 'সিঙ্ক অপশন',
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_isManager) ...[
                _buildMemberSelector(),
                const SizedBox(height: 16),
                if (_myMemberId.isNotEmpty) _buildMyStatusCard(),
                const SizedBox(height: 16),
              ],
              _buildCollapsibleSection(
                title: 'মেস এর হিসাব',
                sectionKey: 'summary',
                shareKey: _summaryKey,
                shareFileName: 'summary_report.png',
                shareText: 'মেস এর হিসাব',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    _buildCalculationRow('মোট জমা (ম্যানেজার):',
                        '${_members.fold(0.0, (sum, m) => sum + m.initialDeposit).toStringAsFixed(2)} টাকা',
                        textColor: Colors.green),
                    _buildCalculationRow('বড় বাজার খরচ:',
                        '${_totalManagerExpenses.toStringAsFixed(2)} টাকা',
                        textColor: Colors.red),
                    _buildCalculationRow('সদস্যদের খরচ:',
                        '${_totalMemberExpenses.toStringAsFixed(2)} টাকা',
                        textColor: Colors.red),
                    _buildCalculationRow(
                        'মোট খরচ:', '${_totalExpenses.toStringAsFixed(2)} টাকা',
                        textColor: Colors.red),
                    _buildCalculationRow('মোট বিবিধ খরচ:',
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
                    _buildCalculationRow('মোট মিল সংখ্যা:',
                        '${_totalMeals.toStringAsFixed(1)} টি'),
                    _buildCalculationRow('বড় বাজার মিল রেট:',
                        '${_bigMarketMealRate.toStringAsFixed(2)} টাকা'),
                    _buildCalculationRow('কাঁচা বাজার মিল রেট:',
                        '${_rawMarketMealRate.toStringAsFixed(2)} টাকা'),
                    _buildCalculationRow(
                        'গড় মিল রেট:', '${_mealRate.toStringAsFixed(2)} টাকা'),
                  ],
                ),
              ),
              if (_isManager) ...[
                _buildCollapsibleSection(
                  title: 'বড় বাজার খরচ',
                  sectionKey: 'managerExpense',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
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
                      const SizedBox(height: 10),
                      Text(
                        'মোট ম্যানেজারের খরচ: ৳ ${_totalManagerExpenses.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, color: Colors.green),
                      ),
                    ],
                  ),
                ),
                _buildCollapsibleSection(
                  title: 'বিবিধ খরচ ',
                  sectionKey: 'miscExpense',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
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
                _buildCollapsibleSection(
                  title: 'সদস্যদের খরচ',
                  sectionKey: 'memberExpense',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      if (_members.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.3),
                                spreadRadius: 2,
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                spreadRadius: 0,
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: InkWell(
                            onTap: _showMemberSelectionDialog,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  const Text(
                                    'সদস্য নির্বাচন করুন:',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        _members
                                            .firstWhere(
                                                (m) =>
                                                    m.id ==
                                                    _selectedExpenseMemberId,
                                                orElse: () => Member(
                                                    id: '',
                                                    name: 'নির্বাচন করুন'))
                                            .name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.arrow_drop_down),
                                ],
                              ),
                            ),
                          ),
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
                      const SizedBox(height: 6),
                      Text(
                        'মোট সদস্যদের খরচ: ৳ ${_totalMemberExpenses.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, color: Colors.green),
                      ),
                    ],
                  ),
                ),
                _buildCollapsibleSection(
                  title: 'সদস্য ও মিল ব্যবস্থাপনা',
                  sectionKey: 'memberManagement',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
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
                      const Text(
                        'নিচের বক্সে সদস্যদের তালিকা ও মিল দেখুন।',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
              _buildCollapsibleSection(
                title: 'সদস্যদের তালিকা ও মিল',
                sectionKey: 'memberList',
                shareKey: _membersListKey,
                shareFileName: 'members_list.png',
                shareText: 'সদস্যদের তালিকা ও মিল',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    if (_members.isEmpty)
                      _emptyBox('কোনো সদস্য যোগ করা হয়নি।')
                    else
                      ..._members.map((member) {
                        final memberMeals = _meals
                            .firstWhere((m) => m.memberId == member.id,
                                orElse: () =>
                                    Meal(memberId: member.id, count: 0.0))
                            .count;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                            color: (!_isManager && member.id == _myMemberId)
                                ? Colors.blue.shade50
                                : Colors.white,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      member.name,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'প্রাথমিক জমা: ৳ ${member.initialDeposit.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_isManager) ...[
                                const SizedBox(width: 8),
                                PopupMenuButton<String>(
                                  tooltip: 'অ্যাকশন',
                                  onSelected: (value) async {
                                    if (value == 'edit_meals') {
                                      _showEditMealDialog(member, memberMeals);
                                    } else if (value == 'edit') {
                                      _showEditInitialDepositDialog(member);
                                    } else if (value == 'delete') {
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
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'edit_meals',
                                      child: Row(
                                        children: [
                                          Icon(Icons.restaurant_menu,
                                              color: Colors.deepPurple),
                                          SizedBox(width: 8),
                                          Text('মিল সংখ্যা সম্পাদনা'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit, color: Colors.teal),
                                          SizedBox(width: 8),
                                          Text('প্রাথমিক জমা সম্পাদনা'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('সদস্য ডিলিট'),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              Container(
                                decoration: BoxDecoration(
                                  border:
                                      Border.all(color: Colors.grey.shade400),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isManager)
                                      IconButton(
                                        icon: const Icon(Icons.remove),
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                                width: 32, height: 32),
                                        onPressed: () {
                                          setState(() {
                                            double newCount = memberMeals - 0.5;
                                            if (newCount < 0) newCount = 0.0;
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
                                      width: 48,
                                      child: Center(
                                        child: Text(
                                          memberMeals.toStringAsFixed(1),
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.deepPurple),
                                        ),
                                      ),
                                    ),
                                    if (_isManager) ...[
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(Icons.add),
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints:
                                            const BoxConstraints.tightFor(
                                                width: 32, height: 32),
                                        onPressed: () {
                                          setState(() {
                                            final double newCount =
                                                memberMeals + 0.5;
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
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
              _buildCollapsibleSection(
                title: 'ফাইনাল হিসাব',
                sectionKey: 'finalReport',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_reportData.isNotEmpty) ...[
                      const SizedBox(height: 6),
                    ],
                    if (_reportData.isEmpty)
                      _emptyBox('কোনো ডাটা পাওয়া যায়নি।')
                    else
                      ..._reportData.map((data) {
                        final key = _memberCardKeys.putIfAbsent(
                            data.memberId, () => GlobalKey());
                        final bool isMemberReportExpanded =
                            _isMemberReportExpanded[data.memberId] ?? true;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 8,
                          shadowColor: Colors.black26,
                          color: (!_isManager && data.memberId == _myMemberId)
                              ? Colors.blue.shade50
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _isMemberReportExpanded[data.memberId] =
                                        !isMemberReportExpanded;
                                  });
                                  _saveState();
                                },
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 8, 4, 8),
                                  child: Row(
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
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
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
                                          Icon(isMemberReportExpanded
                                              ? Icons.expand_less
                                              : Icons.expand_more),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (isMemberReportExpanded)
                                RepaintBoundary(
                                  key: key,
                                  child: Container(
                                    color: Colors
                                        .white, // Ensures shared image has a background
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 0, 12, 12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 8),
                                          _buildCalculationRow('প্রাথমিক জমা:',
                                              '${data.initialDeposit.toStringAsFixed(2)} টাকা',
                                              textColor: Colors.green),
                                          _buildCalculationRow('ব্যক্তিগত খরচ:',
                                              '${data.personalExpense.toStringAsFixed(2)} টাকা',
                                              textColor: Colors.red),
                                          _buildCalculationRow('মোট জমা:',
                                              '${data.totalContribution.toStringAsFixed(2)} টাকা'),
                                          _buildCalculationRow('মোট মিল:',
                                              '${data.totalMeals.toStringAsFixed(1)} টি'),
                                          _buildCalculationRow('মিল রেট:',
                                              '${data.mealRate.toStringAsFixed(2)} টাকা'),
                                          _buildCalculationRow('মিল খরচ:',
                                              '${data.mealCost.toStringAsFixed(2)} টাকা',
                                              textColor: Colors.red),
                                          _buildCalculationRow(
                                              'বিবিধ খরচের অংশ:',
                                              '${(_members.isNotEmpty ? (_totalMiscExpenses / _members.length) : 0).toStringAsFixed(2)} টাকা',
                                              textColor: Colors.red),
                                          _buildCalculationRow('মোট খরচ:',
                                              '${(data.mealCost + (_members.isNotEmpty ? (_totalMiscExpenses / _members.length) : 0)).toStringAsFixed(2)} টাকা',
                                              textColor: Colors.red),
                                          const Divider(),
                                          _buildCalculationRow('ব্যালেন্স:',
                                              '${(data.totalContribution - (data.mealCost + (_members.isNotEmpty ? (_totalMiscExpenses / _members.length) : 0))).toStringAsFixed(2)} টাকা',
                                              textColor: (data.totalContribution -
                                                          (data.mealCost +
                                                              (_members
                                                                      .isNotEmpty
                                                                  ? (_totalMiscExpenses /
                                                                      _members
                                                                          .length)
                                                                  : 0))) >=
                                                      0
                                                  ? Colors.green
                                                  : Colors.red),
                                          if ((data.totalContribution -
                                                  (data.mealCost +
                                                      (_members.isNotEmpty
                                                          ? (_totalMiscExpenses /
                                                              _members.length)
                                                          : 0))) >
                                              0)
                                            Text(
                                              '${data.memberName} ${(data.totalContribution - (data.mealCost + (_members.isNotEmpty ? (_totalMiscExpenses / _members.length) : 0))).toStringAsFixed(2)} টাকা ফেরত পাবেন',
                                              style: const TextStyle(
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.bold),
                                            )
                                          else if ((data.totalContribution -
                                                  (data.mealCost +
                                                      (_members.isNotEmpty
                                                          ? (_totalMiscExpenses /
                                                              _members.length)
                                                          : 0))) <
                                              0)
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
                                ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
              _buildCollapsibleSection(
                title: 'খরচের তালিকা',
                sectionKey: 'expenseList',
                shareKey: _expenseListKey,
                shareFileName: 'expenses_list.png',
                shareText: 'খরচের তালিকা',
                child: () {
                  final allExpenses = <dynamic>[
                    ..._managerExpenses,
                    ..._memberExpenses,
                    ..._miscExpenses,
                  ];

                  // Sort by date, newest first
                  allExpenses.sort((a, b) => b.date.compareTo(a.date));

                  if (allExpenses.isEmpty) {
                    return _emptyBox('কোনো খরচ যোগ করা হয়নি।');
                  }

                  return Column(
                    children: allExpenses.map((expense) {
                      String title;
                      Color titleColor = Colors.black87;

                      if (expense is ManagerExpense) {
                        title = '${expense.description} (ম্যানেজার)';
                        titleColor = Colors.blue.shade800;
                      } else if (expense is MemberExpense) {
                        final memberName = _members
                            .firstWhere((m) => m.id == expense.memberId,
                                orElse: () => Member(id: '', name: 'অজানা'))
                            .name;
                        title = '${expense.description} ($memberName)';
                      } else if (expense is MiscExpense) {
                        title = '${expense.description} (বিবিধ)';
                        titleColor = Colors.purple.shade700;
                      } else {
                        title = 'অজানা খরচ';
                      }

                      return GestureDetector(
                        onLongPress: () {
                          _showExpenseActionDialog(expense);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: titleColor),
                                      softWrap: true,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      DateFormat('dd MMM, yyyy')
                                          .format(expense.date),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text('${expense.amount.toStringAsFixed(2)} টাকা',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                }(),
              ),
            ],
          ),
        ));
  }

  Widget _buildCollapsibleSection({
    required String title,
    required String sectionKey,
    required Widget child,
    GlobalKey? shareKey,
    String? shareFileName,
    String? shareText,
  }) {
    final bool isExpanded = _isSectionExpanded[sectionKey] ?? true;
    return Card(
      elevation: 12,
      shadowColor: Colors.black38,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isSectionExpanded[sectionKey] = !isExpanded;
              });
              _saveState();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionTitle(title),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (shareKey != null)
                        IconButton(
                          icon: const Icon(Icons.ios_share,
                              color: Colors.blueGrey),
                          tooltip: shareText ?? 'Share',
                          onPressed: () => _shareKeyAsImage(
                            shareKey,
                            shareFileName ?? 'shared_image.png',
                            text: shareText,
                          ),
                        ),
                      IconButton(
                        icon: Icon(
                            isExpanded ? Icons.expand_less : Icons.expand_more),
                        tooltip: isExpanded ? 'Collapse' : 'Expand',
                        onPressed: () {
                          setState(() {
                            _isSectionExpanded[sectionKey] = !isExpanded;
                          });
                          _saveState();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            RepaintBoundary(
              key: shareKey,
              child: Container(
                color: Colors.white, // Ensures shared image has a background
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: child,
                ),
              ),
            ),
        ],
      ),
    );
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

  Widget _buildMemberSelector() {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.70,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'আপনি কে? নির্বাচন করুন:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  //align the dropdown button to the center
                  alignment: Alignment.center,
                  value: _myMemberId.isEmpty ? null : _myMemberId,
                  hint: const Text('সদস্য নির্বাচন করুন'),
                  isExpanded: true,
                  items: _members.map((member) {
                    return DropdownMenuItem<String>(
                      //align member name to the center
                      alignment: Alignment.center,
                      value: member.id,
                      child: Text(member.name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _myMemberId = value ?? '';
                    });
                    _saveState();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyStatusCard() {
    final myData = _reportData.firstWhere(
      (d) => d.memberId == _myMemberId,
      orElse: () => ReportData(
        memberId: '',
        memberName: 'অজানা',
        totalMeals: 0,
        initialDeposit: 0,
        personalExpense: 0,
        totalContribution: 0,
        mealCost: 0,
        balance: 0,
        mealRate: 0,
        bigMarketMealRate: 0,
        rawMarketMealRate: 0,
      ),
    );

    if (myData.memberId.isEmpty) return const SizedBox.shrink();

    final double totalCost = myData.mealCost +
        (_members.isNotEmpty ? (_totalMiscExpenses / _members.length) : 0);
    final double balance = myData.totalContribution - totalCost;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade600, Colors.blue.shade400],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              'স্বাগতম, ${myData.memberName}!',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const Divider(color: Colors.white24, height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusItem('বর্তমান জমা',
                    '${myData.totalContribution.toStringAsFixed(0)} ৳'),
                _buildStatusItem(
                    'মোট খরচ', '${totalCost.toStringAsFixed(0)} ৳'),
                _buildStatusItem('ব্যালেন্স', '${balance.toStringAsFixed(0)} ৳',
                    color: balance >= 0
                        ? Colors.greenAccent
                        : Colors.orangeAccent),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusItem(
                    'মোট মিল', myData.totalMeals.toStringAsFixed(1)),
                _buildStatusItem(
                    'মিল রেট', '${myData.mealRate.toStringAsFixed(2)} ৳'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(String label, String value,
      {Color color = Colors.white}) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _emptyBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
        ),
      ),
    );
  }
}

class _SetupDialogContent extends StatefulWidget {
  final Function(bool isManager, String url, String pass) onComplete;
  final bool? initialIsManager;
  final String? initialUrl;
  final String? initialPass;
  final int? initialStep;

  const _SetupDialogContent({
    required this.onComplete,
    this.initialIsManager,
    this.initialUrl,
    this.initialPass,
    this.initialStep,
  });

  @override
  State<_SetupDialogContent> createState() => _SetupDialogContentState();
}

class _SetupDialogContentState extends State<_SetupDialogContent> {
  late TextEditingController urlController;
  late TextEditingController passController;
  late bool isManager;
  late bool isOnline;
  late int step;

  @override
  void initState() {
    super.initState();
    urlController = TextEditingController(text: widget.initialUrl ?? '');
    passController = TextEditingController(text: widget.initialPass ?? '');
    isManager = widget.initialIsManager ?? true;
    isOnline = true; // Default to online, especially for updates
    step = widget.initialStep ?? 1;
  }

  @override
  void dispose() {
    urlController.dispose();
    passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 5,
            )
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade400, Colors.blue.shade700],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.settings_suggest,
                    color: Colors.white, size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                step == 1 ? 'মেস ম্যানেজার সেটআপ' : 'কানেকশন সেটিংস',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
              ),
              const SizedBox(height: 8),
              Text(
                step == 1
                    ? 'আপনার ভূমিকা এবং ব্যবহারের ধরণ নির্বাচন করুন'
                    : 'আপনার অনলাইন ব্যাকএন্ড কনফিগার করুন',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),

              if (step == 1) ...[
                // Role selection
                _buildSetupHeader('আপনার ভূমিকা নির্বাচন করুন:'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: _buildSelectionCard(
                      'ম্যানেজার',
                      'হিসাব ব্যবস্থাপনা ও ডাটা সিঙ্ক',
                      Icons.admin_panel_settings,
                      isManager,
                      () => setState(() => isManager = true),
                    )),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _buildSelectionCard(
                      'মেম্বার',
                      'শুধুমাত্র নিজের হিসাব দেখা',
                      Icons.person,
                      !isManager,
                      () {
                        setState(() {
                          isManager = false;
                          isOnline = true; // Members must be online
                        });
                      },
                    )),
                  ],
                ),
                const SizedBox(height: 24),
                // Mode selection
                _buildSetupHeader('কানেকশন মোড:'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: _buildSelectionCard(
                      'অনলাইন',
                      'ডাটা গুগল শিটের সাথে যুক্ত',
                      Icons.cloud_done,
                      isOnline,
                      () => setState(() => isOnline = true),
                    )),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _buildSelectionCard(
                      'অফলাইন',
                      'শুধুমাত্র ফোনের মেমোরিতে',
                      Icons.cloud_off,
                      !isOnline,
                      () => setState(() => isOnline = false),
                      isDisabled: !isManager,
                    )),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  !isManager
                      ? '* সদস্যদের ডাটা লোড করতে অনলাইন মোড প্রয়োজন'
                      : (isOnline
                          ? '* ডাটা গুগল শিটে সেভ হবে (সুপারিশকৃত)'
                          : '* ডাটা শুধুমাত্র ফোনে সেভ হবে'),
                  style: TextStyle(
                      fontSize: 12,
                      color: !isManager
                          ? Colors.orange.shade800
                          : Colors.grey.shade600),
                ),
              ] else ...[
                // Step 2: Online Details
                TextField(
                  controller: urlController,
                  decoration: InputDecoration(
                    labelText: 'Apps Script Web App URL',
                    hintText: 'https://...',
                    prefixIcon: const Icon(Icons.link),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
                if (isManager) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: passController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'ম্যানেজার পাসওয়ার্ড',
                      hintText: 'নিরাপত্তার জন্য পাসওয়ার্ড দিন',
                      prefixIcon: const Icon(Icons.lock),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        final url = Uri.parse(
                            'https://pi-mathematics.blogspot.com/p/mess-manager-online-connection-setup.html');
                        await launchUrl(url,
                            mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(Icons.lightbulb_outline, size: 16),
                      label: const Text(
                        'Online Setup Guide',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.deepPurple,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isManager
                              ? 'পাসওয়ার্ডটি আপনার গুগল স্ক্রিপ্ট কোডের সাথে মিল থাকতে হবে।'
                              : 'মেম্বার হিসেবে শুধুমাত্র ডাটা দেখার জন্য URL টি প্রয়োজন।',
                          style: TextStyle(
                              fontSize: 12, color: Colors.blue.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        if (step == 2) {
                          if (widget.initialStep == 2) {
                            Navigator.pop(context);
                          } else {
                            setState(() => step = 1);
                          }
                        } else {
                          // Step 1: Cancel and exit
                          Navigator.pop(context);
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(step == 2 && widget.initialStep != 2
                          ? 'পিছনে'
                          : (step == 2 ? 'বন্ধ করুন' : 'ফিরে যান')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (step == 1) {
                          if (isOnline) {
                            setState(() => step = 2);
                          } else {
                            // Finish Offline
                            widget.onComplete(isManager, '', '');
                            Navigator.pop(context, true);
                          }
                        } else {
                          // Finalize Online
                          final url = urlController.text.trim();
                          final pass = passController.text.trim();
                          if (url.isEmpty || (isManager && pass.isEmpty)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('URL এবং পাসওয়ার্ড দিন।'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          widget.onComplete(isManager, url, pass);
                          Navigator.pop(context, true);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        step == 1 && isOnline ? 'পরবর্তী ধাপ' : 'শুরু করুন',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSetupHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style:
            const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
      ),
    );
  }

  Widget _buildSelectionCard(String title, String subtitle, IconData icon,
      bool isSelected, VoidCallback onTap,
      {bool isDisabled = false}) {
    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.blue.shade50
              : (isDisabled ? Colors.grey.shade50 : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Colors.blue
                : (isDisabled ? Colors.grey.shade200 : Colors.grey.shade200),
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: Colors.blue.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4))
                ]
              : [],
        ),
        child: Column(
          children: [
            Icon(icon,
                color: isSelected
                    ? Colors.blue
                    : (isDisabled ? Colors.grey.shade300 : Colors.grey),
                size: 32),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? Colors.blue
                        : (isDisabled
                            ? Colors.grey.shade400
                            : Colors.black87))),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 10,
                  color:
                      isDisabled ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
