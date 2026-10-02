-- 拆分 share_pack_items 写策略，避免与 select 策略重复（performance advisor: multiple_permissive_policies）
drop policy pack_items_write on public.share_pack_items;
create policy pack_items_insert on public.share_pack_items for insert to authenticated with check (
  exists (select 1 from public.share_packs p where p.id = pack_id and p.owner_id = (select auth.uid())));
create policy pack_items_update on public.share_pack_items for update to authenticated using (
  exists (select 1 from public.share_packs p where p.id = pack_id and p.owner_id = (select auth.uid()))) with check (
  exists (select 1 from public.share_packs p where p.id = pack_id and p.owner_id = (select auth.uid())));
create policy pack_items_delete on public.share_pack_items for delete to authenticated using (
  exists (select 1 from public.share_packs p where p.id = pack_id and p.owner_id = (select auth.uid())));
