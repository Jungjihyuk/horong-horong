# HorongHorong Metabase Dashboard

이 폴더는 Supabase에 쌓이는 피드백 데이터를 Metabase에서 대시보드로 보기 위한 로컬 운영 세트입니다.

## 목표

- 산만함 기준이 사용자의 체감과 맞는지 추적
- `selective`, `sustained`, `switching` 신호별 만족도 확인
- 신호 유형별 피드백 수와 판단 미흡률 확인
- 기준치 프리셋별 오답률 확인
- 어느 화면이나 기능에서 불만족 피드백이 많이 나오는지 확인
- 코멘트 데이터를 모아 AI 정성 분석 후보로 분리
- 익명 개선 데이터 동의율 변화 확인

## 1. Supabase 분석 뷰 만들기

Supabase 대시보드에서 `SQL Editor`를 열고 `ops/metabase/views.sql` 내용을 실행합니다.

이 SQL은 원본 테이블을 수정하지 않고 아래 읽기 전용 뷰만 추가합니다.

- `analytics_attention_feedback_events`
- `analytics_attention_signal_accuracy_daily`
- `analytics_attention_signal_accuracy_weekly`
- `analytics_attention_threshold_satisfaction`
- `analytics_attention_feedback_location_summary`
- `analytics_attention_score_bucket_accuracy`
- `analytics_attention_comments_for_ai`
- `analytics_telemetry_consent_daily`

`signal_type`은 아래 고정 분류로 정규화됩니다. 기존에 쌓인 `return_delay`, `declined_trend`, `none` 같은 이전 값은 뷰에서 새 기준으로 변환됩니다.

| `signal_type` | 한글 라벨 | 의미 |
|---|---|---|
| `selective` | 선택적 주의 | 집중 중 알림, 메시지, 방해 가능 앱처럼 중요하지 않은 자극에 주의가 붙잡힌 경우 |
| `sustained` | 지속적 주의 | 목표한 집중 세션을 끝까지 유지하지 못하고 조기 중단한 경우 |
| `switching` | 주의 전환 | 휴식이나 다른 활동 후 원래 작업 흐름으로 돌아오는 데 지연이 생긴 경우 |
| `general` | 종합/기타 | 특정 신호 하나로 귀속하기 어려운 일간/주간/월간 종합 해석 |
| `insufficient_data` | 데이터 부족 | 비교나 판단에 필요한 기록이 부족한 경우 |

대시보드에서 `판단 미흡`은 사용자가 `애매해요` 또는 `아니에요`를 누른 피드백의 합산입니다. 즉 `unresolved_count = unclear_count + wrong_count`, `unresolved_rate = unresolved_count / feedback_count`로 봅니다.

## 2. 로컬 Metabase 실행

Docker가 실행 중인 상태에서 프로젝트 루트에서 실행합니다.

```bash
docker compose -f ops/metabase/docker-compose.yml up -d
```

그 다음 브라우저에서 엽니다.

```text
http://localhost:3000
```

처음 접속하면 Metabase 관리자 계정을 하나 만듭니다. 이 계정은 로컬 Metabase용 계정이고 Supabase 계정과 별개입니다.

## 3. Supabase DB 연결

Metabase 초기 설정 또는 `Admin settings > Databases > Add database`에서 PostgreSQL을 선택합니다.

Supabase 대시보드에서 DB 접속 정보는 보통 `Project Settings > Database`에서 확인합니다.

필요한 값:

- Host
- Port
- Database name: 보통 `postgres`
- Username
- Password
- SSL: enabled

앱에 넣었던 `Project URL`과 `Publishable key`는 앱에서 REST API로 insert할 때 쓰는 값입니다. Metabase는 PostgreSQL DB에 직접 읽기 연결을 하므로 DB host/user/password가 따로 필요합니다.

## 4. 질문 만들기

Metabase에서 `New > SQL query`를 눌러 `ops/metabase/questions.sql`의 각 블록을 하나씩 질문으로 저장합니다.

반복 작업을 줄이려면 Metabase API 스크립트로 한 번에 질문을 생성할 수 있습니다.

먼저 `ops/metabase/.env.local`에 로컬 Metabase 값을 채웁니다.

```bash
METABASE_URL=http://localhost:3000
METABASE_EMAIL=YOUR_METABASE_LOGIN_EMAIL
METABASE_PASSWORD=YOUR_METABASE_LOGIN_PASSWORD
METABASE_DATABASE_NAME=Horong Supabase
METABASE_DASHBOARD_ID=1
```

그 다음 실행합니다.

```bash
node ops/metabase/create-cards.mjs
```

또는 파일에 저장하지 않고 일회성 환경변수로 실행할 수도 있습니다.

