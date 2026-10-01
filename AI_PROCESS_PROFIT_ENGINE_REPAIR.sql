-- ============================================================
-- AI PROCESS · PROFIT ENGINE REPAIR
-- GitHub + Supabase V4 후속 수정
-- 목적: 진행중 AI 프로세스에서 자동 수익/손실 로그가 다시 발생하도록
--       기존 데이터는 유지하면서 지급 엔진/cron/필수 컬럼만 복구합니다.
--
-- 기준
-- - 진행 기간 UI/운영 기준: 최소 1시간 ~ 최대 30일
-- - 자동 종료하지 않음 (관리자 수동 종료 유지)
-- - 각 투자별 last_payout_at 기준 독립 주기
-- - app_profit_logs source_type = 'process_payout'
-- - 기존 app_users / app_investments 데이터 삭제 없음
-- ============================================================

create extension if not exists pgcrypto;
create extension if not exists pg_cron;

-- ------------------------------------------------------------
-- 1) 기존 사용자 테이블에서 지급 함수가 사용하는 최소 컬럼 보장
-- ------------------------------------------------------------
alter table public.app_users add column if not exists approved boolean not null default false;
alter table public.app_users add column if not exists realized_amount numeric not null default 0;
alter table public.app_users add column if not exists updated_at timestamptz not null default now();

-- ------------------------------------------------------------
-- 2) 자동지급 설정: 기존 값은 보존, 없는 컬럼/행만 보완
-- ------------------------------------------------------------
create table if not exists public.app_payout_settings (
  id int primary key default 1,
  enabled boolean not null default true,
  every_minutes int not null default 9,
  start_hour int not null default 0,
  end_hour int not null default 23,
  min_rate numeric not null default 0.0035,
  max_rate numeric not null default 0.0105,
  profit_min_rate numeric not null default 0.0035,
  profit_max_rate numeric not null default 0.0105,
  loss_min_rate numeric not null default 0.0004,
  loss_max_rate numeric not null default 0.0030,
  profit_probability numeric not null default 85,
  loss_probability numeric not null default 15,
  profit_chance numeric not null default 85,
  loss_chance numeric not null default 15,
  daily_user_cap numeric not null default 999999999999,
  daily_system_cap numeric not null default 999999999999,
  max_single_payout numeric not null default 999999999999,
  updated_at timestamptz not null default now()
);

alter table public.app_payout_settings add column if not exists enabled boolean not null default true;
alter table public.app_payout_settings add column if not exists every_minutes int not null default 9;
alter table public.app_payout_settings add column if not exists start_hour int not null default 0;
alter table public.app_payout_settings add column if not exists end_hour int not null default 23;
alter table public.app_payout_settings add column if not exists min_rate numeric not null default 0.0035;
alter table public.app_payout_settings add column if not exists max_rate numeric not null default 0.0105;
alter table public.app_payout_settings add column if not exists profit_min_rate numeric not null default 0.0035;
alter table public.app_payout_settings add column if not exists profit_max_rate numeric not null default 0.0105;
alter table public.app_payout_settings add column if not exists loss_min_rate numeric not null default 0.0004;
alter table public.app_payout_settings add column if not exists loss_max_rate numeric not null default 0.0030;
alter table public.app_payout_settings add column if not exists profit_probability numeric not null default 85;
alter table public.app_payout_settings add column if not exists loss_probability numeric not null default 15;
alter table public.app_payout_settings add column if not exists profit_chance numeric not null default 85;
alter table public.app_payout_settings add column if not exists loss_chance numeric not null default 15;
alter table public.app_payout_settings add column if not exists daily_user_cap numeric not null default 999999999999;
alter table public.app_payout_settings add column if not exists daily_system_cap numeric not null default 999999999999;
alter table public.app_payout_settings add column if not exists max_single_payout numeric not null default 999999999999;
alter table public.app_payout_settings add column if not exists updated_at timestamptz not null default now();

insert into public.app_payout_settings(id)
values (1)
on conflict (id) do nothing;

-- 이번 수정 목적이 '진행 중인데 지급이 전혀 안 됨'이므로 엔진은 ON으로 복구.
-- 지급 간격/확률/비율 등 기존 관리자 설정값은 덮어쓰지 않습니다.
update public.app_payout_settings
set enabled = true,
    updated_at = now()
where id = 1;

alter table public.app_payout_settings disable row level security;

