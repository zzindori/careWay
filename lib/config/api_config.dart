class ApiConfig {
  // ══════════════════════════════════════════════════
  // [API 수집] 어드민에서 주기적으로 호출 → DB 저장
  // ══════════════════════════════════════════════════

  // 사회보장정보원 (복지로) - 전 카테고리 서비스 목록/상세
  // srchKeyCode: 001=저소득 002=장애인 003=노인 004=한부모
  //              005=다문화 006=아동 007=임신출산 008=청소년
  //              009=지역사회 010=기타
  static const welfareApiKey =
      'c488333ba7f275fd3a92ca8b3b15b703352159f4206249016e75df2bb86a1927';
  static const welfareBase =
      'https://apis.data.go.kr/B554287/NationalWelfareInformationsV001';
  static const welfareListEndpoint =
      '$welfareBase/NationalWelfareInformationsList';

  // 경기도 지자체 복지서비스 (사용자 거주지 기반 확장 예정)
  static const ggApiKey = 'e90cfdae15d245278caf0875e27029c3';
  static const ggBase = 'https://openapi.gg.go.kr';

  // TODO: 타 시도 지자체 API (서울, 인천, 부산 등)

  // ══════════════════════════════════════════════════
  // [API 실시간] 앱에서 직접 호출 (탭할 때마다)
  // ══════════════════════════════════════════════════

  // 복지로 서비스 상세 (wlfareInfoId로 조회)
  static const welfareDetailEndpoint =
      '$welfareBase/NationalWelfaredetailedV001';

  // ══════════════════════════════════════════════════
  // [DB 저장 - 연 1회 수동 업데이트]
  // 공단/복지부 고시 기준 → Supabase 직접 관리
  // 해당 테이블: ltc_grade_benefits, income_standards
  // ══════════════════════════════════════════════════
  // - 장기요양 등급별 월 한도액 및 이용 가능 서비스
  // - 기준중위소득 (소득분위 필터링 기준)
  // - 기초연금 선정기준 (소득인정액 상한)
  // - 건강검진 대상 기준 (홀수/짝수년 출생)

  // ══════════════════════════════════════════════════
  // [DB 저장 - AI 어드민 추출]
  // 복지로 상세 텍스트 → AI → 구조화된 필터 기준
  // 해당 컬럼: welfare_services.min_age, max_income_level,
  //            requires_ltc_grade, requires_alone,
  //            requires_basic_recipient
  // ══════════════════════════════════════════════════

  // ══════════════════════════════════════════════════
  // [미등록 - 추후 신청 예정]
  // ══════════════════════════════════════════════════
  // - 국민건강보험공단 (장기요양 급여 실적 조회)
  // - 중앙치매센터 (치매안심센터 위치/서비스)
  // - 각 시도 지자체 API (서울, 인천, 부산, 경남 등)
}
