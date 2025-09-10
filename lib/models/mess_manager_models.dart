// lib/models/mess_manager_models.dart

class Member {
  final String id;
  String name;

  Member({required this.id, required this.name});
}

class Meal {
  final String memberId;
  int count;

  Meal({required this.memberId, required this.count});
}

class Deposit {
  final String id;
  final String memberId;
  final double amount;

  Deposit({required this.id, required this.memberId, required this.amount});
}

class Expense {
  final String id;
  final String memberId;
  final double amount;
  final String description;

  Expense({required this.id, required this.memberId, required this.amount, required this.description});
}

class ReportData {
  final String memberId;
  final String memberName;
  final int totalMeals;
  final double totalDeposit;
  final double personalExpense;
  final double totalContribution;
  final double mealCost;
  final double balance;

  ReportData({
    required this.memberId,
    required this.memberName,
    required this.totalMeals,
    required this.totalDeposit,
    required this.personalExpense,
    required this.totalContribution,
    required this.mealCost,
    required this.balance,
  });
}
