// lib/models/mess_manager_models.dart

class Member {
  final String id;
  String name;
  double initialDeposit; // Money given to manager at start of month

  Member({required this.id, required this.name, this.initialDeposit = 0.0});

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'initialDeposit': initialDeposit,
      };

  factory Member.fromMap(Map<String, dynamic> map) => Member(
        id: map['id'] as String,
        name: map['name'] as String,
        initialDeposit: (map['initialDeposit'] as num?)?.toDouble() ?? 0.0,
      );
}

class Meal {
  final String memberId;
  int count;

  Meal({required this.memberId, required this.count});

  Map<String, dynamic> toMap() => {
        'memberId': memberId,
        'count': count,
      };

  factory Meal.fromMap(Map<String, dynamic> map) => Meal(
        memberId: map['memberId'] as String,
        count: (map['count'] as num).toInt(),
      );
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

  Map<String, dynamic> toMap() => {
        'id': id,
        'amount': amount,
        'description': description,
        'date': date.toIso8601String(),
      };

  factory ManagerExpense.fromMap(Map<String, dynamic> map) => ManagerExpense(
        id: map['id'] as String,
        amount: (map['amount'] as num).toDouble(),
        description: map['description'] as String,
        date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      );
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

  Map<String, dynamic> toMap() => {
        'id': id,
        'memberId': memberId,
        'amount': amount,
        'date': date.toIso8601String(),
      };

  factory Deposit.fromMap(Map<String, dynamic> map) => Deposit(
        id: map['id'] as String,
        memberId: map['memberId'] as String,
        amount: (map['amount'] as num).toDouble(),
        date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      );
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

  Map<String, dynamic> toMap() => {
        'id': id,
        'memberId': memberId,
        'amount': amount,
        'description': description,
        'date': date.toIso8601String(),
      };

  factory MemberExpense.fromMap(Map<String, dynamic> map) => MemberExpense(
        id: map['id'] as String,
        memberId: map['memberId'] as String,
        amount: (map['amount'] as num).toDouble(),
        description: map['description'] as String,
        date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      );
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
