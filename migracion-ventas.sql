-- ============================================================
-- MIGRACIÓN: tabla de ventas + registro manual/WhatsApp + corrección de bug
-- Corré esto completo en Supabase → SQL Editor (es idempotente,
-- se puede volver a correr sin romper nada)
-- ============================================================

-- ------------------------------------------------------------
-- 0. FIX: decrement_stock rechazaba ventas de productos con
--    stock "sin control" (null). Ahora null = no se controla,
--    nunca bloquea.
-- ------------------------------------------------------------
create or replace function public.decrement_stock(
    p_producto_precio_id bigint,
    p_amount integer
)
returns integer
language plpgsql
security definer
as $$
declare
    v_current_stock integer;
    v_new_quantity integer;
begin
    select stock into v_current_stock
    from public.producto_precios
    where id = p_producto_precio_id
    for update;

    if not found then
        raise exception 'producto_precio_id % no encontrado', p_producto_precio_id;
    end if;

    -- "Sin control" (null): no bloquea, no descuenta, no es error.
    if v_current_stock is null then
        return null;
    end if;

    if v_current_stock < p_amount then
        raise exception 'Stock insuficiente para producto_precio_id %', p_producto_precio_id;
    end if;

    update public.producto_precios
    set stock = stock - p_amount, updated_at = now()
    where id = p_producto_precio_id
    returning stock into v_new_quantity;

    return v_new_quantity;
end;
$$;

grant execute on function public.decrement_stock(bigint, integer) to anon, authenticated;

-- ------------------------------------------------------------
-- 1. TABLA DE VENTAS
-- ------------------------------------------------------------
create table if not exists public.ventas (
    id                  bigint generated always as identity primary key,
    fecha               date not null default current_date,
    hora                time not null default current_time,
    rubro_nombre        text not null,
    producto_nombre     text not null,
    tamanio_nombre      text,
    cantidad            integer not null check (cantidad > 0),
    precio_unitario     numeric(10,2) not null,
    precio_total        numeric(10,2) not null,
    producto_precio_id  bigint references public.producto_precios(id),
    promocion_id        bigint references public.promociones(id),
    venta_grupo_id      uuid,
    origen              text not null default 'manual' check (origen in ('manual', 'whatsapp')),
    created_at          timestamptz not null default now()
);

create index if not exists idx_ventas_fecha on public.ventas(fecha);

alter table public.ventas enable row level security;

-- Solo lectura para el admin logueado. NO hay políticas de insert/update/delete
-- a propósito: toda escritura pasa SOLO por las funciones de abajo (security definer),
-- nunca por INSERT/UPDATE/DELETE directo a la tabla — así cada venta queda siempre
-- consistente con el descuento de stock correspondiente.
drop policy if exists "ventas_select" on public.ventas;
create policy "ventas_select" on public.ventas
    for select using (auth.role() = 'authenticated');

-- ------------------------------------------------------------
-- 2. VENTA DESDE EL SITIO PÚBLICO (WhatsApp)
--    Recibe el carrito completo como un array JSON y lo procesa
--    TODO en una sola transacción: si algo falla, no queda nada
--    a medio registrar. Fecha/hora siempre del servidor (no se
--    puede falsificar desde el navegador). origen fijo 'whatsapp'.
-- ------------------------------------------------------------
create or replace function public.registrar_venta_whatsapp_lote(p_items jsonb)
returns void
language plpgsql
security definer
as $$
declare
    v_item jsonb;
    v_producto_precio_id bigint;
    v_cantidad integer;
    v_current_stock integer;
