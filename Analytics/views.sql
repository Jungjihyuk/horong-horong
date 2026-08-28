-- HorongHorong feedback analytics views for Metabase.
-- Run this in Supabase SQL Editor after creating the feedback tables.
--
-- These are read-only analytics views. Dropping/recreating them does not delete
-- feedback_events, attention_feedback_details, or telemetry_consents data.
-- Existing views are dropped first because PostgreSQL cannot replace a view
-- when a new column is inserted before an existing column.

drop view if exists public.analytics_attention_comments_for_ai;
drop view if exists public.analytics_attention_score_bucket_accuracy;
drop view if exists public.analytics_attention_feedback_location_summary;
drop view if exists public.analytics_attention_threshold_satisfaction;
drop view if exists public.analytics_attention_signal_accuracy_weekly;
drop view if exists public.analytics_attention_signal_accuracy_daily;
drop view if exists public.analytics_attention_feedback_events;
drop view if exists public.analytics_telemetry_consent_daily;

create or replace view public.analytics_attention_feedback_events
with (security_invoker = true) as
select
  base.feedback_event_id,
  base.created_at,
  base.event_day,
  base.event_week,
  base.anonymous_install_id,
  base.app_version,
  base.os_version,
  base.event_name,
  base.feedback_location,
  base.source_feature,
  base.flow_state,
  base.raw_signal_type,
  base.signal_type,
  case base.signal_type
    when 'selective' then '선택적 주의'
    when 'sustained' then '지속적 주의'
    when 'switching' then '주의 전환'
    when 'general' then '종합/기타'
    when 'insufficient_data' then '데이터 부족'
    else base.signal_type
  end as signal_label,
  base.verdict,
  base.threshold_preset,
  base.score_bucket,
  base.comment_present,
  base.sanitized_comment
from (
  select
    e.id as feedback_event_id,
    e.created_at,
    date_trunc('day', e.created_at)::date as event_day,
    date_trunc('week', e.created_at)::date as event_week,
    e.anonymous_install_id,
    e.app_version,
    e.os_version,
    e.event_name,
    e.feedback_location,
    e.source_feature,
    d.flow_state,
    d.signal_type as raw_signal_type,
    case d.signal_type
      when 'selective' then 'selective'
      when 'sustained' then 'sustained'
      when 'switching' then 'switching'
      when 'return_delay' then 'switching'
      when 'delayed_return' then 'switching'
      when 'allowed_switch' then 'general'
      when 'none' then 'general'
      when 'declined_trend' then 'general'
      when 'improved_trend' then 'general'
      when 'steady_trend' then 'general'
      when 'monthly_pattern' then 'general'
      when 'no_dominant_signal' then 'general'
      when 'insufficient_data' then 'insufficient_data'
      else coalesce(d.signal_type, 'general')
    end as signal_type,
    d.verdict,
    d.threshold_preset,
    d.score_bucket,
    d.comment_present,
    d.sanitized_comment
  from public.feedback_events e
  join public.attention_feedback_details d
    on d.feedback_event_id = e.id
  where e.source_feature = 'attention'
) base;

create or replace view public.analytics_attention_signal_accuracy_daily
with (security_invoker = true) as
select
  event_day,
  signal_type,
  signal_label,
  count(*) as feedback_count,
  count(*) filter (where verdict = 'correct') as correct_count,
  count(*) filter (where verdict = 'wrong') as wrong_count,
  count(*) filter (where verdict = 'unclear') as unclear_count,
  count(*) filter (where verdict in ('unclear', 'wrong')) as unresolved_count,
  round(count(*) filter (where verdict = 'correct')::numeric / nullif(count(*), 0), 4) as correct_rate,
  round(count(*) filter (where verdict = 'wrong')::numeric / nullif(count(*), 0), 4) as wrong_rate,
  round(count(*) filter (where verdict = 'unclear')::numeric / nullif(count(*), 0), 4) as unclear_rate,
  round(count(*) filter (where verdict in ('unclear', 'wrong'))::numeric / nullif(count(*), 0), 4) as unresolved_rate,
  count(distinct anonymous_install_id) as active_install_count
from public.analytics_attention_feedback_events
group by event_day, signal_type, signal_label;

