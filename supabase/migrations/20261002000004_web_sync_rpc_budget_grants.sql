-- 网页端同步 RPC（四）：预算项与比价、授权

-- ---------- 预算项 + 比价方案（原子写入） ----------
create or replace function public.save_budget_item(p jsonb) returns void
language plpgsql security invoker set search_path = '' as $$
declare
  bid uuid := (p->>'id')::uuid; o jsonb; i int := 0; keep uuid[] := '{}';
  chosen uuid := nullif(p->>'chosen_option_id','')::uuid;
begin
  insert into public.budget_items (id, trip_id, title, category, day_date, planned_amount, qty, currency, rate,
                                   is_fixed, status, booking_ref, url, note, created_at)
  values (bid, (p->>'trip_id')::uuid, p->>'title', coalesce(p->>'category','other'), nullif(p->>'day_date','')::date,
          coalesce((p->>'planned_amount')::numeric,0), greatest(1, coalesce((p->>'qty')::int,1)), coalesce(p->>'currency','CNY'),
          coalesce((p->>'rate')::numeric,1), coalesce((p->>'is_fixed')::boolean,false), coalesce(p->>'status','idea'),
          coalesce(p->>'booking_ref',''), nullif(p->>'url',''), coalesce(p->>'note',''), coalesce((p->>'created_at')::timestamptz, now()))
  on conflict (id) do update set trip_id = excluded.trip_id, title = excluded.title, category = excluded.category,
    day_date = excluded.day_date, planned_amount = excluded.planned_amount, qty = excluded.qty, currency = excluded.currency,
    rate = excluded.rate, is_fixed = excluded.is_fixed, status = excluded.status, booking_ref = excluded.booking_ref,
    url = excluded.url, note = excluded.note, chosen_option_id = null;
  for o in select * from jsonb_array_elements(coalesce(p->'options','[]'::jsonb)) loop
    keep := keep || (o->>'id')::uuid;
    insert into public.price_options (id, budget_item_id, label, mode, channel, price, currency, rate, duration_minutes,
                                      transfers, convenience, refund_policy, url, note, checked_at, pos)
    values ((o->>'id')::uuid, bid, o->>'label', coalesce(o->>'mode',''), coalesce(o->>'channel',''),
            coalesce((o->>'price')::numeric,0), coalesce(o->>'currency','CNY'), coalesce((o->>'rate')::numeric,1),
            nullif(o->>'duration_minutes','')::int, nullif(o->>'transfers','')::int, nullif(o->>'convenience','')::smallint,
            nullif(o->>'refund_policy',''), nullif(o->>'url',''), coalesce(o->>'note',''),
            nullif(o->>'checked_at','')::timestamptz, i)
    on conflict (id) do update set label = excluded.label, mode = excluded.mode, channel = excluded.channel,
      price = excluded.price, currency = excluded.currency, rate = excluded.rate, duration_minutes = excluded.duration_minutes,
      transfers = excluded.transfers, convenience = excluded.convenience, refund_policy = excluded.refund_policy,
      url = excluded.url, note = excluded.note, checked_at = excluded.checked_at, pos = excluded.pos
    where public.price_options.budget_item_id = bid;
    i := i + 1;
  end loop;
  delete from public.price_options where budget_item_id = bid and not (id = any(keep));
  if chosen is not null and chosen = any(keep) then
    update public.budget_items set chosen_option_id = chosen where id = bid;
  end if;
end $$;

create or replace function public.delete_budget_item(bid uuid) returns void
language sql security invoker set search_path = '' as $$ delete from public.budget_items where id = bid $$;

-- ---------- 授权：仅登录用户可调用 ----------
do $$ declare f text; begin
  foreach f in array array['pull_all()','save_profile(jsonb)','save_person(jsonb)','archive_person(uuid)','resolve_person(text)',
    'save_trip(jsonb)','delete_trip(uuid)','save_expense(jsonb)','delete_expense(uuid)','save_budget_item(jsonb)','delete_budget_item(uuid)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
