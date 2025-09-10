// lib/models/mess_manager_models.dart

class Member {
  final String id;
  String name;
  double initialDeposit; // Money given to manager at start of month

  Member({required this.id, required this.name, this.initialDeposit = 0.0});
}

class Meal {
  final String memberId;
  int count;

  Meal({required this.memberId, required this.count});
}

class ManagerExpense {
  final String id;
  final double amount;
  final String description;
  final DateTime date;

  ManagerExpense({
    required this.id,
    required this.amount,
    required this.description,
    DateTime? date,
  }) : date = date ?? DateTime.now();
}

class Deposit {
  final String id;
  final String memberId;
  final double amount;
  final DateTime date;

  Deposit({
    required this.id,
    required this.memberId,
    required this.amount,
    DateTime? date,
  }) : date = date ?? DateTime.now();
}

class MemberExpense {
  final String id;
  final String memberId;
  final double amount;
  final String description;
  final DateTime date;

  MemberExpense({
    required this.id,
    required this.memberId,
    required this.amount,
    required this.description,
    DateTime? date,
  }) : date = date ?? DateTime.now();
}

class ReportData {
  final String memberId;
  final String memberName;
  final int totalMeals;
  final double initialDeposit; // Money given to manager
  final double personalExpense; // Money spent on market purchases
  final double mealCost; // Total cost of meals consumed (meals * mealRate)
  final double totalContribution; // initialDeposit + personalExpense
  final double balance; // totalContribution - mealCost
  final double mealRate;

  ReportData({
    required this.memberId,
    required this.memberName,
    required this.totalMeals,
    required this.initialDeposit,
    required this.personalExpense,
    required this.mealCost,
    required this.totalContribution,
    required this.balance,
    required this.mealRate,
  });
}
