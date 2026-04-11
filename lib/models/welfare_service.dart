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
  final int minAge;
  final int maxIncomeLevel;
  final bool requiresLtcGrade;
  final bool requiresAlone;
  final bool requiresBasicRecipient;
  final bool requiresVeteran;    // 보훈대상자 필수
  final bool requiresDisability; // 장애인 전용

  // AI 분류 필드
  final String targetAgeGroup;  // elderly/youth/child/infant/adult/veteran/disabled/all/unknown
  final String region;           // 서울 / 경기 / 전국 등
  final List<String> serviceTags; // dementia/mobility/daily_care/hearing/vision/medical

  // 배치 수집된 상세 정보
  final List<Map<String, String>> applmetList;
  final String inqPlace;
  final String detailContent;
  final String aiSummary;   // Gemini AI 요약

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
    this.requiresVeteran = false,
    this.requiresDisability = false,
    this.targetAgeGroup = 'unknown',
    this.region = '',
    this.serviceTags = const [],
    this.applmetList = const [],
    this.inqPlace = '',
    this.detailContent = '',
    this.aiSummary = '',
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
    '청년', '대학생',
  ];

  static const _elderlyKeywords = [
    '노인', '어르신', '65세', '60세', '경로', '실버', '고령',
  ];

  bool get _isObviouslyNotElderly {
    final text = '$name $targetInfo $description';
    return _nonElderlyKeywords.any((k) => text.contains(k));
  }

  bool get isElderlyTargeted {
    if (targetAgeGroup == 'elderly' || targetAgeGroup == 'all') return true;
    if (targetAgeGroup == 'youth' ||
        targetAgeGroup == 'child' ||
        targetAgeGroup == 'infant') {
      return false;
    }
    final text = '$name $targetInfo $description';
    return _elderlyKeywords.any((k) => text.contains(k));
  }

  bool get hasFilterCriteria =>
      minAge > 0 ||
      maxIncomeLevel < 10 ||
      requiresLtcGrade ||
      requiresAlone ||
      requiresBasicRecipient ||
      requiresVeteran ||
      requiresDisability;

  // ─── 지역 매칭 ────────────────────────────────────────────
  static String _normalizeRegion(String r) {
    if (r.contains('서울')) return '서울';
    if (r.contains('부산')) return '부산';
    if (r.contains('대구')) return '대구';
    if (r.contains('인천')) return '인천';
    if (r.contains('광주')) return '광주';
    if (r.contains('대전')) return '대전';
    if (r.contains('울산')) return '울산';
    if (r.contains('세종')) return '세종';
    if (r.contains('경기')) return '경기';
    if (r.contains('강원')) return '강원';
    if (r.contains('충북') || r.contains('충청북')) return '충북';
    if (r.contains('충남') || r.contains('충청남')) return '충남';
    if (r.contains('전북') || r.contains('전라북')) return '전북';
    if (r.contains('전남') || r.contains('전라남')) return '전남';
    if (r.contains('경북') || r.contains('경상북')) return '경북';
    if (r.contains('경남') || r.contains('경상남')) return '경남';
    if (r.contains('제주')) return '제주';
    return r;
  }

  bool _regionMatches(String profileRegion) {
    if (region.isEmpty || region == '전국') return true;
    return _normalizeRegion(region) == _normalizeRegion(profileRegion);
  }

  // ─── 자격 검사 ───────────────────────────────────────────

  List<String> getMismatchReasons(ParentProfile profile) {
    final age = profile.age;
    final incomeLevel = profile.incomeLevel ?? 10;
    final reasons = <String>[];

    // 나이
    if (minAge > 0 && age < minAge) {
      reasons.add('만 $minAge세 이상 필요 (현재 $age세)');
    }
    // 지역
    if (!_regionMatches(profile.region)) {
      reasons.add('$region 지역 서비스');
    }
    // 소득
    if (maxIncomeLevel < 10 && incomeLevel > maxIncomeLevel) {
      reasons.add('소득 $maxIncomeLevel분위 이하 필요 (현재 $incomeLevel분위)');
    }
    // 장기요양등급
    if (requiresLtcGrade && !profile.hasLtcGrade) {
      reasons.add('장기요양 등급 보유자 전용');
    }
    // 독거
    if (requiresAlone && !profile.liveAlone) {
      reasons.add('독거 노인 전용');
    }
    // 기초수급
    if (requiresBasicRecipient && !profile.isBasicRecipient) {
      reasons.add('기초생활수급자 전용');
    }

    return reasons;
  }

  bool matchesProfile(ParentProfile profile) => getMismatchReasons(profile).isEmpty;

  // ─── 해당 사유 (Tier 1 표시용) ────────────────────────────
  List<String> getMatchReasons(ParentProfile profile) {
    final reasons = <String>[];

    if (minAge > 0 && profile.age >= minAge) {
      reasons.add('만 $minAge세 이상');
    } else if (isElderlyTargeted) {
      reasons.add('노인 대상');
    }
    if (region.isNotEmpty && region != '전국') {
      reasons.add('$region 지역');
    }
    if (maxIncomeLevel < 10) {
      reasons.add('소득 $maxIncomeLevel분위 이하');
    }
    if (requiresLtcGrade && profile.hasLtcGrade && profile.ltcGrade != null) {
      reasons.add('장기요양 ${profile.ltcGrade}등급');
    }
    if (requiresAlone && profile.liveAlone) {
      reasons.add('독거 노인');
    }
    if (requiresBasicRecipient && profile.isBasicRecipient) {
      reasons.add('기초수급자');
    }
    if (profile.isVeteran && (targetAgeGroup == 'veteran' || requiresVeteran)) {
      reasons.add('보훈대상자');
    }
    return reasons;
  }

  // ─── 3단계 매칭 티어 ────────────────────────────────────────
  // 0: 표시 안함
  // 1: 🔴 지금 바로 신청 (조건 모두 충족, 장기요양 불필요)
  // 2: 🟡 등급 신청 후 가능 (장기요양 등급 필요, 현재 없음)
  // 3: 🔵 알아두면 좋아요 (조건 일부 미충족 or 분류 불명확)

  int getMatchTier(ParentProfile profile) {
    // ── Tier 0: 대상 아님 ─────────────────────────────────
    if (targetAgeGroup == 'youth' || targetAgeGroup == 'child' ||
        targetAgeGroup == 'infant' || targetAgeGroup == 'disabled') {
      return 0;
    }
    if (targetAgeGroup == 'unknown' && _isObviouslyNotElderly) return 0;
    if (requiresDisability) return 0;

    // 보훈 전용인데 보훈대상자 아님
    final isVeteranService = targetAgeGroup == 'veteran' ||
        requiresVeteran || serviceTags.contains('veteran');
    if (isVeteranService && !profile.isVeteran) return 0;

    // 지역 불일치 → 숨김
    if (!_regionMatches(profile.region)) return 0;

    // ── 개별 조건 평가 ────────────────────────────────────
    final incomeLevel = profile.incomeLevel ?? 10;
    final ageOk = minAge <= 0 || profile.age >= minAge;
    final incomeOk = maxIncomeLevel >= 10 || incomeLevel <= maxIncomeLevel;
    final aloneOk = !requiresAlone || profile.liveAlone;
    final basicOk = !requiresBasicRecipient || profile.isBasicRecipient;

    final isRelevantGroup = isElderlyTargeted ||
        ['elderly', 'all', 'adult'].contains(targetAgeGroup) ||
        (isVeteranService && profile.isVeteran);

    // ── Tier 2: 장기요양 등급 필요 & 현재 없음 ──────────────
    if (requiresLtcGrade && !profile.hasLtcGrade) {
      if (ageOk && incomeOk && aloneOk && basicOk) return 2;
      if (isRelevantGroup) return 3;
      return 0;
    }

    // ── Tier 1: 모든 조건 충족 + 분류 명확 ─────────────────
    if (ageOk && incomeOk && aloneOk && basicOk) {
      if (isRelevantGroup && canShowMatchedBadge) return 1;
      // 분류 불명확(unknown) → 🔵
      return 3;
    }

    // ── Tier 3: 조건 일부 미충족 ────────────────────────────
    if (isRelevantGroup) return 3;
    return 0;
  }

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
      requiresVeteran: json['requires_veteran'] as bool? ?? false,
      requiresDisability: json['requires_disability'] as bool? ?? false,
      targetAgeGroup: json['target_age_group'] as String? ?? 'unknown',
      region: json['region'] as String? ?? '',
      serviceTags: (json['service_tags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      applmetList: (json['applmet_list'] as List<dynamic>?)
              ?.map((e) => Map<String, String>.from(
                    (e as Map<String, dynamic>).map((k, v) => MapEntry(k, v?.toString() ?? '')),
                  ))
              .toList() ??
          [],
      inqPlace: json['inq_place'] as String? ?? '',
      detailContent: json['detail_content'] as String? ?? '',
      aiSummary: json['ai_summary'] as String? ?? '',
    );
  }
}