-- ------------------------------------------------------------
-- 3) 투자 테이블의 자동지급 필수 컬럼 보장
-- ------------------------------------------------------------
create table if not exists public.app_investments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users(id) on delete cascade,
  processor_code text,
  amount numeric not null default 0,
  realized_amount numeric not null default 0,
  duration_minutes int,
  target_return_pct numeric,
  assigned_return_pct numeric,
  target_profit_amount numeric,
  is_indefinite boolean not null default false,
  status text not null default '대기중',
  started_at timestamptz,
  ends_at timestamptz,
  completed_at timestamptz,
  last_payout_at timestamptz,
  payout_count int not null default 0,
  loss_count int not null default 0,
  return_profile numeric,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.app_investments add column if not exists realized_amount numeric not null default 0;
alter table public.app_investments add column if not exists started_at timestamptz;
alter table public.app_investments add column if not exists last_payout_at timestamptz;
alter table public.app_investments add column if not exists payout_count int not null default 0;
alter table public.app_investments add column if not exists loss_count int not null default 0;
alter table public.app_investments add column if not exists return_profile numeric;
alter table public.app_investments add column if not exists updated_at timestamptz not null default now();

update public.app_investments
set return_profile = random()
where return_profile is null;

alter table public.app_investments alter column return_profile set default random();
alter table public.app_investments alter column return_profile set not null;

-- 진행중인데 started_at이 비어 있으면 과거 수익을 소급하지 않고 지금부터 시작.
update public.app_investments
set started_at = now(),
    updated_at = now()
where status = '진행중'
  and started_at is null;

create index if not exists app_investments_due_idx
  on public.app_investments(status, last_payout_at);

alter table public.app_investments disable row level security;

-- ------------------------------------------------------------
-- 4) 투자금 트랜치 로그 / 수익 로그 보장
-- ------------------------------------------------------------
create table if not exists public.app_investment_amount_logs (
  id uuid primary key default gen_random_uuid(),
  investment_id uuid not null references public.app_investments(id) on delete cascade,
  user_id uuid references public.app_users(id) on delete cascade,
  delta numeric not null default 0,
  note text,
  created_at timestamptz not null default now()
);

create index if not exists app_investment_amount_logs_inv_created_idx
  on public.app_investment_amount_logs(investment_id, created_at desc);

alter table public.app_investment_amount_logs disable row level security;

create table if not exists public.app_profit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.app_users(id) on delete cascade,
  investment_id uuid references public.app_investments(id) on delete cascade,
  amount_delta numeric not null default 0,
  source_type text not null default 'process_payout',
  source_id uuid,
  created_at timestamptz not null default now()
);

alter table public.app_profit_logs add column if not exists investment_id uuid;
alter table public.app_profit_logs add column if not exists source_type text default 'process_payout';
alter table public.app_profit_logs add column if not exists source_id uuid;
alter table public.app_profit_logs add column if not exists created_at timestamptz not null default now();

create index if not exists app_profit_logs_user_created_idx
  on public.app_profit_logs(user_id, created_at desc);
create index if not exists app_profit_logs_investment_created_idx
  on public.app_profit_logs(investment_id, created_at desc);
create index if not exists app_profit_logs_source_type_idx
  on public.app_profit_logs(source_type);

alter table public.app_profit_logs disable row level security;

-- 초기 투자금 로그가 빠진 기존 투자만 1회 백필.
insert into public.app_investment_amount_logs(
  investment_id, user_id, delta, note, created_at
)
select
  i.id,
  i.user_id,
  i.amount,
  '기존 투자 기준금',
  coalesce(i.started_at, now())
from public.app_investments i
where i.amount > 0
  and not exists (
    select 1
    from public.app_investment_amount_logs l
    where l.investment_id = i.id
  );

-- ------------------------------------------------------------
-- 5) 1시간~30일 시간곡선 함수 복구
-- 아래 3개 함수는 프로젝트에서 마지막으로 사용하던 weighted time-curve 기준.
-- ------------------------------------------------------------
create or replace function public.ai_process_return_band(
  p_elapsed_hours numeric,
  out min_pct numeric,
  out max_pct numeric
)
returns record
language plpgsql
immutable
as $$
declare
  h numeric := greatest(0, least(coalesce(p_elapsed_hours,0), 720));
  t numeric;
