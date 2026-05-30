#!/usr/bin/env node | node ops/metabase/create-cards.mjs

import { readFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const envPath = join(scriptDir, ".env.local");

if (existsSync(envPath)) {
  const envFile = readFileSync(envPath, "utf8");

  for (const line of envFile.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const separatorIndex = trimmed.indexOf("=");
    if (separatorIndex === -1) continue;

    const key = trimmed.slice(0, separatorIndex).trim();
    const rawValue = trimmed.slice(separatorIndex + 1).trim();
    const value = rawValue.replace(/^['"]|['"]$/g, "");

    if (key && process.env[key] === undefined) {
      process.env[key] = value;
    }
  }
}

const required = ["METABASE_URL", "METABASE_EMAIL", "METABASE_PASSWORD", "METABASE_DATABASE_NAME"];
const missing = required.filter((key) => !process.env[key]);
const placeholders = [
  ["METABASE_EMAIL", "YOUR_METABASE_LOGIN_EMAIL"],
  ["METABASE_PASSWORD", "YOUR_METABASE_LOGIN_PASSWORD"],
].filter(([key, value]) => process.env[key] === value);

if (missing.length > 0) {
  console.error(`Missing required env vars: ${missing.join(", ")}`);
  console.error("");
  console.error("Usage:");
  console.error("METABASE_URL=http://localhost:3000 \\");
  console.error("METABASE_EMAIL='you@example.com' \\");
  console.error("METABASE_PASSWORD='your-metabase-password' \\");
  console.error("METABASE_DATABASE_NAME='Horong Supabase' \\");
  console.error("METABASE_DASHBOARD_ID='1' \\");
  console.error("node ops/metabase/create-cards.mjs");
  process.exit(1);
}

if (placeholders.length > 0) {
  console.error(`Replace placeholder values in ops/metabase/.env.local: ${placeholders.map(([key]) => key).join(", ")}`);
  process.exit(1);
}

const baseUrl = process.env.METABASE_URL.replace(/\/$/, "");
const rawDashboardId = process.env.METABASE_DASHBOARD_ID;
const dashboardId = rawDashboardId?.match(/^\d+/)?.[0];
const archivedCardNames = [
  "신호 유형별 주간 판단 비율",
  "기준치 프리셋별 만족도",
  "최근 코멘트와 AI 분석 후보",
  "익명 개선 데이터 동의 추이",
];

function columnSettings(fieldName, settings) {
  return {
    [`["name","${fieldName}"]`]: settings,
    [`["ref",["field","${fieldName}",{"base-type":"type/Decimal"}]]`]: settings,
  };
}

function scalarSettings(fieldName, settings = {}) {
  return {
    "scalar.field": fieldName,
    column_settings: columnSettings(fieldName, settings),
  };
}

function percentScalarSettings(fieldName, changeFieldName = "지난 30일 대비") {
  return {
    "scalar.field": fieldName,
    column_settings: {
      ...columnSettings(fieldName, {
        number_style: "decimal",
        decimals: 1,
        suffix: "%",
      }),
      ...columnSettings(changeFieldName, {
        number_style: "decimal",
        decimals: 1,
        suffix: "%p",
      }),
    },
  };
}

const cards = [
  {
    tab: "정확도 개요",
    name: "판단 일치율",
    aliases: ["기준 적중률", "전체 판단 정확도"],
    display: "scalar",
    visualizationSettings: percentScalarSettings("판단 일치율"),
    layout: { row: 0, col: 0, sizeX: 4, sizeY: 3 },
    query: `
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
  coalesce(max(value) filter (where period = 'current'), 0) as "판단 일치율",
  coalesce(
    max(value) filter (where period = 'current') -
    max(value) filter (where period = 'previous'),
    0
  ) as "지난 30일 대비"
from summary;
`.trim(),
  },
  {
    tab: "정확도 개요",
    name: "총 다운로드 수",
    aliases: ["관측 설치 수", "활성 설치 수"],
    display: "scalar",
    visualizationSettings: scalarSettings("총 다운로드 수", { decimals: 0 }),
    layout: { row: 0, col: 4, sizeX: 4, sizeY: 3 },
    query: `
with observed_installs as (
  select anonymous_install_id, created_at
  from public.analytics_attention_feedback_events
  union all
  select anonymous_install_id, created_at
  from public.telemetry_consents
),
values as (
  select
    case
      when created_at >= current_date - interval '30 days' then 'current'
      when created_at >= current_date - interval '60 days'
        and created_at < current_date - interval '30 days' then 'previous'
    end as period,
    count(distinct anonymous_install_id) as value
  from observed_installs
  where created_at >= current_date - interval '60 days'
  group by period
)
select
  coalesce(max(value) filter (where period = 'current'), 0) as "총 다운로드 수",
  coalesce(
    max(value) filter (where period = 'current') -
    max(value) filter (where period = 'previous'),
    0
  ) as "지난 30일 대비"
from values;
`.trim(),
  },
  {
    tab: "정확도 개요",
    name: "피드백 허용률",
    aliases: ["데이터 동의율", "애매해요 비율"],
    display: "scalar",
    visualizationSettings: percentScalarSettings("피드백 허용률"),
    layout: { row: 0, col: 8, sizeX: 4, sizeY: 3 },
    query: `
with observed_installs as (
  select distinct anonymous_install_id
  from public.analytics_attention_feedback_events
  union all
  select distinct anonymous_install_id
  from public.telemetry_consents
),
latest_current as (
  select distinct on (anonymous_install_id)
    anonymous_install_id,
    consent_status
  from public.telemetry_consents
  where created_at < current_date + interval '1 day'
  order by anonymous_install_id, created_at desc
),
latest_previous as (
  select distinct on (anonymous_install_id)
    anonymous_install_id,
    consent_status
  from public.telemetry_consents
  where created_at < current_date - interval '30 days'
  order by anonymous_install_id, created_at desc
),
allowed_current as (
  select anonymous_install_id
  from latest_current
  where consent_status = 'enabled'
  union
  select distinct anonymous_install_id
  from public.analytics_attention_feedback_events
),
allowed_previous as (
  select anonymous_install_id
  from latest_previous
  where consent_status = 'enabled'
  union
  select distinct anonymous_install_id
  from public.analytics_attention_feedback_events
  where created_at < current_date - interval '30 days'
),
values as (
  select
    'current' as period,
    round(100 * count(distinct a.anonymous_install_id)::numeric / nullif(count(distinct o.anonymous_install_id), 0), 1) as value
  from observed_installs o
  left join allowed_current a on a.anonymous_install_id = o.anonymous_install_id
  union all
  select
    'previous' as period,
    round(100 * count(distinct a.anonymous_install_id)::numeric / nullif(count(distinct o.anonymous_install_id), 0), 1) as value
  from observed_installs o
  left join allowed_previous a on a.anonymous_install_id = o.anonymous_install_id
)
select
  coalesce(max(value) filter (where period = 'current'), 0) as "피드백 허용률",
  coalesce(
    max(value) filter (where period = 'current') -
    max(value) filter (where period = 'previous'),
    0
  ) as "지난 30일 대비"
from values;
`.trim(),
  },
  {
    tab: "정확도 개요",
    name: "일평균 피드백 수",
    aliases: ["허용 설치당 일평균 피드백"],
    display: "scalar",
    visualizationSettings: scalarSettings("일평균 피드백 수", { decimals: 2 }),
    layout: { row: 0, col: 12, sizeX: 4, sizeY: 3 },
    query: `
with feedback_counts as (
  select
    case
      when created_at >= current_date - interval '30 days' then 'current'
      when created_at >= current_date - interval '60 days'
        and created_at < current_date - interval '30 days' then 'previous'
    end as period,
    count(*) as feedback_count
  from public.analytics_attention_feedback_events
  where created_at >= current_date - interval '60 days'
  group by period
),
values as (
  select
    period,
    round(feedback_count::numeric / 30, 2) as value
  from feedback_counts
)
select
  coalesce(max(value) filter (where period = 'current'), 0) as "일평균 피드백 수",
  coalesce(
    max(value) filter (where period = 'current') -
    max(value) filter (where period = 'previous'),
    0
  ) as "지난 30일 대비"
from values;
`.trim(),
  },
  {
    tab: "정확도 개요",
    name: "최근 30일 피드백 수",
    aliases: ["기준 불일치율", "아니에요 비율"],
    display: "scalar",
    visualizationSettings: scalarSettings("최근 30일 피드백 수", { decimals: 0 }),
    layout: { row: 0, col: 16, sizeX: 4, sizeY: 3 },
    query: `
with values as (
  select
    case
      when created_at >= current_date - interval '30 days' then 'current'
      when created_at >= current_date - interval '60 days'
        and created_at < current_date - interval '30 days' then 'previous'
    end as period,
    count(*) as value
  from public.analytics_attention_feedback_events
  where created_at >= current_date - interval '60 days'
  group by period
)
select
  coalesce(max(value) filter (where period = 'current'), 0) as "최근 30일 피드백 수",
  coalesce(
    max(value) filter (where period = 'current') -
    max(value) filter (where period = 'previous'),
    0
  ) as "지난 30일 대비"
from values;
`.trim(),
  },
  {
    tab: "정확도 개요",
    name: "일별 피드백 수",
    display: "bar",
    layout: { row: 3, col: 0, sizeX: 10, sizeY: 6 },
    query: `
select
  event_day as "날짜",
  count(*) as "피드백 수"
from public.analytics_attention_feedback_events
where created_at >= current_date - interval '30 days'
group by event_day
order by event_day;
`.trim(),
  },
  {
    tab: "정확도 개요",
    name: "일별 피드백 참여 기기 수",
    display: "line",
    layout: { row: 3, col: 10, sizeX: 10, sizeY: 6 },
    query: `
select
  event_day as "날짜",
  count(distinct anonymous_install_id) as "피드백 참여자 수"
from public.analytics_attention_feedback_events
where created_at >= current_date - interval '30 days'
group by event_day
order by event_day;
`.trim(),
  },
  {
    tab: "정확도 개요",
    name: "판단 분포",
    display: "pie",
    layout: { row: 9, col: 0, sizeX: 8, sizeY: 6 },
    query: `
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
`.trim(),
  },
  {
    tab: "정확도 개요",
    name: "신호 유형별 피드백 분포",
    aliases: ["신호 유형별 일별 판단 비율"],
    display: "pie",
    layout: { row: 9, col: 8, sizeX: 12, sizeY: 6 },
    query: `
select
  signal_label as "신호 유형",
  count(*) as "피드백 수",
  round(100 * count(*)::numeric / sum(count(*)) over (), 1) as "비율"
from public.analytics_attention_feedback_events
where created_at >= current_date - interval '30 days'
group by signal_type, signal_label
order by "피드백 수" desc, signal_type;
`.trim(),
  },
  {
    tab: "신호 진단",
    name: "신호 유형별 피드백 수",
    display: "table",
    layout: { row: 15, col: 0, sizeX: 10, sizeY: 6 },
    query: `
select
  signal_label as "신호 유형",
  count(*) as "피드백 수",
  count(distinct anonymous_install_id) as "피드백 참여자 수",
  round(100 * count(*)::numeric / sum(count(*)) over (), 1) as "피드백 비중"
from public.analytics_attention_feedback_events
where created_at >= current_date - interval '30 days'
group by signal_type, signal_label
order by "피드백 수" desc, signal_type;
`.trim(),
  },
  {
    tab: "신호 진단",
    name: "신호 유형별 판단 미흡률",
    display: "bar",
    visualizationSettings: {
      column_settings: columnSettings("판단 미흡률", {
        number_style: "decimal",
        decimals: 1,
        suffix: "%",
      }),
    },
    layout: { row: 15, col: 10, sizeX: 10, sizeY: 6 },
    query: `
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
`.trim(),
  },
  {
    tab: "신호 진단",
    name: "점수 구간별 판단 비율",
    display: "bar",
    layout: { row: 21, col: 0, sizeX: 10, sizeY: 6 },
    query: `
select
  score_bucket as "점수 구간",
  signal_label as "신호 유형",
  round(correct_rate * 100, 1) as "맞아요",
  round(unclear_rate * 100, 1) as "애매해요",
  round(wrong_rate * 100, 1) as "아니에요",
  feedback_count as "피드백 수"
from public.analytics_attention_score_bucket_accuracy
order by score_bucket, signal_type;
`.trim(),
  },
  {
    tab: "신호 진단",
    name: "피드백 위치별 판단 현황",
    aliases: ["문제 발생 위치 Top"],
    display: "table",
    layout: { row: 21, col: 10, sizeX: 10, sizeY: 6 },
    query: `
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
`.trim(),
  },
];

async function request(path, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(options.headers ?? {}),
    },
  });

  const text = await response.text();
  const body = text ? JSON.parse(text) : null;

  if (!response.ok) {
    const message = typeof body === "string" ? body : JSON.stringify(body, null, 2);
    throw new Error(`${options.method ?? "GET"} ${path} failed: ${response.status}\n${message}`);
  }

  return body;
}

