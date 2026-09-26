-- ============================================================
-- MIGRACIÓN: políticas de seguridad para promociones y promocion_items
-- Versión idempotente: se puede correr las veces que haga falta,
-- no falla si las políticas ya existen de un intento anterior.
-- ============================================================

alter table public.promociones enable row level security;
alter table public.promocion_items enable row level security;

-- --- promociones ---
drop policy if exists "promociones_select" on public.promociones;
create policy "promociones_select" on public.promociones
    for select using (bcondicion = true or auth.role() = 'authenticated');

drop policy if exists "promociones_insert" on public.promociones;
create policy "promociones_insert" on public.promociones
    for insert with check (auth.role() = 'authenticated');

drop policy if exists "promociones_update" on public.promociones;
create policy "promociones_update" on public.promociones
    for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- --- promocion_items ---
drop policy if exists "promocion_items_select" on public.promocion_items;
create policy "promocion_items_select" on public.promocion_items
    for select using (true);

drop policy if exists "promocion_items_insert" on public.promocion_items;
create policy "promocion_items_insert" on public.promocion_items
    for insert with check (auth.role() = 'authenticated');

drop policy if exists "promocion_items_delete" on public.promocion_items;
create policy "promocion_items_delete" on public.promocion_items
    for delete using (auth.role() = 'authenticated');