begin
  if h <= 0 then
    min_pct := 0;
    max_pct := 0;

  elsif h <= 0.9 then
    t := h / 0.9;
    min_pct := 10 * t;
    max_pct := 12 * t;

  elsif h <= 1 then
    min_pct := 10;
    max_pct := 12;

  elsif h <= 3 then
    t := (h - 1) / 2;
    min_pct := 10 + (21 - 10) * t;
    max_pct := 12 + (28 - 12) * t;

  elsif h <= 6 then
    t := (h - 3) / 3;
    min_pct := 21 + (34 - 21) * t;
    max_pct := 28 + (48 - 28) * t;

  elsif h <= 12 then
    t := (h - 6) / 6;
    min_pct := 34 + (55 - 34) * t;
    max_pct := 48 + (80 - 48) * t;

  elsif h <= 24 then
    t := (h - 12) / 12;
    min_pct := 55 + (85 - 55) * t;
    max_pct := 80 + (140 - 80) * t;

  elsif h <= 72 then
    t := (h - 24) / 48;
    min_pct := 85 + (180 - 85) * t;
    max_pct := 140 + (330 - 140) * t;

  elsif h <= 168 then
    t := (h - 72) / 96;
    min_pct := 180 + (300 - 180) * t;
    max_pct := 330 + (650 - 330) * t;

  elsif h <= 336 then
    t := (h - 168) / 168;
    min_pct := 300 + (450 - 300) * t;
    max_pct := 650 + (1050 - 650) * t;

  elsif h <= 504 then
    t := (h - 336) / 168;
    min_pct := 450 + (550 - 450) * t;
    max_pct := 1050 + (1450 - 1050) * t;

  else
    t := (h - 504) / 216;
    min_pct := 550 + (800 - 550) * t;
    max_pct := 1450 + (1800 - 1450) * t;
  end if;

  min_pct := round(min_pct, 6);
  max_pct := round(max_pct, 6);
end;
$$;


-- ============================================================
-- 10. 투자별 profile을 적용한 누적 기준 수익률
-- profile 0 = 해당 시간대 낮은 쪽
-- profile 1 = 해당 시간대 높은 쪽
-- ============================================================

create or replace function public.ai_process_target_pct(
  p_elapsed_hours numeric,
  p_profile numeric
)
returns numeric
language plpgsql
immutable
as $$
declare
  v_min numeric;
  v_max numeric;
  v_h numeric := greatest(0, least(coalesce(p_elapsed_hours,0), 720));
  v_raw_profile numeric := greatest(0, least(coalesce(p_profile,0.5), 1));
  v_profile_strength numeric;
  v_profile numeric;
  v_t numeric;
begin
  select min_pct, max_pct
  into v_min, v_max
  from public.ai_process_return_band(v_h);

  -- 단기에는 '진행 시간'을 우선한다.
  -- 3일까지는 return_profile이 시간을 압도하지 않도록 중앙 목표를 사용.
  -- 3일 이후부터 기간이 길어질수록 계정별 편차를 점진적으로 확대.
  if v_h <= 72 then
    v_profile_strength := 0;

  elsif v_h <= 168 then
    v_t := (v_h - 72) / 96;
    v_profile_strength := 0.35 * v_t;

  elsif v_h <= 336 then
    v_t := (v_h - 168) / 168;
    v_profile_strength := 0.35 + (0.65 - 0.35) * v_t;

  elsif v_h <= 504 then
    v_t := (v_h - 336) / 168;
    v_profile_strength := 0.65 + (0.85 - 0.65) * v_t;

  else
    v_t := (v_h - 504) / 216;
    v_profile_strength := 0.85 + (1.00 - 0.85) * v_t;
  end if;

  v_profile :=
    0.5
    + (v_raw_profile - 0.5)
    * greatest(0, least(v_profile_strength,1));

  return round(
    v_min + (v_max - v_min) * v_profile,
    8
  );
end;
$$;

-- ============================================================
-- 진행시간 가중치
-- 같은 투자금이면 진행 시간이 길수록 양(+) 지급 강도가 커짐.
-- 누적값은 기존 시간대별 허용 밴드 안에서 계속 제어됨.
-- ============================================================

create or replace function public.ai_process_age_weight(
  p_elapsed_hours numeric
)
returns numeric
language plpgsql
immutable
as $$
declare
  h numeric := greatest(0, least(coalesce(p_elapsed_hours,0), 720));
  t numeric;
