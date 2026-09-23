-- ============================================================
-- ESQUEMA COMPLETO — Carta Don Ramón Pâtisserie (Supabase/Postgres)
-- Corré este script completo en Supabase → SQL Editor
-- ============================================================

-- Si en un intento anterior creaste una tabla "stock" suelta,
-- este esquema la reemplaza por completo (el stock ahora vive
-- en producto_precios, por combinación producto + tamaño).
drop table if exists public.stock cascade;
drop function if exists public.decrement_stock(text, integer);

-- ------------------------------------------------------------
-- 1. RUBROS (categorías: Café, Infusiones, Salados, etc.)
-- ------------------------------------------------------------
create table if not exists public.rubros (
    id          bigint generated always as identity primary key,
    nombre      text not null,
    orden       integer not null default 0,
    bcondicion  boolean not null default true,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 2. TAMAÑOS (Chico, Mediano, Grande, XL, 10 cm...)
-- ------------------------------------------------------------
create table if not exists public.tamanios (
    id          bigint generated always as identity primary key,
    nombre      text not null,
    bcondicion  boolean not null default true,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 3. PRODUCTOS (un producto = una tarjeta en la carta)
-- ------------------------------------------------------------
create table if not exists public.productos (
    id          bigint generated always as identity primary key,
    nombre      text not null,
    descripcion text,
    rubro_id    bigint not null references public.rubros(id),
    icono       text default '🍽️',
    -- estado editorial manual, independiente del stock numérico:
    -- 'disponible' | 'consultar' | 'pendiente' | 'sin_stock'
    estado      text not null default 'disponible',
    orden       integer not null default 0,
    bcondicion  boolean not null default true,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 4. PRODUCTO_PRECIOS (precio + stock por combinación
--    producto+tamaño; tamanio_id null = "precio único")
-- ------------------------------------------------------------
create table if not exists public.producto_precios (
    id            bigint generated always as identity primary key,
    producto_id   bigint not null references public.productos(id),
    tamanio_id    bigint references public.tamanios(id),
    precio        numeric(10, 2) not null,
    -- null = "no se controla stock para esta variante" (sin límite)
    stock         integer,
    bcondicion    boolean not null default true,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now()
);

create index if not exists idx_producto_precios_producto
    on public.producto_precios(producto_id);

create index if not exists idx_productos_rubro
    on public.productos(rubro_id);

-- ============================================================
-- SEGURIDAD (Row Level Security)
--
-- Lectura pública: solo filas activas (bcondicion = true).
-- Los usuarios autenticados (el/los admin, creados a mano
-- desde el Dashboard de Supabase — no hay alta pública) ven
-- TODO (incluidas las filas dadas de baja) y pueden escribir.
-- ============================================================

alter table public.rubros enable row level security;
alter table public.tamanios enable row level security;
alter table public.productos enable row level security;
alter table public.producto_precios enable row level security;

-- --- rubros ---
create policy "rubros_select" on public.rubros
    for select using (bcondicion = true or auth.role() = 'authenticated');

create policy "rubros_insert" on public.rubros
    for insert with check (auth.role() = 'authenticated');

create policy "rubros_update" on public.rubros
    for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- --- tamanios ---
create policy "tamanios_select" on public.tamanios
    for select using (bcondicion = true or auth.role() = 'authenticated');

create policy "tamanios_insert" on public.tamanios
    for insert with check (auth.role() = 'authenticated');

create policy "tamanios_update" on public.tamanios
    for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- --- productos ---
create policy "productos_select" on public.productos
    for select using (bcondicion = true or auth.role() = 'authenticated');

create policy "productos_insert" on public.productos
    for insert with check (auth.role() = 'authenticated');

create policy "productos_update" on public.productos
    for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- --- producto_precios ---
create policy "producto_precios_select" on public.producto_precios
    for select using (bcondicion = true or auth.role() = 'authenticated');

create policy "producto_precios_insert" on public.producto_precios
    for insert with check (auth.role() = 'authenticated');

create policy "producto_precios_update" on public.producto_precios
    for update using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- ============================================================
-- FUNCIÓN: descuento atómico de stock
--
-- Se llama desde la carta pública al confirmar un pedido por
-- WhatsApp. Es atómica (UPDATE con condición WHERE stock >=
-- cantidad) para que dos pedidos simultáneos no vendan la
-- misma última unidad.
-- ============================================================
create or replace function public.decrement_stock(
    p_producto_precio_id bigint,
    p_amount integer
)
returns integer
language plpgsql
security definer
as $$
declare
    v_new_quantity integer;
begin
    update public.producto_precios
    set stock = stock - p_amount,
        updated_at = now()
    where id = p_producto_precio_id
      and stock is not null
      and stock >= p_amount
    returning stock into v_new_quantity;

    if v_new_quantity is null then
        raise exception 'Stock insuficiente para producto_precio_id %', p_producto_precio_id;
    end if;

    return v_new_quantity;
end;
$$;

grant execute on function public.decrement_stock(bigint, integer) to anon, authenticated;

-- ============================================================
-- DATOS INICIALES (rubros y tamaños — coinciden con tu carta actual)
-- Los productos y precios los cargás desde el panel admin.
-- ============================================================

insert into public.rubros (nombre, orden) values
    ('Café', 1),
    ('Infusiones', 2),
    ('Pastelería y laminados', 3),
    ('Salados', 4),
    ('Adicionales', 5)
on conflict do nothing;

insert into public.tamanios (nombre) values
    ('Chico'), ('Mediano'), ('Grande'), ('XL'), ('10 cm'), ('Único')
on conflict do nothing;
