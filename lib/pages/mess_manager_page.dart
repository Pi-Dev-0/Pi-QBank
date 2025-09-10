import 'package:flutter/material.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pi_qbank/models/mess_manager_models.dart'; // Import new models

class MessManagerPage extends StatefulWidget {
  const MessManagerPage({super.key});

  @override
  State<MessManagerPage> createState() => _MessManagerPageState();
}

class _MessManagerPageState extends State<MessManagerPage> {
  // State variables
  List<Member> _members = [];
  List<Meal> _meals = [];
  List<Deposit> _deposits = [];
  List<Expense> _expenses = [];

  // Controllers for input fields
  final TextEditingController _newMemberNameController = TextEditingController();
  final TextEditingController _depositAmountController = TextEditingController();
  final TextEditingController _expenseAmountController = TextEditingController();
  final TextEditingController _expenseDescriptionController = TextEditingController();

  String _selectedDepositMemberId = '';
  String _selectedExpenseMemberId = '';

  @override
  void dispose() {
    _newMemberNameController.dispose();
    _depositAmountController.dispose();
    _expenseAmountController.dispose();
    _expenseDescriptionController.dispose();
    super.dispose();
  }

  // Handlers
  void _handleAddMember() {
    if (_newMemberNameController.text.trim().isNotEmpty) {
      setState(() {
        final newMember = Member(id: DateTime.now().millisecondsSinceEpoch.toString(), name: _newMemberNameController.text.trim());
        _members.add(newMember);
        _meals.add(Meal(memberId: newMember.id, count: 0));
        _newMemberNameController.clear();
      });
      _showSnackBar('সদস্য সফলভাবে যোগ করা হয়েছে। (Member added successfully.)', Colors.green);
    } else {
      _showSnackBar('সদস্যের নাম খালি রাখা যাবে না। (Member name cannot be empty.)', Colors.red);
    }
  }

  void _handleDeleteMember(String memberId) {
    setState(() {
      _members.removeWhere((m) => m.id == memberId);
      _meals.removeWhere((m) => m.memberId == memberId);
      _deposits.removeWhere((d) => d.memberId == memberId);
      _expenses.removeWhere((e) => e.memberId == memberId);
    });
    _showSnackBar('সদস্য সফলভাবে মুছে ফেলা হয়েছে। (Member deleted successfully.)', Colors.orange);
  }

  void _handleMealChange(String memberId, String countText) {
    int count = int.tryParse(countText) ?? 0;
    if (count < 0) count = 0;

    setState(() {
      final index = _meals.indexWhere((m) => m.memberId == memberId);
      if (index != -1) {
        _meals[index].count = count;
      } else {
        _meals.add(Meal(memberId: memberId, count: count));
      }
    });
  }

  void _handleAddDeposit() {
    final amount = double.tryParse(_depositAmountController.text);
    if (_selectedDepositMemberId.isNotEmpty && amount != null && amount > 0) {
      setState(() {
        _deposits.add(Deposit(id: DateTime.now().millisecondsSinceEpoch.toString(), memberId: _selectedDepositMemberId, amount: amount));
        _depositAmountController.clear();
        _selectedDepositMemberId = '';
      });
      _showSnackBar('জমা সফলভাবে যোগ করা হয়েছে। (Deposit added successfully.)', Colors.green);
    } else {
      _showSnackBar('সদস্য নির্বাচন করুন এবং সঠিক পরিমাণ দিন। (Select a member and enter a valid amount.)', Colors.red);
    }
  }

  void _handleAddExpense() {
    final amount = double.tryParse(_expenseAmountController.text);
    if (_selectedExpenseMemberId.isNotEmpty && amount != null && amount > 0 && _expenseDescriptionController.text.trim().isNotEmpty) {
      setState(() {
        _expenses.add(Expense(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          memberId: _selectedExpenseMemberId,
          amount: amount,
          description: _expenseDescriptionController.text.trim(),
        ));
        _expenseAmountController.clear();
        _expenseDescriptionController.clear();
        _selectedExpenseMemberId = '';
      });
      _showSnackBar('খরচ সফলভাবে যোগ করা হয়েছে। (Expense added successfully.)', Colors.green);
    } else {
      _showSnackBar('খরচকারী নির্বাচন করুন, সঠিক পরিমাণ এবং বিবরণ দিন। (Select an expense creator, enter a valid amount and description.)', Colors.red);
    }
  }

