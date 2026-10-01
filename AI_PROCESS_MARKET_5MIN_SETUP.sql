-- ============================================================
-- AI PROCESS · 5분 시장현황 연동
-- GitHub + Supabase 기준
--
-- 대상 종목
--   STOCK  : TSLA / NVDA  (Yahoo Finance 5m chart)
--   CRYPTO : BTC / SOL    (Coinbase Exchange 5m candles)
--
-- 동작
--   1) Supabase가 외부 시장 데이터를 5분마다 수집
--   2) public.app_market_5m 에 최신 5분 변동률 저장
--   3) GitHub Pages는 이 테이블만 읽음
--   4) 프론트에서는 상승(change_pct > 0) 종목만 표시
--
-- 주의
--   - Yahoo Finance chart endpoint는 공개 웹 endpoint이지만 비공식 API 성격이므로
--     제공자 정책/응답 형식 변경 시 교체가 필요할 수 있습니다.
--   - 표시되는 '투자금 기준 환산' 금액은 시장 변동률 × 선택한 투자금의 단순 환산값이며,
--     실제 app_profit_logs 수익과 합산되지 않습니다.
-- ============================================================

begin;

create extension if not exists http with schema extensions;
create extension if not exists pg_cron;

create table if not exists public.app_market_5m (
  symbol text primary key,
  display_name text not null,
  asset_type text not null check (asset_type in ('stock','crypto')),
  source text not null,
  source_symbol text not null,
  currency text not null default 'USD',
  previous_price numeric,
  current_price numeric,
  change_pct numeric,
  bar_time timestamptz,
  refreshed_at timestamptz not null default now(),
  delay_seconds integer not null default 0,
  sort_order integer not null default 100,
  last_error text
);

alter table public.app_market_5m add column if not exists display_name text;
alter table public.app_market_5m add column if not exists asset_type text;
alter table public.app_market_5m add column if not exists source text;
alter table public.app_market_5m add column if not exists source_symbol text;
alter table public.app_market_5m add column if not exists currency text default 'USD';
alter table public.app_market_5m add column if not exists previous_price numeric;
alter table public.app_market_5m add column if not exists current_price numeric;
alter table public.app_market_5m add column if not exists change_pct numeric;
alter table public.app_market_5m add column if not exists bar_time timestamptz;
alter table public.app_market_5m add column if not exists refreshed_at timestamptz not null default now();
alter table public.app_market_5m add column if not exists delay_seconds integer not null default 0;
alter table public.app_market_5m add column if not exists sort_order integer not null default 100;
alter table public.app_market_5m add column if not exists last_error text;

alter table public.app_market_5m disable row level security;
grant select on public.app_market_5m to anon, authenticated;