begin
  if h <= 1 then
    return 1.00;

  elsif h <= 6 then
    t := (h - 1) / 5;
    return 1.00 + (1.08 - 1.00) * t;

  elsif h <= 24 then
    t := (h - 6) / 18;
    return 1.08 + (1.25 - 1.08) * t;

  elsif h <= 72 then
    t := (h - 24) / 48;
    return 1.25 + (2.20 - 1.25) * t;

  elsif h <= 168 then
    t := (h - 72) / 96;
    return 2.20 + (2.65 - 2.20) * t;

  elsif h <= 336 then
    t := (h - 168) / 168;
    return 2.65 + (3.00 - 2.65) * t;

  elsif h <= 504 then
    t := (h - 336) / 168;
    return 3.00 + (3.25 - 3.00) * t;

  else
    t := (h - 504) / 216;
    return 3.25 + (3.50 - 3.25) * t;
  end if;
end;
$$;

-- ------------------------------------------------------------
-- 6) 자동 수익/손실 지급 엔진 복구
-- ------------------------------------------------------------
create or replace function public.run_multi_investment_payouts()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  inv record;
  cfg record;

  v_now timestamptz := now();
  v_interval int;

  v_prev_time timestamptz;

  v_elapsed_hours numeric;
  v_prev_elapsed_hours numeric;

  v_target_now numeric;
  v_target_prev numeric;

  v_band_min_pct numeric;
  v_band_max_pct numeric;

  v_band_min_amount numeric;
  v_band_max_amount numeric;

  v_base_target_step numeric;
  v_gap numeric;

  v_profit boolean;
  v_delta numeric;

  v_profit_mult numeric;
  v_loss_mult numeric;

  v_expected_factor numeric;
  v_age_weight numeric;

  v_projected numeric;

  v_count integer := 0;
