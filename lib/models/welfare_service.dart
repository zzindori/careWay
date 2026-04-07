import 'parent_profile.dart';

class WelfareService {
  final String id;
  final String name;
  final String category;      // medical / care / living / housing / finance / mobility
  final String description;
  final String targetInfo;    // 지원 대상
  final String benefitInfo;   // 지원 내용/금액
  final String applyPlace;    // 신청처
  final String? onlineUrl;    // 온라인 신청 URL
  final List<String> requiredDocs; // 필요 서류
  final int difficulty;       // 신청 난이도 1~3 (1=쉬움)
  final DateTime? deadline;   // 신청 마감일
  final int? benefitAmount;   // 혜택 금액 (원, null=현물)
  final bool isRenewable;     // 매년 갱신 필요

  // 필터 조건
  final int minAge;               // 최소 나이 (0 = 제한없음)
  final int maxIncomeLevel;       // 최대 소득분위 (10 = 제한없음)
  final bool requiresLtcGrade;    // 장기요양등급 필수
  final bool requiresAlone;       // 독거 필수
  final bool requiresBasicRecipient; // 기초수급자 필수

  // AI가 추출한 대상 연령층 (DB: target_age_group)
  // elderly / youth / child / adult / all / unknown
  final String targetAgeGroup;

  // 배치 수집된 상세 정보 (DB: applmet_list, inq_place, detail_content)
  final List<Map<String, String>> applmetList; // 신청방법 목록
  final String inqPlace;                       // 문의처
  final String detailContent;                  // 상세 내용

  const WelfareService({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.targetInfo,
    required this.benefitInfo,
    required this.applyPlace,
    this.onlineUrl,
    this.requiredDocs = const [],
    this.difficulty = 2,
    this.deadline,
    this.benefitAmount,
    this.isRenewable = false,
    this.minAge = 0,
    this.maxIncomeLevel = 10,
    this.requiresLtcGrade = false,
    this.requiresAlone = false,
    this.requiresBasicRecipient = false,
    this.targetAgeGroup = 'unknown',
    this.applmetList = const [],
    this.inqPlace = '',
    this.detailContent = '',
  });

  String get categoryLabel {
    const labels = {
      'medical': '의료',
      'care': '돌봄',
      'living': '생활지원',
      'housing': '주거',
      'finance': '경제',
      'mobility': '이동',
    };
    return labels[category] ?? category;
  }

  String get difficultyLabel {
    switch (difficulty) {
      case 1: return '간편';
      case 2: return '보통';
      case 3: return '복잡';
      default: return '보통';
    }
  }

  bool get isDeadlineSoon {
    if (deadline == null) return false;
    return deadline!.difference(DateTime.now()).inDays <= 7;
  }

  // ─── 키워드 분석 ───────────────────────────────────────────

  static const _nonElderlyKeywords = [
    '청소년', '아동', '어린이', '초등', '중학', '고등', '학생',
    '임신', '임산부', '산모', '영유아', '영아', '유아', '신생아',
    '청년', '대학생', // 만 39세 이하 대상 청년 정책
  ];

  static const _elderlyKeywords = [
    '노인', '어르신', '65세', '60세', '경로', '실버', '고령',
  ];

  // targetInfo + name + description 에서 비노인 키워드 포함 여부
  bool get _isObviouslyNotElderly {
    final text = '$name $targetInfo $description';
    return _nonElderlyKeywords.any((k) => text.contains(k));
  }

  // 노인 대상임을 알 수 있는 서비스인지
  bool get isElderlyTargeted {
    // DB AI 분류 우선 사용
    if (targetAgeGroup == 'elderly' || targetAgeGroup == 'all') return true;
    if (targetAgeGroup == 'youth' || targetAgeGroup == 'child') return false;
    // DB에 아직 분류 안된 경우 → 키워드 폴백
    final text = '$name $targetInfo $description';
    return _elderlyKeywords.any((k) => text.contains(k));
  }

