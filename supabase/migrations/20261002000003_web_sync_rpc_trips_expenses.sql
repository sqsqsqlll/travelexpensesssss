-- 网页端同步 RPC（三）：行程、账目

-- ---------- 行程 ----------
create or replace function public.save_trip(p jsonb) returns void
language plpgsql security invoker set search_path = '' as $$
begin
  insert into public.trips (id, name, start_date, end_date, note, base_currency, created_at)
  values ((p->>'id')::uuid, p->>'name', nullif(p->>'start_date','')::date, nullif(p->>'end_date','')::date,
          coalesce(p->>'note',''), coalesce(p->>'base_currency','CNY'), coalesce((p->>'created_at')::timestamptz, now()))
  on conflict (id) do update set name = excluded.name, start_date = excluded.start_date,
    end_date = excluded.end_date, note = excluded.note, base_currency = excluded.base_currency;
end $$;

create or replace function public.delete_trip(tid uuid) returns void
language sql security invoker set search_path = '' as $$ delete from public.trips where id = tid $$;

-- ---------- 账目（付款人/参与人按名字传入，原子写入分摊明细） ----------
create or replace function public.save_expense(p jsonb) returns void
language plpgsql security invoker set search_path = '' as $$
declare
  eid uuid := (p->>'id')::uuid;
  tid uuid := nullif(p->>'trip_id','')::uuid;
  payer uuid := public.resolve_person(p->>'payer');
  bid uuid := nullif(p->>'budget_item_id','')::uuid;
  s jsonb; i int := 0; pid uuid;
begin
  if tid is not null and not exists (select 1 from public.trips where id = tid) then tid := null; end if;
  if bid is not null and not exists (select 1 from public.budget_items where id = bid) then bid := null; end if;
  insert into public.expenses (id, trip_id, item, spent_on, category, payer_id, amount, currency, rate,
                               split_mode, status, note, budget_item_id, created_at)
  values (eid, tid, coalesce(p->>'item',''), coalesce(nullif(p->>'spent_on','')::date, current_date),
          coalesce(p->>'category','other'), payer, (p->>'amount')::numeric, coalesce(p->>'currency','CNY'),
          coalesce((p->>'rate')::numeric, 1), coalesce(p->>'split_mode','equal'), coalesce(p->>'status','confirmed'),
          coalesce(p->>'note',''), bid, coalesce((p->>'created_at')::timestamptz, now()))
  on conflict (id) do update set trip_id = excluded.trip_id, item = excluded.item, spent_on = excluded.spent_on,
    category = excluded.category, payer_id = excluded.payer_id, amount = excluded.amount, currency = excluded.currency,
    rate = excluded.rate, split_mode = excluded.split_mode, status = excluded.status, note = excluded.note,
    budget_item_id = excluded.budget_item_id;
  delete from public.expense_shares where expense_id = eid;
  for s in select * from jsonb_array_elements(coalesce(p->'shares','[]'::jsonb)) loop
    pid := public.resolve_person(s->>'name');
    insert into public.expense_shares (expense_id, person_id, share, pos)
    values (eid, pid, coalesce((s->>'share')::numeric, 1), i)
    on conflict (expense_id, person_id) do update set share = excluded.share, pos = excluded.pos;
    i := i + 1;
    if tid is not null then insert into public.trip_people (trip_id, person_id) values (tid, pid) on conflict do nothing; end if;
  end loop;
  if tid is not null then insert into public.trip_people (trip_id, person_id) values (tid, payer) on conflict do nothing; end if;
end $$;

create or replace function public.delete_expense(eid uuid) returns void
language sql security invoker set search_path = '' as $$ delete from public.expenses where id = eid $$;