begin
    for v_item in select * from jsonb_array_elements(p_items)
    loop
        v_producto_precio_id := (v_item->>'producto_precio_id')::bigint;
        v_cantidad := (v_item->>'cantidad')::integer;

        if v_producto_precio_id is not null then
            select stock into v_current_stock
            from public.producto_precios
            where id = v_producto_precio_id
            for update;

            if v_current_stock is not null then
                if v_current_stock < v_cantidad then
                    raise exception 'Stock insuficiente para %', v_item->>'producto_nombre';
                end if;

                update public.producto_precios
                set stock = stock - v_cantidad, updated_at = now()
                where id = v_producto_precio_id;
            end if;
        end if;

        insert into public.ventas (
            fecha, hora, rubro_nombre, producto_nombre, tamanio_nombre,
            cantidad, precio_unitario, precio_total,
            producto_precio_id, promocion_id, venta_grupo_id, origen
        ) values (
            current_date, current_time,
            v_item->>'rubro_nombre', v_item->>'producto_nombre', v_item->>'tamanio_nombre',
            v_cantidad, (v_item->>'precio_unitario')::numeric,
            (v_item->>'precio_unitario')::numeric * v_cantidad,
            v_producto_precio_id,
            (v_item->>'promocion_id')::bigint,
            (v_item->>'venta_grupo_id')::uuid,
            'whatsapp'
        );
    end loop;
end;
$$;

grant execute on function public.registrar_venta_whatsapp_lote(jsonb) to anon, authenticated;

-- ------------------------------------------------------------
-- 3. VENTA MANUAL (desde el admin) — solo autenticados.
--    A diferencia de la anterior, permite elegir fecha/hora
--    (por si cargás una venta de más temprano) y se llama una
--    vez por cada línea (producto suelto, o una vez por cada
--    producto de una promo).
-- ------------------------------------------------------------
create or replace function public.registrar_venta_manual(
    p_producto_precio_id bigint,
    p_cantidad integer,
    p_rubro_nombre text,
    p_producto_nombre text,
    p_tamanio_nombre text,
    p_precio_unitario numeric,
    p_fecha date,
    p_hora time,
    p_promocion_id bigint default null,
    p_venta_grupo_id uuid default null
)
returns void
language plpgsql
security definer
as $$
declare
    v_current_stock integer;
begin
    if p_producto_precio_id is not null then
        select stock into v_current_stock
        from public.producto_precios
        where id = p_producto_precio_id
        for update;

        if v_current_stock is not null then
            if v_current_stock < p_cantidad then
                raise exception 'Stock insuficiente para %', p_producto_nombre;
            end if;

            update public.producto_precios
            set stock = stock - p_cantidad, updated_at = now()
            where id = p_producto_precio_id;
        end if;
    end if;

    insert into public.ventas (
        fecha, hora, rubro_nombre, producto_nombre, tamanio_nombre,
        cantidad, precio_unitario, precio_total,
        producto_precio_id, promocion_id, venta_grupo_id, origen
    ) values (
        p_fecha, p_hora, p_rubro_nombre, p_producto_nombre, p_tamanio_nombre,
        p_cantidad, p_precio_unitario, p_precio_unitario * p_cantidad,
        p_producto_precio_id, p_promocion_id, p_venta_grupo_id, 'manual'
    );
end;
$$;

grant execute on function public.registrar_venta_manual(
    bigint, integer, text, text, text, numeric, date, time, bigint, uuid
) to authenticated;

-- ------------------------------------------------------------
-- 4. ELIMINAR VENTA (repone stock automáticamente) — solo autenticados.
-- ------------------------------------------------------------
create or replace function public.eliminar_venta(p_venta_id bigint)
returns void
language plpgsql
security definer
as $$
declare
    v_producto_precio_id bigint;
    v_cantidad integer;
begin
    select producto_precio_id, cantidad into v_producto_precio_id, v_cantidad
    from public.ventas
    where id = p_venta_id;

    if not found then
        raise exception 'Venta % no encontrada', p_venta_id;
    end if;

    delete from public.ventas where id = p_venta_id;

    if v_producto_precio_id is not null then
        update public.producto_precios
        set stock = stock + v_cantidad, updated_at = now()
        where id = v_producto_precio_id
          and stock is not null;
    end if;
end;
$$;

grant execute on function public.eliminar_venta(bigint) to authenticated;