```bash
METABASE_URL=http://localhost:3000 \
METABASE_EMAIL='you@example.com' \
METABASE_PASSWORD='your-metabase-password' \
METABASE_DATABASE_NAME='Horong Supabase' \
METABASE_DASHBOARD_ID='1' \
node ops/metabase/create-cards.mjs
```

`METABASE_DATABASE_NAME`은 Metabase에 추가한 Supabase DB 표시 이름입니다.

`METABASE_DASHBOARD_ID`는 선택값입니다. 대시보드 URL이 `http://localhost:3000/dashboard/1-horong-focus-feedback`라면 `1`입니다. 이 값을 넣으면 스크립트가 생성한 질문을 해당 대시보드에 추가하려고 시도합니다. Metabase 버전에 따라 탭 생성과 정교한 배치는 UI에서 조정해야 할 수 있습니다.

추천 질문 이름:

| 한글 이름 | English |
|---|---|
| `판단 일치율` | `Judgment agreement rate` |
| `총 다운로드 수` | `Total downloads` |
| `피드백 허용률` | `Feedback opt-in rate` |
| `일평균 피드백 수` | `Average daily feedback count` |
| `최근 30일 피드백 수` | `Last 30 days feedback count` |
| `일별 피드백 수` | `Daily feedback volume` |
| `일별 피드백 참여 기기 수` | `Daily active feedback installs` |
| `판단 분포` | `Verdict distribution` |
| `신호 유형별 피드백 분포` | `Feedback distribution by signal type` |
| `신호 유형별 피드백 수` | `Feedback volume by signal type` |
| `신호 유형별 판단 미흡률` | `Unresolved judgment rate by signal type` |
| `점수 구간별 판단 비율` | `Verdict ratio by score bucket` |
| `피드백 위치별 판단 현황` | `Verdict status by feedback location` |

추천 시각화:

| 한글 이름 | 추천 차트 | 설정 |
|---|---|---|
| `판단 일치율` | Number | `맞아요 / 전체 피드백`, `%` suffix |
| `총 다운로드 수` | Number | 현재는 피드백/동의 이벤트로 관측된 설치 수 |
| `피드백 허용률` | Number | 동의 또는 피드백 제출로 허용이 확인된 설치 비율, `%` suffix |
| `일평균 피드백 수` | Number | 최근 30일 피드백 수 / 30 |
| `최근 30일 피드백 수` | Number | 최근 30일 전체 피드백 수 |
| `일별 피드백 수` | Bar chart 또는 Line chart | X축 `event_day`, Y축 `feedback_count` |
| `일별 피드백 참여 기기 수` | Line chart | X축 `event_day`, Y축 `active_install_count` |
| `판단 분포` | Donut chart 또는 Pie chart | category `verdict_label`, value `feedback_count` |
| `신호 유형별 피드백 분포` | Donut chart 또는 Pie chart | category `신호 유형`, value `피드백 수` |
| `신호 유형별 피드백 수` | Table | `신호 유형`, `피드백 수`, `피드백 참여자 수`, `피드백 비중` |
| `신호 유형별 판단 미흡률` | Bar chart 또는 Table | `애매해요 + 아니에요` 비율 |
| `점수 구간별 판단 비율` | 100% stacked bar chart | X축 `점수 구간`, breakout `신호 유형`, Y축 `맞아요` / `애매해요` / `아니에요` |
| `피드백 위치별 판단 현황` | Table | 위치/이벤트별 `맞아요`, `애매해요`, `아니에요`, `판단 미흡률` |

## 5. 대시보드 구성

대시보드 이름은 `Horong Focus Feedback` 또는 `호롱 집중 피드백`을 권장합니다.

상세 배치는 `ops/metabase/dashboard-layout.md`를 기준으로 합니다.

추천 탭:

1. `정확도 개요`
2. `신호 진단`
3. `코멘트 & 동의`

`정확도 개요` 탭 상단에는 KPI Number 카드를 먼저 배치합니다.

- `판단 일치율`
- `총 다운로드 수`
- `피드백 허용률`
- `일평균 피드백 수`
- `최근 30일 피드백 수`

그 아래에 추이와 분포 차트를 배치합니다.

## 해석 기준

`correct_rate`가 낮고 `wrong_rate`가 높은 구간은 사용자가 앱의 집중 상태 판단에 동의하지 않는 구간입니다.

특히 우선순위는 아래 순서로 봅니다.

1. `signal_label`별 `아니에요 비율`
2. `threshold_preset`별 `아니에요 비율`
3. `score_bucket`별 `아니에요 비율`
4. `feedback_location`별 `아니에요 비율`
5. 코멘트의 반복 주제

이 순서로 보면 “전체적으로 불만족이 높은가”와 “특정 기준치나 화면에서만 불만족이 높은가”를 분리해서 볼 수 있습니다.
