# Horong Focus Feedback Dashboard Layout

Metabase에서 `Horong Focus Feedback` 대시보드를 아래 구조로 배치한다.

## 탭 1. 정확도 개요

목적: 앱의 집중 상태 판단이 사용자 체감과 전체적으로 맞는지 빠르게 본다.

상단 KPI 카드 5개:

| 카드명 | 차트 | 의미 |
|---|---|---|
| `판단 일치율` | Number, Percent | 최근 30일 중 `맞아요` 비율 |
| `총 다운로드 수` | Number | 현재는 피드백/동의 이벤트로 관측된 설치 수 |
| `피드백 허용률` | Number, Percent | 동의 또는 피드백 제출로 허용이 확인된 설치 비율 |
| `일평균 피드백 수` | Number | 최근 30일 피드백 수 / 30 |
| `최근 30일 피드백 수` | Number | 최근 30일 전체 피드백 수 |

중단 카드:

| 카드명 | 차트 | 설정 |
|---|---|---|
| `일별 피드백 수` | Bar 또는 Line | X축 `event_day`, Y축 `feedback_count` |
| `일별 피드백 참여 기기 수` | Line | X축 `event_day`, Y축 `active_install_count` |
| `판단 분포` | Donut | category `verdict_label`, value `feedback_count` |

하단 카드:

| 카드명 | 차트 | 설정 |
|---|---|---|
| `신호 유형별 일별 판단 비율` | 100% stacked area/bar | X축 `event_day`, Y축 `verdict_rate`, series `verdict_label` |

## 탭 2. 신호 진단

목적: 어떤 신호, 기준치, 점수 구간에서 판단이 어긋나는지 찾는다.

카드:

| 카드명 | 차트 | 설정 |
|---|---|---|
| `신호 유형별 주간 판단 비율` | 100% stacked bar | X축 `event_week`, Y축 `verdict_rate`, series `verdict_label` |
| `기준치 프리셋별 만족도` | 100% stacked bar | X축 `threshold_preset`, Y축 `verdict_rate`, series `verdict_label` |
| `점수 구간별 판단 비율` | 100% stacked bar | X축 `score_bucket`, Y축 `verdict_rate`, series `verdict_label` |
| `문제 발생 위치 Top` | Horizontal bar 또는 Table | X축 `wrong_rate`, Y축 `feedback_location` |

## 탭 3. 코멘트 & 동의

목적: 정성 피드백과 데이터 수집 동의 상태를 확인한다.

카드:

| 카드명 | 차트 | 설정 |
|---|---|---|
| `최근 코멘트와 AI 분석 후보` | Table | `sanitized_comment` 중심으로 확인 |
| `익명 개선 데이터 동의 추이` | Stacked bar 또는 Line | X축 `event_day`, Y축 `install_count`, series `consent_status` |

## 대시보드 필터

가능하면 대시보드 상단에 공통 필터를 둔다.

| 필터명 | 연결할 컬럼 |
|---|---|
| `기간` | `created_at`, `event_day`, `event_week` |
| `신호 유형` | `signal_type` |
| `기준치 프리셋` | `threshold_preset` |
| `앱 버전` | `app_version` |

Metabase에서 필터를 만들고 각 카드의 같은 의미 컬럼에 연결하면, 탭 안의 카드들을 같은 조건으로 볼 수 있다.
