
-- ============================================================
-- AI 프로세스 VIP 종합 테스트 V1
-- 단체채팅 / 사진 / 메시지삭제 / 입장표시 / 강퇴
-- 1:1 상담 / 이벤트 / 브라우저 알림 / 100종 프로필 선택
--
-- 중요: 현재 AI 프로세스의 '자체 로그인 + anon key' 구조와
-- 테스트를 맞추기 위해 VIP 테이블 RLS는 OFF입니다.
-- 실제 운영 전에는 Auth/RLS 또는 서버 검증 구조로 강화해야 합니다.
-- ============================================================

begin;

create extension if not exists pgcrypto;

create table if not exists public.vip_profiles (
  user_id uuid primary key references public.app_users(id) on delete cascade,
  nickname text not null,
  avatar_key text not null default '🐼',
  vip_enabled boolean not null default true,
  group_kicked boolean not null default false,
  first_group_join_at timestamptz,
  notify_events boolean not null default true,
  notify_support boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.vip_profiles disable row level security;

insert into public.vip_profiles(user_id,nickname,avatar_key)
select id,coalesce(nullif(name,''),username),'🐼'
from public.app_users
where role <> 'admin'
on conflict(user_id) do nothing;

create table if not exists public.vip_group_messages (
  id uuid primary key default gen_random_uuid(),
  sender_user_id uuid references public.app_users(id) on delete set null,
  sender_role text not null default 'user' check(sender_role in ('user','admin','system')),
  message_type text not null default 'text' check(message_type in ('text','image','system','event')),
  body text,
  image_url text,
  reply_to uuid references public.vip_group_messages(id) on delete set null,
  is_deleted boolean not null default false,
  deleted_at timestamptz,
  deleted_by text,
  created_at timestamptz not null default now()
);
create index if not exists vip_group_messages_created_idx on public.vip_group_messages(created_at desc);
alter table public.vip_group_messages disable row level security;

create table if not exists public.vip_support_threads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.app_users(id) on delete cascade,
  status text not null default '대기' check(status in ('대기','상담중','완료')),
  unread_admin integer not null default 0,
  unread_user integer not null default 0,
  admin_note text,
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists vip_support_threads_last_idx on public.vip_support_threads(last_message_at desc nulls last);
alter table public.vip_support_threads disable row level security;

create table if not exists public.vip_support_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.vip_support_threads(id) on delete cascade,
  sender_user_id uuid references public.app_users(id) on delete set null,
  sender_role text not null check(sender_role in ('user','admin','system')),
  message_type text not null default 'text' check(message_type in ('text','image','system')),
  body text,
  image_url text,
  reply_to uuid references public.vip_support_messages(id) on delete set null,
  is_deleted boolean not null default false,
  deleted_at timestamptz,
  deleted_by text,
  created_at timestamptz not null default now()
);
create index if not exists vip_support_messages_thread_created_idx on public.vip_support_messages(thread_id,created_at);
alter table public.vip_support_messages disable row level security;

create table if not exists public.vip_events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  image_url text,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  winner_count integer not null default 1 check(winner_count > 0),
  status text not null default '진행중' check(status in ('진행중','종료')),
  notify_on_publish boolean not null default true,
  notification_title text,
  notification_body text,
  created_by uuid references public.app_users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.vip_events disable row level security;

create table if not exists public.vip_event_entries (
  event_id uuid not null references public.vip_events(id) on delete cascade,
  user_id uuid not null references public.app_users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(event_id,user_id)
);
alter table public.vip_event_entries disable row level security;

create table if not exists public.vip_event_winners (
  event_id uuid not null references public.vip_events(id) on delete cascade,
  user_id uuid not null references public.app_users(id) on delete cascade,
  selected_at timestamptz not null default now(),
  primary key(event_id,user_id)
);
alter table public.vip_event_winners disable row level security;