async function findExistingCard(names, databaseId, authHeaders) {
  for (const name of names) {
    const result = await request(`/api/search?q=${encodeURIComponent(name)}`, {
      headers: authHeaders,
    });

    const items = Array.isArray(result) ? result : result.data ?? [];
    const card = items.find((item) =>
      item.model === "card" &&
      item.name === name &&
      item.database_id === databaseId &&
      item.archived === false
    );

    if (card) return card;
  }

  return undefined;
}

async function findAnyExistingCard(names, authHeaders) {
  for (const name of names) {
    const result = await request(`/api/search?q=${encodeURIComponent(name)}`, {
      headers: authHeaders,
    });

    const items = Array.isArray(result) ? result : result.data ?? [];
    const card = items.find((item) =>
      item.model === "card" &&
      item.name === name &&
      item.archived === false
    );

    if (card) return card;
  }

  return undefined;
}

function normalizeDashcard(dashcard) {
  return {
    id: dashcard.id,
    card_id: dashcard.card_id,
    row: dashcard.row,
    col: dashcard.col,
    size_x: dashcard.size_x,
    size_y: dashcard.size_y,
    parameter_mappings: dashcard.parameter_mappings ?? [],
    series: dashcard.series ?? [],
    inline_parameters: dashcard.inline_parameters ?? [],
    ...(dashcard.dashboard_tab_id ? { dashboard_tab_id: dashcard.dashboard_tab_id } : {}),
  };
}

