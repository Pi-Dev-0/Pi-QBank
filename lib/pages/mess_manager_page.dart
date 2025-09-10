import 'package:flutter/material.dart';
import 'package:pi_qbank/widgets/custom_app_bar.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class MessManagerPage extends StatefulWidget {
  const MessManagerPage({super.key});

  @override
  State<MessManagerPage> createState() => _MessManagerPageState();
}

class _MessManagerPageState extends State<MessManagerPage> {
  // Basic mess details
  DateTime? _startDate;
  DateTime? _endDate;
  int _managerContribution = 0;
  final List<Map<String, dynamic>> _members = []; // {name: String, contribution: int, meals: int, personal_expense: int}
  final List<Map<String, dynamic>> _commonExpenses = []; // {item: String, amount: int}

  // Controllers for input fields
  final TextEditingController _memberNameController = TextEditingController();
  final TextEditingController _memberContributionController = TextEditingController();
  final TextEditingController _memberMealsController = TextEditingController();
  final TextEditingController _memberPersonalExpenseController = TextEditingController();
  final TextEditingController _commonExpenseItemController = TextEditingController();
  final TextEditingController _commonExpenseAmountController = TextEditingController();
  final TextEditingController _managerContributionInputController = TextEditingController();

  @override
  void dispose() {
    _memberNameController.dispose();
    _memberContributionController.dispose();
    _memberMealsController.dispose();
    _memberPersonalExpenseController.dispose();
    _commonExpenseItemController.dispose();
    _commonExpenseAmountController.dispose();
    _managerContributionInputController.dispose();
    super.dispose();
  }

