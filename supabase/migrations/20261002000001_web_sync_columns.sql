-- 网页端同步：补充字段 + 原子读写 RPC（security invoker，全部受 RLS 约束）

alter table public.people        add column if not exists archived boolean not null default false; -- 已从成员列表移除，但历史账目仍引用
alter table public.profiles      add column if not exists initialized boolean not null default false;
alter table public.budget_items  add column if not exists qty int not null default 1 check (qty >= 1);
alter table public.price_options add column if not exists rate numeric(18,6) not null default 1 check (rate > 0);
alter table public.price_options add column if not exists refund_policy text check (refund_policy in ('yes','partial','no'));
alter table public.price_options add column if not exists pos int not null default 0;
alter table public.expense_shares add column if not exists pos int not null default 0;

-- 只允许本人插入 profiles（触发器之外的兜底）
create policy profiles_insert on public.profiles for insert to authenticated with check (id = (select auth.uid()));