-- HTTP GET + JSON helper. Yahoo 쪽에서 일반 브라우저 User-Agent를 요구하는 경우를 대비합니다.
create or replace function public.market_http_get_json(p_url text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_headers extensions.http_header[];
  v_request extensions.http_request;
  v_response extensions.http_response;
begin
  perform http_set_curlopt('CURLOPT_CONNECTTIMEOUT_MS', '5000');
  perform http_set_curlopt('CURLOPT_TIMEOUT_MS', '10000');

  v_headers := array[
    row('Accept','application/json')::extensions.http_header,
    row('User-Agent','Mozilla/5.0 (compatible; AI-Process-Market/1.0)')::extensions.http_header
  ];

  v_request := row(
    'GET',
    p_url,
    v_headers,
    null,
    null
  )::extensions.http_request;

  v_response := http(v_request);

  if v_response.status < 200 or v_response.status >= 300 then
    raise exception 'HTTP % for %', v_response.status, p_url;
  end if;

  return v_response.content::jsonb;
end;
$$;

create or replace function public.refresh_ai_market_5m()
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_symbol text;
  v_name text;
  v_source_symbol text;
  v_sort integer;
  v_json jsonb;
  v_result jsonb;
  v_prev numeric;
  v_curr numeric;
  v_pct numeric;
  v_ts bigint;
  v_ord bigint;
  v_delay integer;
  v_ok integer := 0;
begin
  -- ----------------------------------------------------------
  -- STOCK: Yahoo Finance 5-minute chart
  -- ----------------------------------------------------------
  for v_symbol, v_name, v_source_symbol, v_sort in
    select * from (values
      ('TSLA'::text, 'Tesla'::text,  'TSLA'::text, 10),
      ('NVDA'::text, 'NVIDIA'::text, 'NVDA'::text, 20)
    ) as x(symbol, display_name, source_symbol, sort_order)
  loop
    begin
      v_json := public.market_http_get_json(
        'https://query1.finance.yahoo.com/v8/finance/chart/' || v_source_symbol ||
        '?interval=5m&range=1d&includePrePost=false&events=div%2Csplits'
      );

      v_result := v_json #> '{chart,result,0}';
      if v_result is null then
        raise exception 'Yahoo response has no chart result';
      end if;

      select q.ord, q.ts_value, q.close_value
        into v_ord, v_ts, v_curr
      from (
        select
          ts.ord::bigint as ord,
          (ts.value::text)::bigint as ts_value,
          (cl.value::text)::numeric as close_value
        from jsonb_array_elements(v_result->'timestamp') with ordinality as ts(value, ord)
        join jsonb_array_elements(v_result #> '{indicators,quote,0,close}') with ordinality as cl(value, ord)
          on cl.ord = ts.ord
        where cl.value <> 'null'::jsonb
        order by ts.ord desc
        limit 1
      ) q;

      if v_ord is null or v_curr is null then
        raise exception 'Yahoo response has no usable close price';
      end if;

      select (cl.value::text)::numeric
        into v_prev
      from jsonb_array_elements(v_result #> '{indicators,quote,0,close}') with ordinality as cl(value, ord)
      where cl.value <> 'null'::jsonb
        and cl.ord < v_ord
      order by cl.ord desc
      limit 1;

      if v_prev is null or v_prev = 0 then
        raise exception 'Yahoo response has no previous 5m close';
      end if;

      v_pct := ((v_curr - v_prev) / v_prev) * 100.0;
      v_delay := coalesce((v_result #>> '{meta,exchangeDataDelayedBy}')::integer, 0);

      insert into public.app_market_5m(
        symbol, display_name, asset_type, source, source_symbol, currency,
        previous_price, current_price, change_pct, bar_time, refreshed_at,
        delay_seconds, sort_order, last_error
      ) values (
        v_symbol, v_name, 'stock', 'Yahoo Finance', v_source_symbol, 'USD',
        v_prev, v_curr, v_pct, to_timestamp(v_ts), now(),
        v_delay, v_sort, null
      )
      on conflict (symbol) do update set
        display_name = excluded.display_name,
        asset_type = excluded.asset_type,
        source = excluded.source,
        source_symbol = excluded.source_symbol,
        currency = excluded.currency,
        previous_price = excluded.previous_price,
        current_price = excluded.current_price,
        change_pct = excluded.change_pct,
        bar_time = excluded.bar_time,
        refreshed_at = excluded.refreshed_at,
        delay_seconds = excluded.delay_seconds,
        sort_order = excluded.sort_order,
        last_error = null;

      v_ok := v_ok + 1;
    exception when others then
      insert into public.app_market_5m(
        symbol, display_name, asset_type, source, source_symbol, currency,
        refreshed_at, sort_order, last_error
      ) values (
        v_symbol, v_name, 'stock', 'Yahoo Finance', v_source_symbol, 'USD',
        now(), v_sort, left(sqlerrm, 500)
      )
      on conflict (symbol) do update set
        display_name = excluded.display_name,
        asset_type = excluded.asset_type,
        source = excluded.source,
        source_symbol = excluded.source_symbol,
        refreshed_at = excluded.refreshed_at,
        sort_order = excluded.sort_order,
        last_error = excluded.last_error;
    end;
  end loop;

  -- ----------------------------------------------------------
  -- CRYPTO: Coinbase Exchange 5-minute candles
  -- ----------------------------------------------------------
  for v_symbol, v_name, v_source_symbol, v_sort in
    select * from (values
      ('BTC'::text, 'Bitcoin'::text, 'BTC-USD'::text, 30),
      ('SOL'::text, 'Solana'::text,  'SOL-USD'::text, 40)
    ) as x(symbol, display_name, source_symbol, sort_order)
  loop
    begin
      v_json := public.market_http_get_json(
        'https://api.exchange.coinbase.com/products/' || v_source_symbol || '/candles?granularity=300'
      );

      if jsonb_typeof(v_json) <> 'array' or jsonb_array_length(v_json) < 2 then
        raise exception 'Coinbase response has fewer than 2 candles';
      end if;

      select
        (c.value->>0)::bigint,
        (c.value->>4)::numeric
      into v_ts, v_curr
      from jsonb_array_elements(v_json) as c(value)
      order by (c.value->>0)::bigint desc
      limit 1;

      select (c.value->>4)::numeric
      into v_prev
      from jsonb_array_elements(v_json) as c(value)
      where (c.value->>0)::bigint < v_ts
      order by (c.value->>0)::bigint desc
      limit 1;

      if v_prev is null or v_prev = 0 or v_curr is null then
        raise exception 'Coinbase response has invalid close price';
      end if;

      v_pct := ((v_curr - v_prev) / v_prev) * 100.0;

      insert into public.app_market_5m(
        symbol, display_name, asset_type, source, source_symbol, currency,
        previous_price, current_price, change_pct, bar_time, refreshed_at,
        delay_seconds, sort_order, last_error
      ) values (
        v_symbol, v_name, 'crypto', 'Coinbase', v_source_symbol, 'USD',
        v_prev, v_curr, v_pct, to_timestamp(v_ts), now(),
        0, v_sort, null
      )
      on conflict (symbol) do update set
        display_name = excluded.display_name,
        asset_type = excluded.asset_type,
        source = excluded.source,
        source_symbol = excluded.source_symbol,
        currency = excluded.currency,
        previous_price = excluded.previous_price,
        current_price = excluded.current_price,
        change_pct = excluded.change_pct,
        bar_time = excluded.bar_time,
        refreshed_at = excluded.refreshed_at,
        delay_seconds = excluded.delay_seconds,
        sort_order = excluded.sort_order,
        last_error = null;

      v_ok := v_ok + 1;
    exception when others then
      insert into public.app_market_5m(
        symbol, display_name, asset_type, source, source_symbol, currency,
        refreshed_at, sort_order, last_error
      ) values (
        v_symbol, v_name, 'crypto', 'Coinbase', v_source_symbol, 'USD',
        now(), v_sort, left(sqlerrm, 500)
      )
      on conflict (symbol) do update set
        display_name = excluded.display_name,
        asset_type = excluded.asset_type,
        source = excluded.source,
        source_symbol = excluded.source_symbol,
        refreshed_at = excluded.refreshed_at,
        sort_order = excluded.sort_order,
        last_error = excluded.last_error;
    end;
  end loop;

  return v_ok;
end;
$$;

revoke execute on function public.market_http_get_json(text) from public, anon, authenticated;
revoke execute on function public.refresh_ai_market_5m() from public, anon, authenticated;

-- Realtime publication은 중복 등록 시 예외를 무시합니다.
do $$
begin
  begin
    alter publication supabase_realtime add table public.app_market_5m;
  exception
    when duplicate_object then null;
  end;
end $$;

-- 기존 동일 이름 잡 제거 후 5분마다 갱신
-- (시장 데이터만 담당. 기존 수익 지급 cron은 건드리지 않습니다.)
do $$
declare
  j record;
begin
  for j in
    select jobid from cron.job where jobname = 'ai-market-pulse-5m'
  loop
    perform cron.unschedule(j.jobid);
  end loop;
end $$;

select cron.schedule(
  'ai-market-pulse-5m',
  '*/5 * * * *',
  $$select public.refresh_ai_market_5m();$$
);

commit;

-- 최초 1회 즉시 수집
select public.refresh_ai_market_5m() as refreshed_symbols;

-- 확인
select
  symbol, display_name, asset_type, source,
  previous_price, current_price,
  round(change_pct, 4) as change_pct,
  bar_time, refreshed_at, delay_seconds, last_error
from public.app_market_5m
order by sort_order;

select jobid, jobname, schedule, command, active
from cron.job
where jobname = 'ai-market-pulse-5m';