  // Show SnackBar
  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Calculations (equivalent to useMemo)
  double get _totalDeposit => _deposits.fold(0.0, (sum, d) => sum + d.amount);
  double get _totalExpense => _expenses.fold(0.0, (sum, e) => sum + e.amount);
  int get _totalMeals => _meals.fold(0, (sum, m) => sum + m.count);
  double get _mealRate => _totalMeals > 0 ? _totalExpense / _totalMeals : 0.0;

  List<ReportData> get _reportData {
    return _members.map((member) {
      final memberMeals = _meals.firstWhere((m) => m.memberId == member.id, orElse: () => Meal(memberId: member.id, count: 0)).count;
      final memberDeposit = _deposits
          .where((d) => d.memberId == member.id)
          .fold(0.0, (sum, d) => sum + d.amount);
      final personalExpense = _expenses
          .where((e) => e.memberId == member.id)
          .fold(0.0, (sum, e) => sum + e.amount);

      final totalContribution = memberDeposit + personalExpense;
      final mealCost = memberMeals * _mealRate;
      final balance = totalContribution - mealCost;

      return ReportData(
        memberId: member.id,
        memberName: member.name,
        totalMeals: memberMeals,
        totalDeposit: memberDeposit,
        personalExpense: personalExpense,
        totalContribution: totalContribution,
        mealCost: mealCost,
        balance: balance,
      );
    }).toList();
  }

