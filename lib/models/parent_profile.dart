class ParentProfile {
  final String? id;
  final String userId;
  final String name;
  final int birthYear;
  final String region;        // 시도
  final String subRegion;     // 시군구
  final String healthStatus;  // good / fair / poor
  final bool hasLtcGrade;     // 장기요양등급 보유
  final int? ltcGrade;        // 1~6등급
  final int? incomeLevel;     // 소득분위 1~10
  final bool isBasicRecipient; // 기초수급 여부
  final bool liveAlone;        // 독거 여부
  final DateTime? createdAt;

  const ParentProfile({
    this.id,
    required this.userId,
    required this.name,
    required this.birthYear,
    required this.region,
    required this.subRegion,
    this.healthStatus = 'good',
    this.hasLtcGrade = false,
    this.ltcGrade,
    this.incomeLevel,
    this.isBasicRecipient = false,
    this.liveAlone = false,
    this.createdAt,
  });

  int get age {
    final now = DateTime.now();
    return now.year - birthYear;
  }

  factory ParentProfile.fromJson(Map<String, dynamic> json) {
    return ParentProfile(
      id: json['id'] as String?,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      birthYear: json['birth_year'] as int,
      region: json['region'] as String,
      subRegion: json['sub_region'] as String,
      healthStatus: json['health_status'] as String? ?? 'good',
      hasLtcGrade: json['has_ltc_grade'] as bool? ?? false,
      ltcGrade: json['ltc_grade'] as int?,
      incomeLevel: json['income_level'] as int?,
      isBasicRecipient: json['is_basic_recipient'] as bool? ?? false,
      liveAlone: json['live_alone'] as bool? ?? false,
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
      'has_ltc_grade': hasLtcGrade,
      'ltc_grade': ltcGrade,
      'income_level': incomeLevel,
      'is_basic_recipient': isBasicRecipient,
      'live_alone': liveAlone,
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
    bool? hasLtcGrade,
    int? ltcGrade,
    int? incomeLevel,
    bool? isBasicRecipient,
    bool? liveAlone,
  }) {
    return ParentProfile(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      birthYear: birthYear ?? this.birthYear,
      region: region ?? this.region,
      subRegion: subRegion ?? this.subRegion,
      healthStatus: healthStatus ?? this.healthStatus,
      hasLtcGrade: hasLtcGrade ?? this.hasLtcGrade,
      ltcGrade: ltcGrade ?? this.ltcGrade,
      incomeLevel: incomeLevel ?? this.incomeLevel,
      isBasicRecipient: isBasicRecipient ?? this.isBasicRecipient,
      liveAlone: liveAlone ?? this.liveAlone,
    );
  }
}
