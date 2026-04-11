class ParentProfile {
  final String? id;
  final String userId;
  final String name;
  final int birthYear;
  final String region;        // 시도
  final String subRegion;     // 시군구
  final String healthStatus;  // good / fair / poor

  // 장기요양등급 상태: 'has' / 'applying' / 'none'
  final String ltcGradeStatus;
  final int? ltcGrade;        // 1~6등급 (ltcGradeStatus == 'has'일 때)

  final int? incomeLevel;     // 소득분위 1~10
  final bool isBasicRecipient; // 기초수급 여부
  final bool liveAlone;        // 독거 여부

  // 건강 상태 상세 (복수 선택)
  // hearing / vision / mobility / dementia / housework / hospital
  final List<String> healthConditions;

  // 보훈 종류 (복수 선택)
  // 국가유공자 / 참전유공자 / 독립유공자
  final List<String> veteranTypes;

  final DateTime? createdAt;

  const ParentProfile({
    this.id,
    required this.userId,
    required this.name,
    required this.birthYear,
    required this.region,
    required this.subRegion,
    this.healthStatus = 'good',
    this.ltcGradeStatus = 'none',
    this.ltcGrade,
    this.incomeLevel,
    this.isBasicRecipient = false,
    this.liveAlone = false,
    this.healthConditions = const [],
    this.veteranTypes = const [],
    this.createdAt,
  });

  // 하위 호환 getter
  bool get hasLtcGrade => ltcGradeStatus == 'has';
  bool get isVeteran => veteranTypes.isNotEmpty;

  int get age {
    final now = DateTime.now();
    return now.year - birthYear;
  }

  factory ParentProfile.fromJson(Map<String, dynamic> json) {
    // ltc_grade_status 컬럼이 없으면 has_ltc_grade로 폴백
    final ltcStatus = json['ltc_grade_status'] as String? ??
        ((json['has_ltc_grade'] as bool? ?? false) ? 'has' : 'none');

    return ParentProfile(
      id: json['id'] as String?,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      birthYear: json['birth_year'] as int,
      region: json['region'] as String,
      subRegion: json['sub_region'] as String,
      healthStatus: json['health_status'] as String? ?? 'good',
      ltcGradeStatus: ltcStatus,
      ltcGrade: json['ltc_grade'] as int?,
      incomeLevel: json['income_level'] as int?,
      isBasicRecipient: json['is_basic_recipient'] as bool? ?? false,
      liveAlone: json['live_alone'] as bool? ?? false,
      healthConditions: (json['health_conditions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      veteranTypes: (json['veteran_types'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'name': name,
      'birth_year': birthYear,
      'region': region,
      'sub_region': subRegion,
      'health_status': healthStatus,
      'ltc_grade_status': ltcGradeStatus,
      'has_ltc_grade': hasLtcGrade,  // 기존 컬럼 호환
      'ltc_grade': ltcGrade,
      'income_level': incomeLevel,
      'is_basic_recipient': isBasicRecipient,
      'live_alone': liveAlone,
      'health_conditions': healthConditions,
      'veteran_types': veteranTypes,
    };
  }

  ParentProfile copyWith({
    String? id,
    String? userId,
    String? name,
    int? birthYear,
    String? region,
    String? subRegion,
    String? healthStatus,
    String? ltcGradeStatus,
    int? ltcGrade,
    int? incomeLevel,
    bool? isBasicRecipient,
    bool? liveAlone,
    List<String>? healthConditions,
    List<String>? veteranTypes,
  }) {
    return ParentProfile(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      birthYear: birthYear ?? this.birthYear,
      region: region ?? this.region,
      subRegion: subRegion ?? this.subRegion,
      healthStatus: healthStatus ?? this.healthStatus,
      ltcGradeStatus: ltcGradeStatus ?? this.ltcGradeStatus,
      ltcGrade: ltcGrade ?? this.ltcGrade,
      incomeLevel: incomeLevel ?? this.incomeLevel,
      isBasicRecipient: isBasicRecipient ?? this.isBasicRecipient,
      liveAlone: liveAlone ?? this.liveAlone,
      healthConditions: healthConditions ?? this.healthConditions,
      veteranTypes: veteranTypes ?? this.veteranTypes,
    );
  }
}