create or replace view public.analytics_attention_signal_accuracy_weekly
with (security_invoker = true) as
select
  event_week,
  signal_type,
  signal_label,
  count(*) as feedback_count,
  count(*) filter (where verdict = 'correct') as correct_count,
  count(*) filter (where verdict = 'wrong') as wrong_count,
  count(*) filter (where verdict = 'unclear') as unclear_count,
  count(*) filter (where verdict in ('unclear', 'wrong')) as unresolved_count,
  round(count(*) filter (where verdict = 'correct')::numeric / nullif(count(*), 0), 4) as correct_rate,
  round(count(*) filter (where verdict = 'wrong')::numeric / nullif(count(*), 0), 4) as wrong_rate,
  round(count(*) filter (where verdict = 'unclear')::numeric / nullif(count(*), 0), 4) as unclear_rate,
  round(count(*) filter (where verdict in ('unclear', 'wrong'))::numeric / nullif(count(*), 0), 4) as unresolved_rate,
  count(distinct anonymous_install_id) as active_install_count
from public.analytics_attention_feedback_events
group by event_week, signal_type, signal_label;

create or replace view public.analytics_attention_threshold_satisfaction
with (security_invoker = true) as
select
  threshold_preset,
  signal_type,
  signal_label,
  count(*) as feedback_count,
  count(*) filter (where verdict = 'correct') as correct_count,
  count(*) filter (where verdict = 'wrong') as wrong_count,
  count(*) filter (where verdict = 'unclear') as unclear_count,
  count(*) filter (where verdict in ('unclear', 'wrong')) as unresolved_count,
  round(count(*) filter (where verdict = 'correct')::numeric / nullif(count(*), 0), 4) as correct_rate,
  round(count(*) filter (where verdict = 'wrong')::numeric / nullif(count(*), 0), 4) as wrong_rate,
  round(count(*) filter (where verdict = 'unclear')::numeric / nullif(count(*), 0), 4) as unclear_rate,
  round(count(*) filter (where verdict in ('unclear', 'wrong'))::numeric / nullif(count(*), 0), 4) as unresolved_rate
from public.analytics_attention_feedback_events
group by threshold_preset, signal_type, signal_label;

create or replace view public.analytics_attention_feedback_location_summary
with (security_invoker = true) as
select
  feedback_location,
  event_name,
  signal_type,
  signal_label,
  count(*) as feedback_count,
  count(*) filter (where verdict = 'correct') as correct_count,
  count(*) filter (where verdict = 'wrong') as wrong_count,
  count(*) filter (where verdict = 'unclear') as unclear_count,
  count(*) filter (where verdict in ('unclear', 'wrong')) as unresolved_count,
  round(count(*) filter (where verdict = 'correct')::numeric / nullif(count(*), 0), 4) as correct_rate,
  round(count(*) filter (where verdict = 'unclear')::numeric / nullif(count(*), 0), 4) as unclear_rate,
  round(count(*) filter (where verdict = 'wrong')::numeric / nullif(count(*), 0), 4) as wrong_rate,
  round(count(*) filter (where verdict in ('unclear', 'wrong'))::numeric / nullif(count(*), 0), 4) as unresolved_rate
from public.analytics_attention_feedback_events
group by feedback_location, event_name, signal_type, signal_label;

create or replace view public.analytics_attention_score_bucket_accuracy
with (security_invoker = true) as
select
  score_bucket,
  signal_type,
  signal_label,
  count(*) as feedback_count,
  count(*) filter (where verdict = 'correct') as correct_count,
  count(*) filter (where verdict = 'wrong') as wrong_count,
  count(*) filter (where verdict = 'unclear') as unclear_count,
  count(*) filter (where verdict in ('unclear', 'wrong')) as unresolved_count,
  round(count(*) filter (where verdict = 'correct')::numeric / nullif(count(*), 0), 4) as correct_rate,
  round(count(*) filter (where verdict = 'wrong')::numeric / nullif(count(*), 0), 4) as wrong_rate,
  round(count(*) filter (where verdict = 'unclear')::numeric / nullif(count(*), 0), 4) as unclear_rate,
  round(count(*) filter (where verdict in ('unclear', 'wrong'))::numeric / nullif(count(*), 0), 4) as unresolved_rate
from public.analytics_attention_feedback_events
group by score_bucket, signal_type, signal_label;

create or replace view public.analytics_attention_comments_for_ai
with (security_invoker = true) as
select
  feedback_event_id,
  created_at,
  event_day,
  app_version,
  os_version,
  feedback_location,
  flow_state,
  raw_signal_type,
  signal_type,
  signal_label,
  verdict,
  threshold_preset,
  score_bucket,
  sanitized_comment
from public.analytics_attention_feedback_events
where comment_present = true
  and nullif(trim(sanitized_comment), '') is not null;

create or replace view public.analytics_telemetry_consent_daily
with (security_invoker = true) as
select
  date_trunc('day', created_at)::date as event_day,
  consent_scope,
  consent_status,
  count(*) as consent_event_count,
  count(distinct anonymous_install_id) as install_count
from public.telemetry_consents
group by event_day, consent_scope, consent_status;
