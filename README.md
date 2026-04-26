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

개별 phase(`0_national`, `0`, `providers`, `0_detail`, `1`, `1_web`, `1_lite`, `2`, `2r`, `fix_*`)는 장애 분석이나 부분 복구용으로 남겨둡니다.

## 지역 복지 수집 로봇

지자체 홈페이지 웹 수집은 통합 복지서비스 배치와 분리해 `batch/local_welfare_batch.py`에서 실행합니다. GitHub Actions의 `CareWay 지역 복지 수집 로봇` workflow에서 수동 실행합니다.

현재 파일럿 수집은 고정 URL과 지역별 노인복지 후보 자동 탐색을 함께 사용합니다.

- 충북 괴산군: 고정 노인일자리 페이지
- 경기 용인시: 노인일자리, 기초연금, 노인돌봄 관련 페이지 자동 탐색
- 서울 노원구: 노원 복지샘 기반 어르신 복지 페이지 자동 탐색

지자체/복지포털 관련 웹페이지를 읽어 `welfare_services`에 `source = local_site_pilot`으로 저장합니다. 기본 실행은 기존 데이터를 유지하고 `online_url` 기준으로 누적 upsert합니다. 수동 실행에서 `reset_existing`을 켠 경우에만 기존 지역 수집 데이터를 삭제하고 재수집합니다.

실행 후 `batch/output/local_welfare_report.json` 리포트를 생성하고 GitHub Actions artifact(`local-welfare-report`)로 업로드합니다. 리포트에는 저장/스킵/실패 건수, 저장 데이터 샘플, 품질 경고가 포함됩니다.
