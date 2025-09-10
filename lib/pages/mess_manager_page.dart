import 'package:flutter/material.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pi_qbank/models/mess_manager_models.dart';
import 'package:intl/intl.dart';

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
  final List<MemberExpense> _memberExpenses = [];
  final List<Deposit> _deposits = [];

  // Selected member IDs
  String _selectedExpenseMemberId = '';

  // Controllers
  final TextEditingController _expenseAmountController =
      TextEditingController();
  final TextEditingController _expenseDescriptionController =
      TextEditingController();

  // Getters
  double get _totalExpense =>
      _managerExpenses.fold(0.0, (sum, e) => sum + e.amount) +
      _memberExpenses.fold(0.0, (sum, e) => sum + e.amount);

  // Controllers for input fields
  final TextEditingController _newMemberNameController =
      TextEditingController();
  final TextEditingController _initialDepositController =
      TextEditingController();
  final TextEditingController _managerExpenseAmountController =
      TextEditingController();
  final TextEditingController _managerExpenseDescriptionController =
      TextEditingController();
  final TextEditingController _memberExpenseAmountController =
      TextEditingController();
  final TextEditingController _memberExpenseDescriptionController =
      TextEditingController();

  @override
  void dispose() {
    _newMemberNameController.dispose();
    _initialDepositController.dispose();
    _managerExpenseAmountController.dispose();
    _managerExpenseDescriptionController.dispose();
    _memberExpenseAmountController.dispose();
    _memberExpenseDescriptionController.dispose();
    super.dispose();
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
    _showSnackBar('সদস্য মুছে ফেলা হয়েছে।', Colors.orange);
  }

  void _handleAddManagerExpense() {
    final amount = double.tryParse(_managerExpenseAmountController.text);
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
      _showSnackBar('ম্যানেজারের খরচ যোগ করা হয়েছে।', Colors.green);
    } else {
      _showSnackBar('সঠিক পরিমাণ এবং বিবরণ দিন।', Colors.red);
    }
  }

  void _handleAddMemberExpense() {
    final amount = double.tryParse(_memberExpenseAmountController.text);
    final description = _memberExpenseDescriptionController.text.trim();

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
        _memberExpenseAmountController.clear();
        _memberExpenseDescriptionController.clear();
        _selectedExpenseMemberId = '';
      });
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Edit initial deposit for a member
  Future<void> _showEditInitialDepositDialog(Member member) async {
    final controller = TextEditingController(
        text: member.initialDeposit.toStringAsFixed(2));
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('প্রাথমিক জমা সম্পাদনা'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'প্রাথমিক জমা',
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
                Navigator.of(context).pop();
                _showSnackBar('প্রাথমিক জমা হালনাগাদ করা হয়েছে।', Colors.green);
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
  double get _totalExpenses => _totalManagerExpenses + _totalMemberExpenses;
  double get _totalDeposit => _deposits.fold(0.0, (sum, d) => sum + d.amount);
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
                'মেস হিসাব নিকাশ',
                style:
                    pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text(
              'মেস এর হিসাব',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            _buildPdfCalculationRow('মোট মিল সংখ্যা:', _totalMeals.toString()),
            _buildPdfCalculationRowColored(
                'মোট খরচ:', _totalExpense.toStringAsFixed(2),
                color: PdfColors.red),
            _buildPdfCalculationRowColored(
                'মোট জমা:', _totalDeposit.toStringAsFixed(2),
                color: PdfColors.green),
            _buildPdfCalculationRow('মিল রেট:', _mealRate.toStringAsFixed(2)),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text(
              'সদস্যদের হিসাব',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            if (_reportData.isEmpty)
              pw.Text('কোনো সদস্য যোগ করা হয়নি।')
            else
              ..._reportData.map((data) {
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'নাম: ${data.memberName}',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 14),
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('মোট জমা:'),
                        pw.Text(
                            '${data.initialDeposit.toStringAsFixed(2)} টাকা',
                            style: pw.TextStyle(color: PdfColors.green)),
                      ],
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('মোট মিল:'),
                        pw.Text('${data.totalMeals} টি'),
                      ],
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('ব্যক্তিগত খরচ:'),
                        pw.Text(
                            '${data.personalExpense.toStringAsFixed(2)} টাকা',
                            style: pw.TextStyle(color: PdfColors.red)),
                      ],
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('মিল খরচ:'),
                        pw.Text('${data.mealCost.toStringAsFixed(2)} টাকা',
                            style: pw.TextStyle(color: PdfColors.red)),
                      ],
                    ),
                    pw.Text(
                      'অবশিষ্ট: ${data.balance.toStringAsFixed(2)} টাকা',
                      style: pw.TextStyle(
                        color:
                            data.balance >= 0 ? PdfColors.green : PdfColors.red,
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
              'খরচের তালিকা',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            if (_managerExpenses.isEmpty && _memberExpenses.isEmpty)
              pw.Text('কোনো খরচ যোগ করা হয়নি।')
            else
              ..._managerExpenses.map((expense) {
                return pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('${expense.description} (ম্যানেজার)'),
                    pw.Text('${expense.amount.toStringAsFixed(2)} টাকা'),
                  ],
                );
              }).toList()
                ..addAll(_memberExpenses.map((expense) {
                  final memberName = _members
                      .firstWhere((m) => m.id == expense.memberId,
                          orElse: () => Member(id: '', name: 'অজানা'))
                      .name;
                  return pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('${expense.description} ($memberName)'),
                      pw.Text('${expense.amount.toStringAsFixed(2)} টাকা'),
                    ],
                  );
                })),
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

  pw.Widget _buildPdfCalculationRowColored(String label, String value,
      {PdfColor? color}) {
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
            style: pw.TextStyle(
                fontSize: 14, fontWeight: pw.FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: CustomAppBar(
          title: 'মেস ম্যানেজার',
          actions: [
            IconButton(
              icon: const Icon(Icons.print),
              onPressed: _generatePdfReport,
              tooltip: 'রিপোর্ট প্রিন্ট করুন',
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
                      _buildSectionTitle('মেস এর হিসাব'),
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
                      _buildCalculationRow(
                          'মোট মিল সংখ্যা:', '$_totalMeals টি'),
                      _buildCalculationRow(
                          'মিল রেট:', '${_mealRate.toStringAsFixed(2)} টাকা'),
                    ],
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
                      if (_managerExpenses.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _fullWidthLabel('খরচের তালিকা'),
                        ..._managerExpenses.map((expense) => ListTile(
                              title: Text(expense.description),
                              subtitle: Text(DateFormat('dd MMM yyyy')
                                  .format(expense.date)),
                              trailing: Text(
                                  '৳${expense.amount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red)),
                            )),
                      ],
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
                          value: _selectedExpenseMemberId.isEmpty
                              ? null
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
                      if (_memberExpenses.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text('খরচের তালিকা:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        ..._memberExpenses.map((expense) {
                          final member = _members.firstWhere(
                              (m) => m.id == expense.memberId,
                              orElse: () => Member(id: '', name: 'অজানা'));
                          return ListTile(
                            title: Text(expense.description),
                            subtitle: Text(
                                '${member.name} • ${DateFormat('dd MMM yyyy').format(expense.date)}'),
                            trailing: Text(
                                '৳${expense.amount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red)),
                          );
                        }),
                      ],
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
                                  icon: const Icon(Icons.edit, color: Colors.teal),
                                  tooltip: 'প্রাথমিক জমা সম্পাদনা',
                                  onPressed: () => _showEditInitialDepositDialog(member),
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
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () =>
                                      _handleDeleteMember(member.id),
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
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    data.memberName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
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
                                  _buildCalculationRow('মোট খরচ:',
                                      '${data.mealCost.toStringAsFixed(2)} টাকা',
                                      textColor: Colors.red),
                                  const Divider(),
                                  _buildCalculationRow('ব্যালেন্স:',
                                      '${data.balance.toStringAsFixed(2)} টাকা',
                                      textColor: data.balance >= 0
                                          ? Colors.green
                                          : Colors.red),
                                  if (data.balance > 0)
                                    Text(
                                      '${data.memberName} ${data.balance.toStringAsFixed(2)} টাকা ফেরত পাবেন',
                                      style: const TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold),
                                    )
                                  else if (data.balance < 0)
                                    Text(
                                      '${data.memberName} ${(-data.balance).toStringAsFixed(2)} টাকা দিবেন',
                                      style: const TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold),
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
                      _fullWidthLabel('খরচের তালিকা'),
                      if (_managerExpenses.isEmpty && _memberExpenses.isEmpty)
                        _emptyBox('কোনো খরচ যোগ করা হয়নি।')
                      else ...[
                        ..._managerExpenses.map((expense) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('${expense.description} (ম্যানেজার)',
                                      style: const TextStyle(fontSize: 15)),
                                  Text(
                                      '${expense.amount.toStringAsFixed(2)} টাকা',
                                      style: const TextStyle(fontSize: 15)),
                                ],
                              ),
                            )),
                        ..._memberExpenses.map((expense) {
                          final memberName = _members
                              .firstWhere((m) => m.id == expense.memberId,
                                  orElse: () => Member(id: '', name: 'অজানা'))
                              .name;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${expense.description} ($memberName)',
                                    style: const TextStyle(fontSize: 15)),
                                Text(
                                    '${expense.amount.toStringAsFixed(2)} টাকা',
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
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
  Widget _fullWidthLabel(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

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
