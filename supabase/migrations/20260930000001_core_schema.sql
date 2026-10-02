-- 旅游AA账本 · 核心数据模型（总库 + 行程级汇算 + 行级权限）
-- 约定：金额 numeric(14,2)，汇率 numeric(18,6)（原币 → 行程基准币），币种为 ISO 4217 三位代码。

create extension if not exists pgcrypto;
create schema if not exists private;

-- ---------- 通用：updated_at ----------
create or replace function private.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin new.updated_at := now(); return new; end $$;

-- ---------- 用户资料 ----------
create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_name  text not null default '',
  avatar_url    text,
  base_currency text not null default 'CNY' check (base_currency ~ '^[A-Z]{3}$'),
  common_currencies text[] not null default array['CNY'],
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create or replace function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(coalesce(new.email,''), '@', 1), ''))
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();

-- ---------- 同行人（分账对象，不一定是注册用户） ----------
create table public.people (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null default auth.uid() references auth.users(id) on delete cascade,
  user_id    uuid references auth.users(id) on delete set null, -- 若此人也注册了，可关联
  name       text not null check (length(name) between 1 and 40),
  note       text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.people (owner_id);
create index on public.people (user_id);

-- ---------- 行程 ----------
create table public.trips (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name          text not null check (length(name) between 1 and 60),
  destination   text not null default '',
  start_date    date,
  end_date      date,
  base_currency text not null default 'CNY' check (base_currency ~ '^[A-Z]{3}$'),
  budget_total  numeric(14,2),
  note          text not null default '',
  cover_url     text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (end_date is null or start_date is null or end_date >= start_date)
);
create index on public.trips (owner_id);

-- 行程访问权限：owner / editor / viewer
create table public.trip_access (
  trip_id    uuid not null references public.trips(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       text not null check (role in ('owner','editor','viewer')),
  created_at timestamptz not null default now(),
  primary key (trip_id, user_id)
);
create index on public.trip_access (user_id);

-- 行程参与人（分账名单）
create table public.trip_people (
  trip_id   uuid not null references public.trips(id) on delete cascade,
  person_id uuid not null references public.people(id) on delete cascade,
  primary key (trip_id, person_id)
);
create index on public.trip_people (person_id);

-- 权限判定（security definer，避免 RLS 递归）
create or replace function private.trip_role_rank(r text) returns int
language sql immutable set search_path = '' as $$
  select case r when 'owner' then 3 when 'editor' then 2 when 'viewer' then 1 else 0 end $$;

create or replace function private.has_trip_role(tid uuid, min_role text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.trip_access a
    where a.trip_id = tid and a.user_id = (select auth.uid())
      and private.trip_role_rank(a.role) >= private.trip_role_rank(min_role)
  ) $$;

create or replace function private.add_trip_owner() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.trip_access (trip_id, user_id, role) values (new.id, new.owner_id, 'owner')
  on conflict (trip_id, user_id) do update set role = 'owner';
  return new;
end $$;
create trigger trips_add_owner after insert on public.trips
  for each row execute function private.add_trip_owner();

-- ---------- 地点总库 ----------
create table public.places (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  visibility    text not null default 'private' check (visibility in ('private','public')),
  kind          text not null default 'other'
                check (kind in ('sight','restaurant','hotel','shop','transport','activity','other')),
  name          text not null check (length(name) between 1 and 120),
  country       text not null default '',
  city          text not null default '',
  address       text not null default '',
  lat           double precision,
  lng           double precision,
  website       text,
  phone         text,
  opening_hours text not null default '',
  external_ids  jsonb not null default '{}'::jsonb,   -- {"amap":"...","google":"...","osm":"..."}
  toilet        text check (toilet in ('clean','ok','poor','none')),
  accessibility jsonb not null default '{}'::jsonb,   -- {"wheelchair":"yes|limited|no","elevator":true,...}
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index on public.places (owner_id);

-- ---------- 预算 / 计划 ----------
create table public.budget_items (
  id              uuid primary key default gen_random_uuid(),
  trip_id         uuid not null references public.trips(id) on delete cascade,
  title           text not null check (length(title) between 1 and 120),
  category        text not null default 'other'
                  check (category in ('food','transport','shopping','lodging','entertainment','tickets','medical','other')),
  day_date        date,
  planned_amount  numeric(14,2) not null default 0 check (planned_amount >= 0),
  currency        text not null default 'CNY' check (currency ~ '^[A-Z]{3}$'),
  rate            numeric(18,6) not null default 1 check (rate > 0),
  is_fixed        boolean not null default false,       -- 固定费用（车票/门票等）vs 预估
  status          text not null default 'idea' check (status in ('idea','booked','paid')),
  chosen_option_id uuid,
  booking_ref     text not null default '',
  url             text,
  note            text not null default '',
  sort            int not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index on public.budget_items (trip_id);

-- 比价方案：同一预算项的多个选择
create table public.price_options (
  id               uuid primary key default gen_random_uuid(),
  budget_item_id   uuid not null references public.budget_items(id) on delete cascade,
  label            text not null check (length(label) between 1 and 120), -- 如「JR 新快速」「高速巴士」
  mode             text not null default '',        -- train / bus / flight / car / walk / ...
  channel          text not null default '',        -- 购买渠道：官网 / 携程 / Klook / 现场 ...
  price            numeric(14,2) not null default 0 check (price >= 0),
  currency         text not null default 'CNY' check (currency ~ '^[A-Z]{3}$'),
  duration_minutes int check (duration_minutes >= 0),
  transfers        int check (transfers >= 0),
  convenience      smallint check (convenience between 1 and 5),
  refundable       boolean,
  url              text,
  checked_at       timestamptz,                     -- 价格查询时间（价格会过时）
  note             text not null default '',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index on public.price_options (budget_item_id);
alter table public.budget_items add constraint budget_items_chosen_option_fk
  foreign key (chosen_option_id) references public.price_options(id) on delete set null;
create index on public.budget_items (chosen_option_id);

-- ---------- 账目 ----------
create table public.expenses (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  trip_id        uuid references public.trips(id) on delete set null,  -- 可为空 = 未分配
  item           text not null default '' check (length(item) <= 120),
  spent_on       date not null default current_date,
  category       text not null default 'other'
                 check (category in ('food','transport','shopping','lodging','entertainment','tickets','medical','other')),
  payer_id       uuid not null references public.people(id) on delete restrict,
  amount         numeric(14,2) not null check (amount > 0),
  currency       text not null default 'CNY' check (currency ~ '^[A-Z]{3}$'),
  rate           numeric(18,6) not null default 1 check (rate > 0),  -- 原币 → 基准币
  split_mode     text not null default 'equal' check (split_mode in ('equal','ratio','amount')),
  status         text not null default 'confirmed' check (status in ('confirmed','pending')),
  note           text not null default '',
  source         text not null default 'manual' check (source in ('manual','csv','bill_import','ocr','email','budget')),
  source_ref     text,                              -- 导入去重用（如支付流水号）
  place_id       uuid references public.places(id) on delete set null,
  budget_item_id uuid references public.budget_items(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index on public.expenses (owner_id);
create index on public.expenses (trip_id);
create index on public.expenses (payer_id);
create index on public.expenses (place_id);
create index on public.expenses (budget_item_id);
create unique index expenses_source_ref_uniq on public.expenses (owner_id, source, source_ref) where source_ref is not null;

-- 分摊明细：equal → share 可忽略；ratio → share 为份数；amount → share 为原币金额
create table public.expense_shares (
  expense_id uuid not null references public.expenses(id) on delete cascade,
  person_id  uuid not null references public.people(id) on delete restrict,
  share      numeric(14,4) not null default 1 check (share >= 0),
  primary key (expense_id, person_id)
);
create index on public.expense_shares (person_id);

create or replace function private.can_view_expense(eid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.expenses e where e.id = eid
    and (e.owner_id = (select auth.uid()) or (e.trip_id is not null and private.has_trip_role(e.trip_id,'viewer')))) $$;
create or replace function private.can_edit_expense(eid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.expenses e where e.id = eid
    and (e.owner_id = (select auth.uid()) or (e.trip_id is not null and private.has_trip_role(e.trip_id,'editor')))) $$;

-- ---------- 到访记录（记忆） ----------
create table public.visits (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  place_id     uuid not null references public.places(id) on delete cascade,
  trip_id      uuid references public.trips(id) on delete set null,
  visited_on   date,
  rating       smallint check (rating between 1 and 5),
  impression   text not null default '',
  experiences  text not null default '',   -- 体验项目
  highlights   text not null default '',   -- 特色内容
  toilet_note  text not null default '',
  accessibility_note text not null default '',
  photos       text[] not null default '{}',
  is_public    boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index on public.visits (owner_id);
create index on public.visits (place_id);
create index on public.visits (trip_id);

-- ---------- 分享资料包 ----------
create table public.share_packs (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null default auth.uid() references auth.users(id) on delete cascade,
  slug            text not null unique default encode(gen_random_bytes(6),'hex'),
  title           text not null check (length(title) between 1 and 120),
  description     text not null default '',
  is_public       boolean not null default false,
  include_amounts boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index on public.share_packs (owner_id);

create table public.share_pack_items (
  id       uuid primary key default gen_random_uuid(),
  pack_id  uuid not null references public.share_packs(id) on delete cascade,
  place_id uuid references public.places(id) on delete cascade,
  visit_id uuid references public.visits(id) on delete cascade,
  sort     int not null default 0,
  note     text not null default '',
  check (place_id is not null or visit_id is not null)
);
create index on public.share_pack_items (pack_id);
create index on public.share_pack_items (place_id);
create index on public.share_pack_items (visit_id);

-- ---------- updated_at 触发器 ----------
do $$ declare t text; begin
  foreach t in array array['profiles','people','trips','places','budget_items','price_options','expenses','visits','share_packs'] loop
    execute format('create trigger %I before update on public.%I for each row execute function private.touch_updated_at()', t||'_touch', t);
  end loop;
end $$;

-- ================= 行级权限 =================
alter table public.profiles         enable row level security;
alter table public.people           enable row level security;
alter table public.trips            enable row level security;
alter table public.trip_access      enable row level security;
alter table public.trip_people      enable row level security;
alter table public.places           enable row level security;
alter table public.budget_items     enable row level security;
alter table public.price_options    enable row level security;
alter table public.expenses         enable row level security;
alter table public.expense_shares   enable row level security;
alter table public.visits           enable row level security;
alter table public.share_packs      enable row level security;
alter table public.share_pack_items enable row level security;

-- profiles：只能读写自己的
create policy profiles_select on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy profiles_update on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- people：自己建的；或出现在自己可见的行程里
create policy people_select on public.people for select to authenticated using (
  owner_id = (select auth.uid())
  or exists (select 1 from public.trip_people tp where tp.person_id = people.id and private.has_trip_role(tp.trip_id,'viewer')));
create policy people_insert on public.people for insert to authenticated with check (owner_id = (select auth.uid()));
create policy people_update on public.people for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy people_delete on public.people for delete to authenticated using (owner_id = (select auth.uid()));

-- trips
create policy trips_select on public.trips for select to authenticated using (owner_id = (select auth.uid()) or private.has_trip_role(id,'viewer'));
create policy trips_insert on public.trips for insert to authenticated with check (owner_id = (select auth.uid()));
create policy trips_update on public.trips for update to authenticated using (private.has_trip_role(id,'editor')) with check (private.has_trip_role(id,'editor'));
create policy trips_delete on public.trips for delete to authenticated using (owner_id = (select auth.uid()));

-- trip_access：成员可见；仅 owner 可管理
create policy trip_access_select on public.trip_access for select to authenticated using (private.has_trip_role(trip_id,'viewer'));
create policy trip_access_insert on public.trip_access for insert to authenticated with check (private.has_trip_role(trip_id,'owner'));
create policy trip_access_update on public.trip_access for update to authenticated using (private.has_trip_role(trip_id,'owner')) with check (private.has_trip_role(trip_id,'owner'));
create policy trip_access_delete on public.trip_access for delete to authenticated using (private.has_trip_role(trip_id,'owner') and user_id <> (select auth.uid()));

-- trip_people
create policy trip_people_select on public.trip_people for select to authenticated using (private.has_trip_role(trip_id,'viewer'));
create policy trip_people_insert on public.trip_people for insert to authenticated with check (private.has_trip_role(trip_id,'editor'));
create policy trip_people_delete on public.trip_people for delete to authenticated using (private.has_trip_role(trip_id,'editor'));

-- places：公开的所有人可读（含未登录，用于分享）；私有仅本人
create policy places_select on public.places for select to anon, authenticated using (visibility = 'public' or owner_id = (select auth.uid()));
create policy places_insert on public.places for insert to authenticated with check (owner_id = (select auth.uid()));
create policy places_update on public.places for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy places_delete on public.places for delete to authenticated using (owner_id = (select auth.uid()));

-- budget_items / price_options：随行程权限
create policy budget_select on public.budget_items for select to authenticated using (private.has_trip_role(trip_id,'viewer'));
create policy budget_insert on public.budget_items for insert to authenticated with check (private.has_trip_role(trip_id,'editor'));
create policy budget_update on public.budget_items for update to authenticated using (private.has_trip_role(trip_id,'editor')) with check (private.has_trip_role(trip_id,'editor'));
create policy budget_delete on public.budget_items for delete to authenticated using (private.has_trip_role(trip_id,'editor'));

create policy price_select on public.price_options for select to authenticated using (
  exists (select 1 from public.budget_items b where b.id = budget_item_id and private.has_trip_role(b.trip_id,'viewer')));
create policy price_insert on public.price_options for insert to authenticated with check (
  exists (select 1 from public.budget_items b where b.id = budget_item_id and private.has_trip_role(b.trip_id,'editor')));
create policy price_update on public.price_options for update to authenticated using (
  exists (select 1 from public.budget_items b where b.id = budget_item_id and private.has_trip_role(b.trip_id,'editor'))) with check (
  exists (select 1 from public.budget_items b where b.id = budget_item_id and private.has_trip_role(b.trip_id,'editor')));
create policy price_delete on public.price_options for delete to authenticated using (
  exists (select 1 from public.budget_items b where b.id = budget_item_id and private.has_trip_role(b.trip_id,'editor')));

-- expenses：本人的（含未分配）或所在行程可见；写入需本人或行程 editor
create policy expenses_select on public.expenses for select to authenticated using (
  owner_id = (select auth.uid()) or (trip_id is not null and private.has_trip_role(trip_id,'viewer')));
create policy expenses_insert on public.expenses for insert to authenticated with check (
  owner_id = (select auth.uid()) and (trip_id is null or private.has_trip_role(trip_id,'editor')));
create policy expenses_update on public.expenses for update to authenticated using (
  owner_id = (select auth.uid()) or (trip_id is not null and private.has_trip_role(trip_id,'editor'))) with check (
  (trip_id is null and owner_id = (select auth.uid())) or (trip_id is not null and private.has_trip_role(trip_id,'editor')));
create policy expenses_delete on public.expenses for delete to authenticated using (
  owner_id = (select auth.uid()) or (trip_id is not null and private.has_trip_role(trip_id,'editor')));

create policy shares_select on public.expense_shares for select to authenticated using (private.can_view_expense(expense_id));
create policy shares_insert on public.expense_shares for insert to authenticated with check (private.can_edit_expense(expense_id));
create policy shares_update on public.expense_shares for update to authenticated using (private.can_edit_expense(expense_id)) with check (private.can_edit_expense(expense_id));
create policy shares_delete on public.expense_shares for delete to authenticated using (private.can_edit_expense(expense_id));

-- visits：本人；公开的所有人可读；同行程成员可读
create policy visits_select on public.visits for select to anon, authenticated using (
  is_public or owner_id = (select auth.uid()) or (trip_id is not null and private.has_trip_role(trip_id,'viewer')));
create policy visits_insert on public.visits for insert to authenticated with check (owner_id = (select auth.uid()));
create policy visits_update on public.visits for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy visits_delete on public.visits for delete to authenticated using (owner_id = (select auth.uid()));

-- share_packs
create policy packs_select on public.share_packs for select to anon, authenticated using (is_public or owner_id = (select auth.uid()));
create policy packs_insert on public.share_packs for insert to authenticated with check (owner_id = (select auth.uid()));
create policy packs_update on public.share_packs for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy packs_delete on public.share_packs for delete to authenticated using (owner_id = (select auth.uid()));

create policy pack_items_select on public.share_pack_items for select to anon, authenticated using (
  exists (select 1 from public.share_packs p where p.id = pack_id and (p.is_public or p.owner_id = (select auth.uid()))));
create policy pack_items_write on public.share_pack_items for all to authenticated using (
  exists (select 1 from public.share_packs p where p.id = pack_id and p.owner_id = (select auth.uid()))) with check (
  exists (select 1 from public.share_packs p where p.id = pack_id and p.owner_id = (select auth.uid())));

-- ================= 行程级汇算视图（沿用调用者权限） =================
-- 每笔账目 × 每人应摊（原币 & 基准币）
create view public.expense_share_amounts with (security_invoker = true) as
select s.expense_id, e.trip_id, s.person_id, e.status, e.category,
       round(case e.split_mode
         when 'equal'  then e.amount / nullif(count(*) over w, 0)
         when 'ratio'  then e.amount * s.share / nullif(sum(s.share) over w, 0)
         else s.share end, 4) as share_amount,
       round(case e.split_mode
         when 'equal'  then e.amount / nullif(count(*) over w, 0)
         when 'ratio'  then e.amount * s.share / nullif(sum(s.share) over w, 0)
         else s.share end * e.rate, 4) as share_base
from public.expense_shares s
join public.expenses e on e.id = s.expense_id
window w as (partition by s.expense_id);

-- 行程内每人：垫付 / 应摊 / 结余（仅已确认，基准币）
create view public.trip_balances with (security_invoker = true) as
with paid as (
  select trip_id, payer_id as person_id, sum(amount * rate) as paid_base
  from public.expenses where status = 'confirmed' and trip_id is not null group by 1,2
), owed as (
  select trip_id, person_id, sum(share_base) as owed_base
  from public.expense_share_amounts where status = 'confirmed' and trip_id is not null group by 1,2
)
select coalesce(p.trip_id, o.trip_id) as trip_id,
       coalesce(p.person_id, o.person_id) as person_id,
       round(coalesce(p.paid_base,0),2) as paid_base,
       round(coalesce(o.owed_base,0),2) as owed_base,
       round(coalesce(p.paid_base,0) - coalesce(o.owed_base,0),2) as balance_base
from paid p full join owed o on o.trip_id = p.trip_id and o.person_id = p.person_id;

-- 行程分类汇总（跨行程分析的基础）
create view public.trip_category_totals with (security_invoker = true) as
select trip_id, category, count(*) as n,
       round(sum(amount * rate),2) as total_base,
       round(sum(amount * rate) filter (where status = 'confirmed'),2) as confirmed_base
from public.expenses where trip_id is not null group by 1,2;

-- 预算 vs 实际
create view public.trip_budget_vs_actual with (security_invoker = true) as
select t.id as trip_id, c.category,
       coalesce((select round(sum(b.planned_amount * b.rate),2) from public.budget_items b where b.trip_id = t.id and b.category = c.category),0) as planned_base,
       coalesce((select round(sum(e.amount * e.rate),2) from public.expenses e where e.trip_id = t.id and e.category = c.category),0) as actual_base
from public.trips t
cross join (values ('food'),('transport'),('shopping'),('lodging'),('entertainment'),('tickets'),('medical'),('other')) as c(category);

-- ================= private 函数授权 =================
revoke all on all functions in schema private from public;
grant usage on schema private to anon, authenticated;
grant execute on function private.trip_role_rank(text)          to anon, authenticated;
grant execute on function private.has_trip_role(uuid, text)     to anon, authenticated;
grant execute on function private.can_view_expense(uuid)        to authenticated;
grant execute on function private.can_edit_expense(uuid)        to authenticated;