create table if not exists public.vip_notifications (
  id uuid primary key default gen_random_uuid(),
  target_role text not null check(target_role in ('user','admin')),
  target_user_id uuid references public.app_users(id) on delete cascade,
  type text not null default 'broadcast',
  title text not null,
  body text,
  target_url text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists vip_notifications_target_idx
on public.vip_notifications(target_role,target_user_id,created_at desc);
alter table public.vip_notifications disable row level security;

create table if not exists public.vip_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  target_role text not null check(target_role in ('user','admin')),
  target_user_id uuid references public.app_users(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_agent text,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.vip_push_subscriptions disable row level security;

grant select,insert,update,delete on
  public.vip_profiles,
  public.vip_group_messages,
  public.vip_support_threads,
  public.vip_support_messages,
  public.vip_events,
  public.vip_event_entries,
  public.vip_event_winners,
  public.vip_notifications,
  public.vip_push_subscriptions
to anon, authenticated;

-- 1:1 메시지가 오면 반대편 알림 생성 + 안읽음 갱신
create or replace function public.vip_after_support_message()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_user_id uuid;
  v_name text;
  v_preview text;
begin
  select user_id into v_user_id
  from public.vip_support_threads
  where id=new.thread_id;

  select coalesce(p.nickname,u.name,u.username,'VIP 회원')
  into v_name
  from public.app_users u
  left join public.vip_profiles p on p.user_id=u.id
  where u.id=v_user_id;

  v_preview := coalesce(nullif(new.body,''), case when new.message_type='image' then '사진을 보냈습니다.' else '새 메시지가 도착했습니다.' end);

  if new.sender_role='user' then
    update public.vip_support_threads
    set unread_admin=unread_admin+1,
        status=case when status='완료' then '대기' else status end,
        last_message_at=new.created_at,
        updated_at=now()
    where id=new.thread_id;

    insert into public.vip_notifications(target_role,type,title,body,target_url)
    values(
      'admin','support','새 1:1 문의',
      v_name || ' · ' || left(v_preview,80),
      'admin/admin-vip-support.html?thread=' || new.thread_id::text
    );

  elsif new.sender_role='admin' then
    update public.vip_support_threads
    set unread_user=unread_user+1,
        status=case when status='대기' then '상담중' else status end,
        last_message_at=new.created_at,
        updated_at=now()
    where id=new.thread_id;

    insert into public.vip_notifications(target_role,target_user_id,type,title,body,target_url)
    values(
      'user',v_user_id,'support','AI 프로세스 VIP · 1:1 답변',
      left(v_preview,100),
      'vip/support.html'
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_vip_after_support_message on public.vip_support_messages;
create trigger trg_vip_after_support_message
after insert on public.vip_support_messages
for each row execute function public.vip_after_support_message();

-- 이벤트 생성 시, 이벤트 알림을 허용한 VIP 유저에게만 알림 생성
create or replace function public.vip_after_event_insert()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.notify_on_publish=true and new.status='진행중' then
    insert into public.vip_notifications(target_role,target_user_id,type,title,body,target_url)
    select
      'user',
      p.user_id,
      'event',
      coalesce(nullif(new.notification_title,''),'AI 프로세스 VIP 이벤트'),
      coalesce(nullif(new.notification_body,''),new.title || ' 이벤트가 시작되었습니다.'),
      'vip/events.html#event-' || new.id::text
    from public.vip_profiles p
    where p.vip_enabled=true
      and p.notify_events=true
      and p.group_kicked=false;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_vip_after_event_insert on public.vip_events;
create trigger trg_vip_after_event_insert
after insert on public.vip_events
for each row execute function public.vip_after_event_insert();

-- 사진용 공개 테스트 버킷
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('vip-media','vip-media',true,8388608,array['image/jpeg','image/png','image/webp','image/gif'])
on conflict(id) do update
set public=true,file_size_limit=8388608,allowed_mime_types=excluded.allowed_mime_types;

do $$
begin
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='vip media read test') then
    create policy "vip media read test" on storage.objects
    for select to public using(bucket_id='vip-media');
  end if;
  if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='vip media upload test') then
    create policy "vip media upload test" on storage.objects
    for insert to public with check(bucket_id='vip-media');
  end if;
end $$;

-- Realtime
do $$
begin
  begin alter publication supabase_realtime add table public.vip_group_messages; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.vip_support_threads; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.vip_support_messages; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.vip_events; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.vip_notifications; exception when duplicate_object then null; end;
end $$;

commit;

select
  (select count(*) from public.vip_profiles) as vip_profiles,
  (select count(*) from public.vip_support_threads) as support_threads,
  (select count(*) from public.vip_events) as events;
