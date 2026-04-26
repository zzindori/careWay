class LtcGradeBenefit {
  final int grade;
  final String gradeName;
  final int monthlyLimit;
  final List<String> services;
  final double copayRate;
  final double copayRateReduced;
  final int year;

  const LtcGradeBenefit({
    required this.grade,
    required this.gradeName,
    required this.monthlyLimit,
    required this.services,
    required this.copayRate,
    required this.copayRateReduced,
    required this.year,
  });

  factory LtcGradeBenefit.fromJson(Map<String, dynamic> j) => LtcGradeBenefit(
    grade: j['grade'] as int,
    gradeName: j['grade_name'] as String,
    monthlyLimit: j['monthly_limit'] as int,
    services: List<String>.from(j['services'] as List),
    copayRate: (j['copay_rate'] as num).toDouble(),
    copayRateReduced: (j['copay_rate_reduced'] as num).toDouble(),
    year: j['year'] as int,
  );

  String get monthlyLimitLabel {
    final man = (monthlyLimit / 10000).floor();
    final rest = monthlyLimit % 10000;
    return rest == 0 ? '월 최대 $man만원' : '월 최대 $man만 $rest원';
  }
}