begin
  select *
  into cfg
  from public.app_payout_settings
  where id = 1;

  if cfg is null then
    return 0;
  end if;

  if coalesce(cfg.enabled,false) = false then
    return 0;
  end if;

  v_interval := greatest(1, coalesce(cfg.every_minutes,9));

  for inv in
    select i.*
    from public.app_investments i
    join public.app_users u
      on u.id = i.user_id
    where i.status = '진행중'
      and u.approved = true
      and i.amount > 0
      and i.started_at is not null
    order by i.created_at
    for update of i skip locked
  loop

    -- 아직 설정된 지급 간격(every_minutes)이 지나지 않았으면 건너뜀
    if inv.last_payout_at is not null
       and v_now < inv.last_payout_at + make_interval(mins => v_interval) then
      continue;
    end if;

    v_prev_time :=
      coalesce(inv.last_payout_at, inv.started_at);

    v_elapsed_hours :=
      greatest(
        0,
        extract(epoch from (v_now - inv.started_at)) / 3600.0
      );

    v_prev_elapsed_hours :=
      greatest(
        0,
        extract(epoch from (v_prev_time - inv.started_at)) / 3600.0
      );

    -- 진행 시간이 길수록 양(+) 지급 강도를 높이는 시간 가중치
    v_age_weight :=
      public.ai_process_age_weight(v_elapsed_hours);

    -- ----------------------------------------------------------
    -- 투자금 트랜치별 목표수익 합산
    -- 추가 투자금은 추가된 시점부터 자기 시간곡선 시작
    -- ----------------------------------------------------------

    select
      coalesce(
        sum(
          greatest(l.delta,0)
          *
          public.ai_process_target_pct(
            greatest(
              0,
              extract(epoch from (v_now - l.created_at)) / 3600.0
            ),
            inv.return_profile
          )
          / 100.0
        ),
        0
      )
    into v_target_now
    from public.app_investment_amount_logs l
    where l.investment_id = inv.id
      and l.delta > 0;

    select
      coalesce(
        sum(
          greatest(l.delta,0)
          *
          public.ai_process_target_pct(
            greatest(
              0,
              extract(epoch from (v_prev_time - l.created_at)) / 3600.0
            ),
            inv.return_profile
          )
          / 100.0
        ),
        0
      )
    into v_target_prev
    from public.app_investment_amount_logs l
    where l.investment_id = inv.id
      and l.delta > 0;

    -- 기존 투자 중 amount log가 특이하게 비어있는 경우 안전 fallback
    if v_target_now = 0 and inv.amount > 0 then
      v_target_now :=
        inv.amount
        * public.ai_process_target_pct(
            v_elapsed_hours,
            inv.return_profile
          )
        / 100.0;

      v_target_prev :=
        inv.amount
        * public.ai_process_target_pct(
            v_prev_elapsed_hours,
            inv.return_profile
          )
        / 100.0;
    end if;

    v_base_target_step :=
      greatest(
        0.01,
        v_target_now - v_target_prev
      );

    v_gap :=
      v_target_now
      - coalesce(inv.realized_amount,0);

    -- ----------------------------------------------------------
    -- 현재 시간대 전체 허용 밴드 금액 계산
    -- short = 좁음 / long = 넓음
    -- ----------------------------------------------------------

    select min_pct, max_pct
    into v_band_min_pct, v_band_max_pct
    from public.ai_process_return_band(v_elapsed_hours);

    -- 현재 총액에 대한 단순 밴드.
    -- 추가투자가 있는 경우 실제 target은 위 트랜치 방식이 더 정확함.
    v_band_min_amount :=
      inv.amount * v_band_min_pct / 100.0;

    v_band_max_amount :=
      inv.amount * v_band_max_pct / 100.0;

    -- ----------------------------------------------------------
    -- 랜덤 변동폭
    -- 짧은 시간은 작게, 장기일수록 크게
    -- ----------------------------------------------------------

    if v_elapsed_hours <= 1 then
      v_profit_mult := 0.90 + random() * 0.20; -- 0.90 ~ 1.10
      v_loss_mult   := 0.05 + random() * 0.07; -- 0.05 ~ 0.12
      v_expected_factor := 0.83725;

    elsif v_elapsed_hours <= 6 then
      v_profit_mult := 0.80 + random() * 0.40; -- 0.80 ~ 1.20
      v_loss_mult   := 0.06 + random() * 0.10; -- 0.06 ~ 0.16
      v_expected_factor := 0.8335;

    elsif v_elapsed_hours <= 24 then
      v_profit_mult := 0.70 + random() * 0.60; -- 0.70 ~ 1.30
      v_loss_mult   := 0.08 + random() * 0.14; -- 0.08 ~ 0.22
      v_expected_factor := 0.8275;

    elsif v_elapsed_hours <= 168 then
      v_profit_mult := 0.60 + random() * 0.90; -- 0.60 ~ 1.50
      v_loss_mult   := 0.08 + random() * 0.22; -- 0.08 ~ 0.30
      v_expected_factor := 0.8615;

    else
      v_profit_mult := 0.45 + random() * 1.35; -- 0.45 ~ 1.80
      v_loss_mult   := 0.10 + random() * 0.35; -- 0.10 ~ 0.45
      v_expected_factor := 0.914625;
    end if;

    -- ----------------------------------------------------------
    -- 기본 85 / 15
    -- 단, 기준곡선보다 너무 낮으면 보정 수익 허용
    -- ----------------------------------------------------------

    if v_gap > v_base_target_step * 2.0 then
      -- 시간곡선보다 뒤처져 있으면 수익 쪽으로 우선 보정
      v_profit := true;

    elsif v_gap < -v_base_target_step * 6.0 then
      -- 시간곡선보다 많이 앞서 있으면 일시적으로 속도를 낮춤
      v_profit := random() < 0.55;

    else
      -- 기본 설정값(기본 85 / 15)
      v_profit :=
        random()
        <
        (
          coalesce(cfg.profit_probability,85)::numeric
          /
          greatest(
            1,
            coalesce(cfg.profit_probability,85)
            +
            coalesce(cfg.loss_probability,15)
          )
        );
    end if;

    -- ----------------------------------------------------------
    -- 회당 기준값
    -- target step을 85/15 기대값으로 역산
    -- gap의 일부만 천천히 보정
    -- ----------------------------------------------------------

    v_base_target_step :=
      greatest(
        0.01,
        (
          v_base_target_step
          +
          greatest(
            -v_base_target_step * 0.90,
            least(
              v_base_target_step * 1.75,
              v_gap * case
                when v_elapsed_hours <= 1 then 0.35
                when v_elapsed_hours <= 6 then 0.25
                when v_elapsed_hours <= 24 then 0.18
                else 0.10
              end
            )
          )
        )
        /
        greatest(0.10, v_expected_factor)
      );

    if v_profit then
      v_delta :=
        round(
          v_base_target_step
          * v_profit_mult
          * case
              when v_gap >= -v_base_target_step
                then v_age_weight
              else 1.0
            end,
          2
        );
    else
      v_delta :=
        -round(
          greatest(
            0.01,
            v_base_target_step * v_loss_mult
          ),
          2
        );
    end if;

    -- ----------------------------------------------------------
    -- 안전보정
    --
    -- 짧은 구간:
    --   허용범위를 크게 벗어나지 않도록 강하게 제어.
    --
    -- 장기 구간:
    --   밴드 자체가 매우 넓으므로 자연스럽게 결과 차이가 커짐.
    -- ----------------------------------------------------------

    v_projected :=
      coalesce(inv.realized_amount,0)
      + v_delta;

    -- 아래쪽 과이탈
    if v_elapsed_hours >= 0.9
       and v_projected < v_band_min_amount * 0.97 then

      v_delta :=
        round(
          (v_band_min_amount * 0.97)
          - coalesce(inv.realized_amount,0),
          2
        );

    -- 위쪽 과이탈
    elsif v_projected > v_band_max_amount * 1.03 then

      v_delta :=
        round(
          (v_band_max_amount * 1.03)
          - coalesce(inv.realized_amount,0),
          2
        );
    end if;

    -- 완전히 0원 지급은 만들지 않음
    if abs(v_delta) < 0.01 then
      update public.app_investments
      set last_payout_at = v_now,
          updated_at = v_now
      where id = inv.id;

      continue;
    end if;

    -- ----------------------------------------------------------
    -- 로그 저장
    -- ----------------------------------------------------------

    insert into public.app_profit_logs(
      user_id,
      investment_id,
      amount_delta,
      source_type,
      created_at
    )
    values(
      inv.user_id,
      inv.id,
      v_delta,
      'process_payout',
      v_now
    );

    update public.app_investments
    set realized_amount =
          coalesce(realized_amount,0) + v_delta,
        payout_count =
          payout_count + 1,
        loss_count =
          loss_count + case when v_delta < 0 then 1 else 0 end,
        last_payout_at =
          v_now,
        updated_at =
          v_now
    where id = inv.id;

    update public.app_users
    set realized_amount =
          coalesce(realized_amount,0) + v_delta,
        updated_at =
          v_now
    where id = inv.user_id;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- ------------------------------------------------------------