  // Date picker for start and end dates
  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != (isStartDate ? _startDate : _endDate)) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  // Add a new member
  void _addMember() {
    if (_memberNameController.text.isNotEmpty) {
      setState(() {
        _members.add({
          'name': _memberNameController.text,
          'contribution': int.tryParse(_memberContributionController.text) ?? 0,
          'meals': int.tryParse(_memberMealsController.text) ?? 0,
          'personal_expense': int.tryParse(_memberPersonalExpenseController.text) ?? 0,
        });
        _memberNameController.clear();
        _memberContributionController.clear();
        _memberMealsController.clear();
        _memberPersonalExpenseController.clear();
      });
    }
  }

  // Add a common expense
  void _addCommonExpense() {
    if (_commonExpenseItemController.text.isNotEmpty && _commonExpenseAmountController.text.isNotEmpty) {
      setState(() {
        _commonExpenses.add({
          'item': _commonExpenseItemController.text,
          'amount': int.parse(_commonExpenseAmountController.text),
        });
        _commonExpenseItemController.clear();
        _commonExpenseAmountController.clear();
      });
    }
  }

  // Calculate total meals
  int _getTotalMeals() {
    return _members.fold(0, (sum, member) => sum + (member['meals'] as int));
  }

  // Calculate total common expenses
  int _getTotalCommonExpenses() {
    return _commonExpenses.fold(0, (sum, expense) => sum + (expense['amount'] as int));
  }

  // Calculate total contributions
  int _getTotalContributions() {
    return _members.fold(0, (sum, member) => sum + (member['contribution'] as int)) + _managerContribution;
  }

  // Calculate meal rate
  double _getMealRate() {
    final totalCommonExpenses = _getTotalCommonExpenses();
    final totalMeals = _getTotalMeals();
    return totalMeals > 0 ? totalCommonExpenses / totalMeals : 0.0;
  }

  // Calculate individual member's balance
  int _getMemberBalance(Map<String, dynamic> member) {
    final mealCost = (member['meals'] as int) * _getMealRate();
    final totalExpense = mealCost + (member['personal_expense'] as int);
    return (member['contribution'] as int) - totalExpense.round();
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
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'মেস এর সময়কাল (Mess Duration): ${_startDate?.toLocal().toString().split(' ')[0] ?? 'N/A'} - ${_endDate?.toLocal().toString().split(' ')[0] ?? 'N/A'}',
              style: const pw.TextStyle(fontSize: 16),
            ),
            pw.Text(
              'ম্যানেজারের জমা (Manager\'s Contribution): $_managerContribution টাকা',
              style: const pw.TextStyle(fontSize: 16),
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text(
              'মেস এর হিসাব (Mess Calculation)',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            _buildPdfCalculationRow('মোট মিল সংখ্যা (Total Meals):', _getTotalMeals().toString()),
            _buildPdfCalculationRow('মোট সাধারণ খরচ (Total Common Expenses):', _getTotalCommonExpenses().toString()),
            _buildPdfCalculationRow('মোট জমা (Total Contributions):', _getTotalContributions().toString()),
            _buildPdfCalculationRow('মিল রেট (Meal Rate):', _getMealRate().toStringAsFixed(2)),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text(
              'সদস্যদের হিসাব (Members\' Accounts)',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            if (_members.isEmpty)
              pw.Text('কোনো সদস্য যোগ করা হয়নি। (No members added yet.)')
            else
              ..._members.map((member) {
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'নাম (Name): ${member['name']}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
                    ),
                    pw.Text('জমা (Contribution): ${member['contribution']} টাকা'),
                    pw.Text('মিল সংখ্যা (Meals): ${member['meals']} টি'),
                    pw.Text('ব্যক্তিগত বাজার খরচ (Personal Market Expense): ${member['personal_expense']} টাকা'),
                    pw.Text('মিল খরচ (Meal Cost): ${((member['meals'] as int) * _getMealRate()).toStringAsFixed(2)} টাকা'),
                    pw.Text(
                      'অবশিষ্ট (Balance): ${_getMemberBalance(member)} টাকা',
                      style: pw.TextStyle(
                        color: _getMemberBalance(member) >= 0 ? PdfColors.green : PdfColors.red,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 10),
                  ],
                );
              }).toList(),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Text(
              'সাধারণ খরচের তালিকা (Common Expense List)',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            if (_commonExpenses.isEmpty)
              pw.Text('কোনো সাধারণ খরচ যোগ করা হয়নি। (No common expenses added yet.)')
            else
              ..._commonExpenses.map((expense) {
                return pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(expense['item']),
                    pw.Text('${expense['amount']} টাকা'),
                  ],
                );
              }).toList(),
          ];
        },
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'mess_report.pdf');
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
            Card(
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('মেস এর সময়কাল (Mess Duration)'),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _selectDate(context, true),
                            icon: const Icon(Icons.calendar_today),
                            label: Text(_startDate == null
                                ? 'শুরুর তারিখ (Start Date)'
                                : 'শুরুর তারিখ: ${_startDate!.toLocal().toString().split(' ')[0]}'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _selectDate(context, false),
                            icon: const Icon(Icons.calendar_today),
                            label: Text(_endDate == null
                                ? 'শেষের তারিখ (End Date)'
                                : 'শেষের তারিখ: ${_endDate!.toLocal().toString().split(' ')[0]}'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            Card(
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('ম্যানেজারের জমা (Manager\'s Contribution)'),
                    TextField(
                      controller: _managerContributionInputController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'ম্যানেজারের জমা (Manager\'s Contribution)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () {
                            setState(() {
                              _managerContribution = int.tryParse(_managerContributionInputController.text) ?? 0;
                            });
                            FocusScope.of(context).unfocus(); // Dismiss keyboard
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Card(
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('সদস্য যোগ করুন (Add Member)'),
                    TextField(
                      controller: _memberNameController,
                      decoration: InputDecoration(
                        labelText: 'সদস্যের নাম (Member Name)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _memberContributionController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'সদস্যের জমা (Member Contribution)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _memberMealsController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'মোট মিল সংখ্যা (Total Meals)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _memberPersonalExpenseController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'ব্যক্তিগত বাজার খরচ (Personal Market Expense)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _addMember,
                        icon: const Icon(Icons.person_add),
                        label: const Text('সদস্য যোগ করুন (Add Member)'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Card(
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('সাধারণ খরচ যোগ করুন (Add Common Expense)'),
                    TextField(
                      controller: _commonExpenseItemController,
                      decoration: InputDecoration(
                        labelText: 'খরচের বিবরণ (Expense Description)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _commonExpenseAmountController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'পরিমাণ (Amount)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _addCommonExpense,
                        icon: const Icon(Icons.add_shopping_cart),
                        label: const Text('খরচ যোগ করুন (Add Expense)'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Card(
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('মেস এর হিসাব (Mess Calculation)'),
                    _buildCalculationRow('মোট মিল সংখ্যা (Total Meals):', _getTotalMeals().toString()),
                    _buildCalculationRow('মোট সাধারণ খরচ (Total Common Expenses):', _getTotalCommonExpenses().toString()),
                    _buildCalculationRow('মোট জমা (Total Contributions):', _getTotalContributions().toString()),
                    _buildCalculationRow('মিল রেট (Meal Rate):', _getMealRate().toStringAsFixed(2)),
                  ],
                ),
              ),
            ),

            Card(
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('সদস্যদের হিসাব (Members\' Accounts)'),
                    if (_members.isEmpty)
                      const Text('কোনো সদস্য যোগ করা হয়নি। (No members added yet.)')
                    else
                      ..._members.map((member) {
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8.0),
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'নাম (Name): ${member['name']}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple),
                                ),
                                const Divider(),
                                _buildCalculationRow('জমা (Contribution):', '${member['contribution']} টাকা'),
                                _buildCalculationRow('মিল সংখ্যা (Meals):', '${member['meals']} টি'),
                                _buildCalculationRow('ব্যক্তিগত বাজার খরচ (Personal Market Expense):', '${member['personal_expense']} টাকা'),
                                _buildCalculationRow('মিল খরচ (Meal Cost):', '${((member['meals'] as int) * _getMealRate()).toStringAsFixed(2)} টাকা'),
                                const Divider(),
                                _buildCalculationRow(
                                  'অবশিষ্ট (Balance):',
                                  '${_getMemberBalance(member)} টাকা',
                                  textColor: _getMemberBalance(member) >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                  ],
                ),
              ),
            ),

            Card(
              elevation: 4,
              margin: const EdgeInsets.only(bottom: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('সাধারণ খরচের তালিকা (Common Expense List)'),
                    if (_commonExpenses.isEmpty)
                      const Text('কোনো সাধারণ খরচ যোগ করা হয়নি। (No common expenses added yet.)')
                    else
                      ..._commonExpenses.map((expense) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(expense['item'], style: const TextStyle(fontSize: 15)),
                              Text('${expense['amount']} টাকা', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        );
                      }).toList(),
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
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
          ),
        ],
      ),
    );
  }
}
