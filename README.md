# CareWay

CareWay는 자녀가 부모님 복지 혜택을 찾고 신청 관리를 할 수 있도록 만든 Flutter 앱입니다.

## 구조

- `lib/`: Flutter 앱 화면, 모델, Provider
- `batch/`: 복지서비스 수집, 상세 보강, AI 분류, 검색 토큰 생성 배치
- `supabase/functions/`: Supabase Edge Function
- `.github/workflows/`: 배치 자동 실행 워크플로

## 데이터 흐름

1. `batch/welfare_ai_processor.py`가 복지로/사회서비스 데이터를 수집합니다.
2. 배치가 Supabase의 `welfare_services`, `service_providers` 등을 갱신합니다.
3. 앱은 Supabase DB를 읽어 부모님 프로필 기준으로 복지서비스를 추천합니다.

## 배치 실행

필수 환경변수:

- `SUPABASE_SERVICE_KEY`
- `WELFARE_API_KEY`
- `LOCAL_WELFARE_API_KEY`
- `GEMINI_API_KEY`
- `SOCIAL_SERVICE_API_KEY`

```bash
pip install -r batch/requirements.txt
python batch/welfare_ai_processor.py --phase 1_lite
python batch/welfare_ai_processor.py --phase 2
```

운영용 phase:

- `daily`: 매일 자동 실행용. 국가/지자체 신규 수집, 상세 보강, 신규 AI 분류, 기본 보정
- `collect`: Gemini 호출 없이 신규/누락 데이터 수집과 규칙 기반 보정
- `reclassify`: 상세 누락 일부 보강 후 오래된 AI 분류 순환 재검토
- `repair`: 데이터 수집 없이 지역, 코드, 검색 토큰 보정
- `repair_force_search`: 검색 토큰까지 강제 재생성하는 보정
- `collect_pilot_local`: 충북 괴산군/경기 용인시 수지구 웹페이지 파일럿 수집

개별 phase(`0_national`, `0`, `providers`, `0_detail`, `1`, `1_web`, `1_lite`, `2`, `2r`, `fix_*`)는 장애 분석이나 부분 복구용으로 남겨둡니다.

## 지역 웹 수집 파일럿

`collect_pilot_local`은 자동 배치에 포함하지 않는 수동 테스트용 phase입니다. 현재 대상은 다음 두 지역입니다.

- 충북 괴산군
- 경기 용인시 수지구

구청/복지/보건소 관련 웹페이지를 읽어 `welfare_services`에 `source = local_site_pilot`으로 저장합니다. 수집 품질을 확인한 뒤 자동 배치 편입 여부를 결정합니다.