  // DB에 실제 필터 조건이 설정된 서비스인지
  bool get hasFilterCriteria =>
      minAge > 0 || maxIncomeLevel < 10 || requiresLtcGrade || requiresAlone || requiresBasicRecipient;

  // ─── 자격 검사 ───────────────────────────────────────────

  // 프로필 조건에 맞지 않는 이유 목록 (빈 리스트 = 해당됨)
  List<String> getMismatchReasons(ParentProfile profile) {
    final reasons = <String>[];
    final age = profile.age;
    final incomeLevel = profile.incomeLevel ?? 10;

    // 1. DB AI 분류 우선 적용
    if (targetAgeGroup == 'youth') {
      reasons.add('청소년 대상 서비스');
      return reasons;
    }
    if (targetAgeGroup == 'child') {
      reasons.add('아동·영유아 대상 서비스');
      return reasons;
    }

    // 2. DB 미분류(unknown) → 키워드로 보조 필터
    if (targetAgeGroup == 'unknown' && _isObviouslyNotElderly) {
      reasons.add('대상자 연령 조건 미해당');
      return reasons;
    }

    // 3. DB에 설정된 구조화 조건 체크
    if (minAge > 0 && age < minAge) {
      reasons.add('만 $minAge세 이상 필요 (현재 ${age}세)');
    }
    if (maxIncomeLevel < 10 && incomeLevel > maxIncomeLevel) {
      reasons.add('소득 ${maxIncomeLevel}분위 이하 필요 (현재 ${incomeLevel}분위)');
    }
    if (requiresLtcGrade && !profile.hasLtcGrade) {
      reasons.add('장기요양 등급 보유자 전용');
    }
    if (requiresAlone && !profile.liveAlone) {
      reasons.add('독거 노인 전용');
    }
    if (requiresBasicRecipient && !profile.isBasicRecipient) {
      reasons.add('기초생활수급자 전용');
    }

    return reasons;
  }

  bool matchesProfile(ParentProfile profile) => getMismatchReasons(profile).isEmpty;

  // "✓ 해당됨" 뱃지를 보여줄 만큼 근거가 충분한가:
  // - DB에 조건이 있고 통과했거나
  // - 노인 대상 서비스로 식별된 경우
  bool get canShowMatchedBadge => hasFilterCriteria || isElderlyTargeted;

  factory WelfareService.fromJson(Map<String, dynamic> json) {
    return WelfareService(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      description: json['description'] as String,
      targetInfo: json['target_info'] as String,
      benefitInfo: json['benefit_info'] as String,
      applyPlace: json['apply_place'] as String,
      onlineUrl: json['online_url'] as String?,
      requiredDocs: (json['required_docs'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      difficulty: json['difficulty'] as int? ?? 2,
      deadline: json['deadline'] != null
          ? DateTime.parse(json['deadline'] as String)
          : null,
      benefitAmount: json['benefit_amount'] as int?,
      isRenewable: json['is_renewable'] as bool? ?? false,
      minAge: json['min_age'] as int? ?? 0,
      maxIncomeLevel: json['max_income_level'] as int? ?? 10,
      requiresLtcGrade: json['requires_ltc_grade'] as bool? ?? false,
      requiresAlone: json['requires_alone'] as bool? ?? false,
      requiresBasicRecipient: json['requires_basic_recipient'] as bool? ?? false,
      targetAgeGroup: json['target_age_group'] as String? ?? 'unknown',
      applmetList: (json['applmet_list'] as List<dynamic>?)
              ?.map((e) => Map<String, String>.from(
                    (e as Map<String, dynamic>).map((k, v) => MapEntry(k, v?.toString() ?? '')),
                  ))
              .toList() ??
          [],
      inqPlace: json['inq_place'] as String? ?? '',
      detailContent: json['detail_content'] as String? ?? '',
    );
  }
}
