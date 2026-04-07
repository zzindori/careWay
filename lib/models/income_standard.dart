class IncomeStandard {
  final int year;
  final int householdSize;
  final int medianIncome;
  final int pct32;
  final int pct40;
  final int pct47;
  final int pct48;
  final int pct50;
  final int pct100;
  final int pct120;
  final int pct150;

  const IncomeStandard({
    required this.year,
    required this.householdSize,
    required this.medianIncome,
    required this.pct32,
    required this.pct40,
    required this.pct47,
    required this.pct48,
    required this.pct50,
    required this.pct100,
    required this.pct120,
    required this.pct150,
  });

  factory IncomeStandard.fromJson(Map<String, dynamic> j) => IncomeStandard(
    year: j['year'] as int,
    householdSize: j['household_size'] as int,
    medianIncome: j['median_income'] as int,
    pct32: j['pct_32'] as int,
    pct40: j['pct_40'] as int,
    pct47: j['pct_47'] as int,
    pct48: j['pct_48'] as int,
    pct50: j['pct_50'] as int,
    pct100: j['pct_100'] as int,
    pct120: j['pct_120'] as int,
    pct150: j['pct_150'] as int,
  );
}