  // Generate PDF report
  Future<void> _generatePdfReport() async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Center(
              child: pw.Text(
                'মেস হিসাব নিকাশ (Mess Calculation Report)',
                style:
                    pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text(
              'মেস এর হিসাব (Mess Calculation)',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            _buildPdfCalculationRow(
                'মোট মিল সংখ্যা (Total Meals):', _totalMeals.toString()),
            _buildPdfCalculationRow('মোট খরচ (Total Expenses):',
                _totalExpense.toStringAsFixed(2)),
            _buildPdfCalculationRow('মোট জমা (Total Deposits):',
                _totalDeposit.toStringAsFixed(2)),
            _buildPdfCalculationRow(
                'মিল রেট (Meal Rate):', _mealRate.toStringAsFixed(2)),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text(
              'সদস্যদের হিসাব (Members\' Accounts)',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            if (_reportData.isEmpty)
              pw.Text('কোনো সদস্য যোগ করা হয়নি। (No members added yet.)')
            else
              ..._reportData.map((data) {
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'নাম (Name): ${data.memberName}',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 14),
                    ),
                    pw.Text(
                        'মোট জমা (Total Deposit): ${data.totalDeposit.toStringAsFixed(2)} টাকা'),
                    pw.Text('মোট মিল (Total Meals): ${data.totalMeals} টি'),
                    pw.Text(
                        'ব্যক্তিগত খরচ (Personal Expense): ${data.personalExpense.toStringAsFixed(2)} টাকা'),
                    pw.Text(
                        'মিল খরচ (Meal Cost): ${data.mealCost.toStringAsFixed(2)} টাকা'),
                    pw.Text(
                      'অবশিষ্ট (Balance): ${data.balance.toStringAsFixed(2)} টাকা',
                      style: pw.TextStyle(
                        color: data.balance >= 0
                            ? PdfColors.green
                            : PdfColors.red,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 10),
                  ],
                );
              }),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text(
              'খরচের তালিকা (Expense List)',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            if (_expenses.isEmpty)
              pw.Text(
                  'কোনো খরচ যোগ করা হয়নি। (No expenses added yet.)')
            else
              ..._expenses.map((expense) {
                final memberName = _members.firstWhere((m) => m.id == expense.memberId, orElse: () => Member(id: '', name: 'Unknown')).name;
                return pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('${expense.description} (${memberName})'),
                    pw.Text('${expense.amount.toStringAsFixed(2)} টাকা'),
                  ],
                );
              }),
          ];
        },
      ),
    );

    await Printing.sharePdf(
        bytes: await pdf.save(), filename: 'mess_report.pdf');
  }

  pw.Widget _buildPdfCalculationRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.0),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.normal),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'মেস ম্যানেজার (Mess Manager)',
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _generatePdfReport,
            tooltip: 'Print Report',
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
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('মেস এর হিসাব (Mess Calculation)'),
                    _buildCalculationRow('মোট জমা (Total Deposits):',
                        '${_totalDeposit.toStringAsFixed(2)} টাকা'),
                    _buildCalculationRow('মোট খরচ (Total Expenses):',
                        '${_totalExpense.toStringAsFixed(2)} টাকা'),
                    _buildCalculationRow('মোট মিল সংখ্যা (Total Meals):',
                        '${_totalMeals} টি'),
                    _buildCalculationRow('মিল রেট (Meal Rate):',
                        '${_mealRate.toStringAsFixed(2)} টাকা'),
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
                    _buildSectionTitle('সদস্য ও মিল ব্যবস্থাপনা (Members & Meal Management)'),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newMemberNameController,
                            decoration: InputDecoration(
                              labelText: 'নতুন সদস্যের নাম (New Member Name)',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
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
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (_members.isEmpty)
                      const Text('কোনো সদস্য যোগ করা হয়নি। (No members added yet.)')
                    else
                      ..._members.map((member) {
                        final memberMeals = _meals.firstWhere((m) => m.memberId == member.id, orElse: () => Meal(memberId: member.id, count: 0)).count;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  member.name,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: TextField(
                                  controller: TextEditingController(text: memberMeals.toString()),
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.right,
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  ),
                                  onChanged: (value) => _handleMealChange(member.id, value),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _handleDeleteMember(member.id),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),

            // Deposit Form
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
                    _buildSectionTitle('টাকা জমা করুন (Add Deposit)'),
                    DropdownButtonFormField<String>(
                      value: _selectedDepositMemberId.isEmpty && _members.isNotEmpty
                          ? _members.first.id
                          : _selectedDepositMemberId,
                      decoration: InputDecoration(
                        labelText: 'সদস্য নির্বাচন করুন (Select Member)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('সদস্য নির্বাচন করুন')),
                        ..._members.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedDepositMemberId = value ?? '';
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _depositAmountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'টাকার পরিমাণ (Amount)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _handleAddDeposit,
                        icon: const Icon(Icons.attach_money),
                        label: const Text('জমা করুন (Deposit)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Expense Form
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
                    _buildSectionTitle('খরচ যোগ করুন (Add Expense)'),
                    DropdownButtonFormField<String>(
                      value: _selectedExpenseMemberId.isEmpty && _members.isNotEmpty
                          ? _members.first.id
                          : _selectedExpenseMemberId,
                      decoration: InputDecoration(
                        labelText: 'খরচকারী নির্বাচন করুন (Select Payer)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('খরচকারী নির্বাচন করুন')),
                        ..._members.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedExpenseMemberId = value ?? '';
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _expenseAmountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'টাকার পরিমাণ (Amount)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _expenseDescriptionController,
                      decoration: InputDecoration(
                        labelText: 'খরচের বিবরণ (Expense Description)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _handleAddExpense,
                        icon: const Icon(Icons.shopping_cart_checkout),
                        label: const Text('খরচ যোগ করুন (Add Expense)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Members' Accounts Report
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
                    _buildSectionTitle('সদস্যদের হিসাব (Members\' Accounts)'),
                    if (_reportData.isEmpty)
                      const Text(
                          'কোনো সদস্য যোগ করা হয়নি। (No members added yet.)')
                    else
                      ..._reportData.map((data) {
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8.0),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'নাম (Name): ${data.memberName}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.deepPurple),
                                ),
                                const Divider(),
                                _buildCalculationRow('মোট জমা (Total Deposit):',
                                    '${data.totalDeposit.toStringAsFixed(2)} টাকা'),
                                _buildCalculationRow('মোট মিল (Total Meals):',
                                    '${data.totalMeals} টি'),
                                _buildCalculationRow(
                                    'ব্যক্তিগত খরচ (Personal Expense):',
                                    '${data.personalExpense.toStringAsFixed(2)} টাকা'),
                                _buildCalculationRow('মিল খরচ (Meal Cost):',
                                    '${data.mealCost.toStringAsFixed(2)} টাকা'),
                                const Divider(),
                                _buildCalculationRow(
                                  'অবশিষ্ট (Balance):',
                                  '${data.balance.toStringAsFixed(2)} টাকা',
                                  textColor: data.balance >= 0
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),

            // Expense List
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
                    _buildSectionTitle(
                        'খরচের তালিকা (Expense List)'),
                    if (_expenses.isEmpty)
                      const Text(
                          'কোনো খরচ যোগ করা হয়নি। (No expenses added yet.)')
                    else
                      ..._expenses.map((expense) {
                        final memberName = _members.firstWhere((m) => m.id == expense.memberId, orElse: () => Member(id: '', name: 'Unknown')).name;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${expense.description} (${memberName})',
                                  style: const TextStyle(fontSize: 15)),
                              Text('${expense.amount.toStringAsFixed(2)} টাকা',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],
        ),
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
}