async function updateCard(cardId, spec, databaseId, authHeaders) {
  await request(`/api/card/${cardId}`, {
    method: "PUT",
    headers: authHeaders,
    body: JSON.stringify({
      name: spec.name,
      display: spec.display,
      dataset_query: {
        type: "native",
        database: databaseId,
        native: {
          query: spec.query,
          "template-tags": {},
        },
      },
      visualization_settings: spec.visualizationSettings ?? {},
      description: `탭: ${spec.tab}`,
    }),
  });
}

async function main() {
  const session = await request("/api/session", {
    method: "POST",
    body: JSON.stringify({
      username: process.env.METABASE_EMAIL,
      password: process.env.METABASE_PASSWORD,
    }),
  });

  const authHeaders = { "X-Metabase-Session": session.id };

  const databaseResponse = await request("/api/database", { headers: authHeaders });
  const databases = Array.isArray(databaseResponse) ? databaseResponse : databaseResponse.data;
  const database = databases.find((item) => item.name === process.env.METABASE_DATABASE_NAME);

  if (!database) {
    console.error(`Database not found: ${process.env.METABASE_DATABASE_NAME}`);
    console.error(`Available databases: ${databases.map((item) => item.name).join(", ")}`);
    process.exit(1);
  }

  console.log(`Using database: ${database.name} (${database.id})`);

  const createdCards = [];

  for (const spec of cards) {
    const candidateNames = [spec.name, ...(spec.aliases ?? [])];
    const existingCard = await findExistingCard(candidateNames, database.id, authHeaders);

    if (existingCard) {
      console.log(`Using existing card: ${spec.name} (${existingCard.id})`);
      await updateCard(existingCard.id, spec, database.id, authHeaders);
      console.log(`Updated card query: ${spec.name} (${existingCard.id})`);
      createdCards.push({ ...spec, id: existingCard.id });
      continue;
    }

    const card = await request("/api/card", {
      method: "POST",
      headers: authHeaders,
      body: JSON.stringify({
        name: spec.name,
        display: spec.display,
        dataset_query: {
          type: "native",
          database: database.id,
          native: {
            query: spec.query,
            "template-tags": {},
          },
        },
        visualization_settings: spec.visualizationSettings ?? {},
        description: `탭: ${spec.tab}`,
      }),
    });

    console.log(`Created card: ${spec.name} (${card.id})`);
    createdCards.push({ ...spec, id: card.id });
  }

  if (!dashboardId) {
    console.log("");
    console.log("Cards created. METABASE_DASHBOARD_ID was not provided, so cards were not added to a dashboard.");
    console.log("Open Metabase and add these saved questions to your dashboard.");
    return;
  }

  const dashboard = await request(`/api/dashboard/${dashboardId}`, {
    headers: authHeaders,
  });

  if (dashboard.width !== "full") {
    await request(`/api/dashboard/${dashboardId}`, {
      method: "PUT",
      headers: authHeaders,
      body: JSON.stringify({
        ...dashboard,
        width: "full",
      }),
    });
    console.log(`Set dashboard width to full: ${dashboardId}`);
    dashboard.width = "full";
  }

  const existingDashcards = dashboard.dashcards ?? [];
  const existingCardIds = new Set(existingDashcards.map((dashcard) => dashcard.card_id));
  const archivedCardIds = new Set();
  for (const name of archivedCardNames) {
    const card = await findAnyExistingCard([name], authHeaders);
    if (!card) continue;
    archivedCardIds.add(card.id);
    await request(`/api/card/${card.id}`, {
      method: "PUT",
      headers: authHeaders,
      body: JSON.stringify({ archived: true }),
    });
    console.log(`Archived removed card: ${name} (${card.id})`);
  }

  const nextDashcards = existingDashcards
    .filter((dashcard) => !archivedCardIds.has(dashcard.card_id))
    .map(normalizeDashcard);
  let nextTemporaryId = -1;

  for (const card of createdCards) {
    if (existingCardIds.has(card.id)) {
      const dashcard = nextDashcards.find((item) => item.card_id === card.id);
      if (dashcard) {
        dashcard.row = card.layout.row;
        dashcard.col = card.layout.col;
        dashcard.size_x = card.layout.sizeX;
        dashcard.size_y = card.layout.sizeY;
      }
      console.log(`Already on dashboard ${dashboardId}, layout updated: ${card.name}`);
      continue;
    }

    nextDashcards.push({
      id: nextTemporaryId,
      card_id: card.id,
      row: card.layout.row,
      col: card.layout.col,
      size_x: card.layout.sizeX,
      size_y: card.layout.sizeY,
      parameter_mappings: [],
      series: [],
      inline_parameters: [],
    });
    nextTemporaryId -= 1;
    console.log(`Queued for dashboard ${dashboardId}: ${card.name}`);
  }

  await request(`/api/dashboard/${dashboardId}/cards`, {
    method: "PUT",
    headers: authHeaders,
    body: JSON.stringify({
      cards: nextDashcards,
      tabs: dashboard.tabs ?? [],
    }),
  });

  console.log("");
  console.log("Done.");
  console.log(`Dashboard updated: ${baseUrl}/dashboard/${dashboardId}`);
  console.log("Note: Metabase dashboard tabs and final layout may still need to be adjusted in the UI.");
  console.log("Use each card description field to see which tab it belongs to.");
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
