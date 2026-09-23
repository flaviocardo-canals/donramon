# Don Ramón Pâtisserie · Carta digital + Admin

Sitio 100% estático (HTML/CSS/JS), sin servidor propio. La base de datos y
la autenticación corren en **Supabase**; el hosting es **GitHub Pages**
(gratis).

## Archivos

| Archivo       | Qué es                                                             |
|---------------|----------------------------------------------------------------------|
| `schema.sql`  | Esquema completo de la base (tablas, seguridad, función de stock). Se corre una sola vez en Supabase. |
| `index.html`  | La carta pública — lo que ven los clientes.                        |
| `admin.html`  | Panel de administración — alta/baja de rubros, tamaños, productos y precios/stock. |

---

## 1. Crear el proyecto en Supabase

1. Entrá a [supabase.com](https://supabase.com) → creá una cuenta gratis → **New project**.
2. Elegí una contraseña de base de datos (guardala, no hace falta para esto pero por las dudas) y esperá a que el proyecto termine de aprovisionarse (1-2 min).

## 2. Cargar el esquema

1. En el panel de Supabase, andá a **SQL Editor** → **New query**.
2. Pegá el contenido completo de `schema.sql` y ejecutalo (▶ Run).
3. Confirmá que no haya errores. Esto crea las 4 tablas, la seguridad (RLS), la función de descuento de stock, y carga los rubros/tamaños iniciales.

## 3. Crear el usuario administrador

**No hay alta pública** — el/los admin se crean a mano desde el panel de Supabase:

1. Andá a **Authentication** → **Users** → **Add user** → **Create new user**.
2. Cargá el email y contraseña que va a usar quien administre la carta (vos, o quien maneje el local).
3. Repetí si necesitás más de un usuario admin.

## 4. Obtener las credenciales de conexión

1. Andá a **Project Settings** (ícono de engranaje) → **API**.
2. Copiá:
   - **Project URL** (algo como `https://xxxxx.supabase.co`)
   - **anon public** key (una clave larga, empieza con `eyJ...`)

## 5. Completar las credenciales en los archivos

Abrí **tanto `index.html` como `admin.html`** y reemplazá estas dos líneas (están cerca del final de cada archivo, dentro del `<script>`):

```js
const SUPABASE_URL = 'TU_SUPABASE_URL_AQUI';
const SUPABASE_ANON_KEY = 'TU_SUPABASE_ANON_KEY_AQUI';
```

por tus valores reales copiados en el paso 4. **Son las mismas credenciales en los dos archivos.**

> La `anon key` es pública por diseño (Supabase la pensó para vivir en el
> frontend) — la seguridad real la dan las políticas de RLS que ya
> quedaron configuradas en `schema.sql` (lectura pública solo de lo
> activo, escritura solo para usuarios logueados).

## 6. Cargar el menú desde el admin

1. Abrí `admin.html` en el navegador (podés probarlo localmente, doble click al archivo, no hace falta subirlo todavía).
2. Iniciá sesión con el usuario que creaste en el paso 3.
3. Cargá tus productos, tamaños y precios desde ahí. Los rubros y tamaños base ya vienen precargados por el `schema.sql`.

## 7. Subir a GitHub y publicar con GitHub Pages

```bash
git init
git add .
git commit -m "Carta digital Don Ramón + admin"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/TU_REPO.git
git push -u origin main
```

Después, en GitHub:

1. Andá a tu repo → **Settings** → **Pages**.
2. En **Source**, elegí **Deploy from a branch** → rama `main` → carpeta `/ (root)`.
3. Guardá. En un par de minutos tu carta va a estar en:
   `https://TU_USUARIO.github.io/TU_REPO/index.html`
4. El admin va a estar en:
   `https://TU_USUARIO.github.io/TU_REPO/admin.html`

> ⚠️ Como es un repo público (GitHub Pages gratis requiere repo público,
> salvo que tengas plan pago), cualquiera puede ver el código fuente,
> **incluida la `anon key`** — no importa, es pública por diseño. Pero
> **nunca subas ahí** la contraseña de la base de datos de Supabase ni
> ninguna "service role key" — esas sí son secretas y no van en este
> repo.

## Notas de mantenimiento

- **Dar de baja un producto/rubro/tamaño** no lo borra — solo lo oculta de la carta pública (`bcondicion = false`). Podés reactivarlo cuando quieras desde el admin.
- **El stock se descuenta solo** cuando un cliente confirma el pedido por WhatsApp (no al copiar el resumen). Si el stock llega a 0, la opción se marca automáticamente como agotada en la carta para todos los clientes.
- Si un pedido no se termina concretando (el cliente no vino a buscarlo), el stock **no se repone solo** — hay que ajustarlo a mano desde el admin ("Ajustar stock").