-- 7) 권한 / Realtime / cron 복구
-- ------------------------------------------------------------
grant execute on function public.ai_process_return_band(numeric) to anon, authenticated;
grant execute on function public.ai_process_target_pct(numeric,numeric) to anon, authenticated;
grant execute on function public.ai_process_age_weight(numeric) to anon, authenticated;
grant execute on function public.run_multi_investment_payouts() to anon, authenticated;

grant select, insert, update on public.app_investments to anon, authenticated;
grant select, insert, update on public.app_investment_amount_logs to anon, authenticated;
grant select, insert, update on public.app_profit_logs to anon, authenticated;
grant select, update on public.app_payout_settings to anon, authenticated;

do $$
begin
  begin
    alter publication supabase_realtime add table public.app_investments;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.app_profit_logs;
  exception when duplicate_object then null;
  end;
end $$;

-- 중복/구버전 지급 cron 제거 후 최종 엔진 하나만 등록.
do $$
declare
  j record;
begin
  for j in
    select jobid
    from cron.job
    where jobname in (
      'ai-process-multi-payout',
      'ai-process-timecurve-payout',
      'ai-auto-payout-every-9min',
      'user-auto-payout',
      'ailife-auto-payout'
    )
    or command ilike '%run_multi_investment_payouts%'
    or command ilike '%run_auto_payout%'
  loop
    perform cron.unschedule(j.jobid);
  end loop;
end $$;

select cron.schedule(
  'ai-process-timecurve-payout',
  '* * * * *',
  $$select public.run_multi_investment_payouts();$$
);

-- ------------------------------------------------------------
-- 8) 최종 확인
-- SQL 실행 결과에서 아래 값들을 확인하세요.
-- enabled = true
-- cron_active = true
-- running_investments > 0 이면 진행중 투자 존재
-- 최근 로그는 실제 지급간격이 지난 뒤 생성됩니다.
-- ------------------------------------------------------------
select
  id,
  enabled,
  every_minutes,
  profit_probability,
  loss_probability
from public.app_payout_settings
where id = 1;

select
  jobid,
  jobname,
  schedule,
  command,
  active as cron_active
from cron.job
where jobname = 'ai-process-timecurve-payout';

select
  count(*) as running_investments,
  count(*) filter (where started_at is not null) as running_with_start_time
from public.app_investments
where status = '진행중';

select
  id,
  user_id,
  amount,
  realized_amount,
  started_at,
  last_payout_at,
  payout_count,
  loss_count
from public.app_investments
where status = '진행중'
order by created_at desc
limit 20;

select
  investment_id,
  amount_delta,
  source_type,
  created_at
from public.app_profit_logs
where source_type in ('payout','process_payout')
order by created_at desc
limit 20;
