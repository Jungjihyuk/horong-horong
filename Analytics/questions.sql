-- Metabase native SQL question templates.
-- Create one Metabase question per block, then place them on the dashboard.

-- Dashboard tabs:
-- 1. 정확도 개요 / Accuracy Overview
-- 2. 신호 진단 / Signal Diagnosis
-- 3. 코멘트 & 동의 / Comments & Consent

-- ============================================================
-- Tab 1. 정확도 개요 / Accuracy Overview
-- ============================================================

-- KPI 1. 전체 판단 정확도 / Overall correctness
-- 추천 차트: Number. 첫 컬럼은 현재 30일 값, 두 번째 컬럼은 직전 30일 대비 변화량(%p).
with periods as (
  select
    case
      when created_at >= current_date - interval '30 days' then 'current'
      when created_at >= current_date - interval '60 days'
        and created_at < current_date - interval '30 days' then 'previous'
    end as period,
    verdict
  from public.analytics_attention_feedback_events
  where created_at >= current_date - interval '60 days'
),
summary as (
  select
    period,
    round(100 * count(*) filter (where verdict = 'correct')::numeric / nullif(count(*), 0), 1) as value
  from periods
  where period is not null
  group by period
)
select
  coalesce(max(value) filter (where period = 'current'), 0) as "전체 판단 정확도 %",
  coalesce(
    max(value) filter (where period = 'current') -
    max(value) filter (where period = 'previous'),
    0
  ) as "지난 30일 대비 %p"
from summary;

-- KPI 2. 일평균 피드백 수 / Average daily feedback count
-- 추천 차트: Number. 첫 컬럼은 현재 30일 값, 두 번째 컬럼은 직전 30일 대비 변화량.
with summary as (
  select
    case
      when created_at >= current_date - interval '30 days' then 'current'
      when created_at >= current_date - interval '60 days'
        and created_at < current_date - interval '30 days' then 'previous'
    end as period,
    count(*) as feedback_count,
    count(distinct event_day) as day_count
  from public.analytics_attention_feedback_events
  where created_at >= current_date - interval '60 days'
  group by period
),
values as (
  select
    period,
    round(feedback_count::numeric / nullif(day_count, 0), 1) as value
  from summary
  where period is not null
)
select
  coalesce(max(value) filter (where period = 'current'), 0) as "일평균 피드백 수",
  coalesce(
    max(value) filter (where period = 'current') -
    max(value) filter (where period = 'previous'),
    0
  ) as "지난 30일 대비"
from values;

-- KPI 3. 활성 설치 수 / Active install count
-- 추천 차트: Number. 첫 컬럼은 현재 30일 값, 두 번째 컬럼은 직전 30일 대비 변화량.
with values as (
  select
    case
      when created_at >= current_date - interval '30 days' then 'current'
      when created_at >= current_date - interval '60 days'
        and created_at < current_date - interval '30 days' then 'previous'
    end as period,
    count(distinct anonymous_install_id) as value
  from public.analytics_attention_feedback_events
  where created_at >= current_date - interval '60 days'
  group by period
)
select
  coalesce(max(value) filter (where period = 'current'), 0) as "활성 설치 수",
  coalesce(
    max(value) filter (where period = 'current') -
    max(value) filter (where period = 'previous'),
    0
  ) as "지난 30일 대비"
from values;

-- KPI 4. 애매해요 비율 / Unclear rate
-- 추천 차트: Number. 첫 컬럼은 현재 30일 값, 두 번째 컬럼은 직전 30일 대비 변화량(%p).
with periods as (
  select
    case
      when created_at >= current_date - interval '30 days' then 'current'
      when created_at >= current_date - interval '60 days'
        and created_at < current_date - interval '30 days' then 'previous'
    end as period,
    verdict
  from public.analytics_attention_feedback_events
  where created_at >= current_date - interval '60 days'
),
summary as (
  select
    period,
    round(100 * count(*) filter (where verdict = 'unclear')::numeric / nullif(count(*), 0), 1) as value
  from periods
  where period is not null
  group by period
)
select
  coalesce(max(value) filter (where period = 'current'), 0) as "애매해요 비율 %",
  coalesce(
    max(value) filter (where period = 'current') -
    max(value) filter (where period = 'previous'),
    0
  ) as "지난 30일 대비 %p"
from summary;

-- KPI 5. 아니에요 비율 / Wrong rate
-- 추천 차트: Number. 첫 컬럼은 현재 30일 값, 두 번째 컬럼은 직전 30일 대비 변화량(%p).
with periods as (
  select
    case
      when created_at >= current_date - interval '30 days' then 'current'
      when created_at >= current_date - interval '60 days'
        and created_at < current_date - interval '30 days' then 'previous'
    end as period,
    verdict
  from public.analytics_attention_feedback_events
  where created_at >= current_date - interval '60 days'
),
summary as (
  select
    period,
    round(100 * count(*) filter (where verdict = 'wrong')::numeric / nullif(count(*), 0), 1) as value
  from periods
  where period is not null
  group by period
)
select
  coalesce(max(value) filter (where period = 'current'), 0) as "아니에요 비율 %",
  coalesce(
    max(value) filter (where period = 'current') -
    max(value) filter (where period = 'previous'),
    0
  ) as "지난 30일 대비 %p"
from summary;

-- 1-1. 일별 피드백 수 / Daily feedback volume
-- 추천 차트: Bar chart 또는 Line chart. X축 event_day, Y축 feedback_count.
select
  event_day,
  count(*) as feedback_count
