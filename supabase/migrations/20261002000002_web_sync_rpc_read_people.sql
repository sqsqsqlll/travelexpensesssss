-- 网页端同步 RPC（二）：读取、设置、成员

-- ---------- 读取：一次拉取当前用户可见的全部数据 ----------
create or replace function public.pull_all() returns jsonb
language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'profile', (select to_jsonb(p) from public.profiles p where p.id = (select auth.uid())),
    'people',  coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.people x), '[]'::jsonb),
    'trips',   coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.trips x), '[]'::jsonb),
    'expenses', coalesce((select jsonb_agg(to_jsonb(e) || jsonb_build_object('shares',
        coalesce((select jsonb_agg(jsonb_build_object('person_id', s.person_id, 'share', s.share) order by s.pos)
                  from public.expense_shares s where s.expense_id = e.id), '[]'::jsonb)) order by e.created_at)
      from public.expenses e), '[]'::jsonb),
    'budget_items', coalesce((select jsonb_agg(to_jsonb(b) || jsonb_build_object('options',
        coalesce((select jsonb_agg(to_jsonb(o) order by o.pos) from public.price_options o where o.budget_item_id = b.id), '[]'::jsonb)) order by b.created_at)
      from public.budget_items b), '[]'::jsonb)
  ) $$;

-- ---------- 设置 ----------
create or replace function public.save_profile(p jsonb) returns void
language plpgsql security invoker set search_path = '' as $$
begin
  insert into public.profiles (id, base_currency, common_currencies, initialized)
  values ((select auth.uid()), coalesce(p->>'base_currency','CNY'),
          coalesce(array(select jsonb_array_elements_text(p->'common_currencies')), array['CNY']),
          coalesce((p->>'initialized')::boolean, false))
  on conflict (id) do update set base_currency = excluded.base_currency,
    common_currencies = excluded.common_currencies, initialized = excluded.initialized;
end $$;

-- ---------- 成员 ----------
create or replace function public.save_person(p jsonb) returns void
language plpgsql security invoker set search_path = '' as $$
begin
  insert into public.people (id, name, note, archived, created_at)
  values ((p->>'id')::uuid, p->>'name', coalesce(p->>'note',''), coalesce((p->>'archived')::boolean,false),
          coalesce((p->>'created_at')::timestamptz, now()))
  on conflict (id) do update set name = excluded.name, note = excluded.note, archived = excluded.archived;
end $$;

create or replace function public.archive_person(pid uuid) returns void
language sql security invoker set search_path = '' as $$
  update public.people set archived = true where id = pid $$;

-- 按名字找人（本人名下，优先未归档）；找不到则创建一个已归档的人（用于已删除成员的历史账目）
create or replace function public.resolve_person(pname text) returns uuid
language plpgsql security invoker set search_path = '' as $$
declare pid uuid;
begin
  select id into pid from public.people
   where owner_id = (select auth.uid()) and name = pname
   order by archived, created_at limit 1;
  if pid is null then
    insert into public.people (name, archived) values (pname, true) returning id into pid;
  end if;
  return pid;
end $$;
