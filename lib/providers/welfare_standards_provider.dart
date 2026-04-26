import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ltc_grade_benefit.dart';
import '../models/income_standard.dart';

class WelfareStandardsProvider extends ChangeNotifier {
  final _client = Supabase.instance.client;

  Map<int, LtcGradeBenefit> _ltcBenefits = {};
  List<IncomeStandard> _incomeStandards = [];
  bool _isLoaded = false;

  Map<int, LtcGradeBenefit> get ltcBenefits => _ltcBenefits;
  List<IncomeStandard> get incomeStandards => _incomeStandards;
  bool get isLoaded => _isLoaded;

  // ─────────────────────────────────────────────
  // 소득분위(1~10) → 기준중위소득 % 매핑
  // 1인가구 2025년 기준 월 소득 상한 (원)
  // ─────────────────────────────────────────────
  static const _levelPct = {
    1: '30%',  2: '40%',  3: '47%',  4: '50%',
    5: '60%',  6: '70%',  7: '80%',  8: '100%',
    9: '120%', 10: '초과',
  };

  Future<void> load() async {
    if (_isLoaded) return;
    try {
      final ltcRes = await _client.from('ltc_grade_benefits').select();
      _ltcBenefits = {
        for (final r in ltcRes as List)
          (r['grade'] as int): LtcGradeBenefit.fromJson(r)
      };

      final incRes = await _client
          .from('income_standards')
          .select()
          .order('household_size');
      _incomeStandards = (incRes as List)
          .map((r) => IncomeStandard.fromJson(r))
          .toList();

      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('WelfareStandards load error: $e');
    }
  }

  // ─────────────────────────────────────────────
  // 소득분위별 금액 라벨 (1인가구 기준)
  // ─────────────────────────────────────────────
  String getIncomeLevelLabel(int level) {
    final std = _incomeStandards.where((s) => s.householdSize == 1).firstOrNull;
    if (std == null) return '소득분위 $level';

    final amounts = {
      1: std.pct32,
      2: std.pct40,
      3: std.pct47,
      4: std.pct50,
      5: (std.medianIncome * 0.6).toInt(),
      6: (std.medianIncome * 0.7).toInt(),
      7: (std.medianIncome * 0.8).toInt(),
      8: std.pct100,
      9: std.pct120,
    };

    final pct = _levelPct[level] ?? '';
    if (level == 10) {
      final man = (std.pct120 / 10000).floor();
      return '기준중위소득 120% 초과 (월 $man만원 이상)';
    }
    final limit = amounts[level] ?? 0;
    final man = (limit / 10000).floor();
    return '기준중위소득 $pct 이하 · 월 약 $man만원 이하 (1인가구)';
  }

  // ─────────────────────────────────────────────
  // 기초연금 해당 여부
  // ─────────────────────────────────────────────
  EligibilityResult checkBasicPension(int age, int? incomeLevel, bool isCouple) {
    if (age < 65) {
      return EligibilityResult.notEligible('만 65세 이상만 신청 가능');
    }
    if (incomeLevel == null) {
      return EligibilityResult.unknown('소득분위를 확인해주세요');
    }
    // 소득분위 6 이하 (기준중위소득 70% 이하) → 해당 가능성 높음
    if (incomeLevel <= 6) return EligibilityResult.eligible('소득 하위 70% 이하로 해당 가능성 높음');
    // 7~8분위 → 확인 필요 (소득인정액에 자산 포함되므로)
    if (incomeLevel <= 8) return EligibilityResult.unknown('소득인정액 기준으로 확인 필요 (주민센터 문의)');
    return EligibilityResult.notEligible('소득 기준 초과로 해당 가능성 낮음');
  }

  // ─────────────────────────────────────────────
  // 장기요양 서비스 조회
  // ─────────────────────────────────────────────
  LtcGradeBenefit? getLtcBenefit(int? grade) {
    if (grade == null) return null;
    return _ltcBenefits[grade];
  }

  // ─────────────────────────────────────────────
  // 건강검진 해당 여부 (짝수/홀수년 출생 교차)
  // ─────────────────────────────────────────────
  EligibilityResult checkHealthCheckup(int birthYear) {
    final thisYear = DateTime.now().year;
    final isEligible = (birthYear % 2) == (thisYear % 2);
    return isEligible
        ? EligibilityResult.eligible('$thisYear년 건강검진 대상')
        : EligibilityResult.notEligible('${thisYear + 1}년 대상 (격년제)');
  }
}

// ─────────────────────────────────────────────
// 해당 여부 결과 모델
// ─────────────────────────────────────────────
enum EligibilityStatus { eligible, unknown, notEligible }

class EligibilityResult {
  final EligibilityStatus status;
  final String reason;

  const EligibilityResult._(this.status, this.reason);
  factory EligibilityResult.eligible(String r) =>
      EligibilityResult._(EligibilityStatus.eligible, r);
  factory EligibilityResult.unknown(String r) =>
      EligibilityResult._(EligibilityStatus.unknown, r);
  factory EligibilityResult.notEligible(String r) =>
      EligibilityResult._(EligibilityStatus.notEligible, r);
}