from public.analytics_attention_feedback_events
where created_at >= current_date - interval '30 days'
group by event_day
order by event_day;

-- 1-2. 일별 피드백 참여 기기 수 / Daily active feedback installs
-- 추천 차트: Line chart. X축 event_day, Y축 active_install_count.
select
  event_day,
  count(distinct anonymous_install_id) as active_install_count
from public.analytics_attention_feedback_events
where created_at >= current_date - interval '30 days'
group by event_day
order by event_day;

-- 1-3. 판단 분포 / Verdict distribution
-- 추천 차트: Donut chart 또는 Pie chart. label을 category, feedback_count를 value로 사용.
select
  case verdict
    when 'correct' then '맞아요'
    when 'unclear' then '애매해요'
    when 'wrong' then '아니에요'
    else verdict
  end as verdict_label,
  count(*) as feedback_count,
  round(100 * count(*)::numeric / sum(count(*)) over (), 1) as verdict_percent
from public.analytics_attention_feedback_events
where created_at >= current_date - interval '30 days'
group by verdict
order by feedback_count desc;

-- 1-4. 신호 유형별 피드백 분포 / Feedback distribution by signal type
-- 추천 차트: Pie chart 또는 Donut chart.
-- 어떤 신호 유형에 피드백이 집중되는지 빠르게 보는 카드입니다.
select
  signal_label as "신호 유형",
  count(*) as "피드백 수",
  round(100 * count(*)::numeric / sum(count(*)) over (), 1) as "비율"
from public.analytics_attention_feedback_events
where created_at >= current_date - interval '30 days'
group by signal_type, signal_label
order by "피드백 수" desc, signal_type;

-- ============================================================
-- Tab 2. 신호 진단 / Signal Diagnosis
-- ============================================================

-- 2-1. 신호 유형별 피드백 수 / Feedback volume by signal type
-- 추천 차트: Table.
-- 어떤 신호 유형에 대해 사용자가 가장 많이 피드백하는지 확인합니다.
select
  signal_label as "신호 유형",
  count(*) as "피드백 수",
  count(distinct anonymous_install_id) as "피드백 참여자 수",
  round(100 * count(*)::numeric / sum(count(*)) over (), 1) as "피드백 비중"
from public.analytics_attention_feedback_events
where created_at >= current_date - interval '30 days'
group by signal_type, signal_label
order by "피드백 수" desc, signal_type;

-- 2-2. 신호 유형별 판단 미흡률 / Unresolved judgment rate by signal type
-- 추천 차트: Bar chart 또는 Table.
-- `판단 미흡`은 사용자가 `애매해요(unclear)` 또는 `아니에요(wrong)`를 누른 건을 합산한 값입니다.
-- 어떤 신호 유형에서 앱의 해석이 가장 설득력이 떨어지는지 확인합니다.
select
  signal_label as "신호 유형",
  count(*) as "피드백 수",
  count(*) filter (where verdict = 'unclear') as "애매해요 수",
  count(*) filter (where verdict = 'wrong') as "아니에요 수",
  count(*) filter (where verdict in ('unclear', 'wrong')) as "판단 미흡 수",
  round(100 * count(*) filter (where verdict in ('unclear', 'wrong'))::numeric / nullif(count(*), 0), 1) as "판단 미흡률"
from public.analytics_attention_feedback_events
where created_at >= current_date - interval '30 days'
group by signal_type, signal_label
order by "판단 미흡률" desc, "피드백 수" desc, signal_type;

-- 2-3. 점수 구간별 판단 비율 / Verdict ratio by score bucket
-- 추천 차트: 100% stacked bar. X축 score_bucket, Y축 verdict_rate, series는 verdict_label.
select
  score_bucket,
  signal_type,
  '맞아요' as verdict_label,
  correct_count as verdict_count,
  correct_rate as verdict_rate
from public.analytics_attention_score_bucket_accuracy
union all
select
  score_bucket,
  signal_type,
  '애매해요' as verdict_label,
  unclear_count as verdict_count,
  round(unclear_count::numeric / nullif(feedback_count, 0), 4) as verdict_rate
from public.analytics_attention_score_bucket_accuracy
union all
select
  score_bucket,
  signal_type,
  '아니에요' as verdict_label,
  wrong_count as verdict_count,
  wrong_rate as verdict_rate
from public.analytics_attention_score_bucket_accuracy
order by score_bucket, signal_type, verdict_label;

-- 2-4. 피드백 위치별 판단 현황 / Verdict status by feedback location
-- 추천 차트: Table.
-- 문제라고 단정하지 않고, 어느 화면/기능에서 판정 피드백이 어떻게 들어오는지 봅니다.
select
  feedback_location as "피드백 위치",
  event_name as "이벤트",
  sum(feedback_count) as "피드백 수",
  sum(correct_count) as "맞아요 수",
  sum(unclear_count) as "애매해요 수",
  sum(wrong_count) as "아니에요 수",
  sum(unclear_count + wrong_count) as "판단 미흡 수",
  round(100 * sum(unclear_count + wrong_count)::numeric / nullif(sum(feedback_count), 0), 1) as "판단 미흡률"
from public.analytics_attention_feedback_location_summary
where feedback_count >= 1
group by feedback_location, event_name
order by "판단 미흡 수" desc, "피드백 수" desc, feedback_location;
