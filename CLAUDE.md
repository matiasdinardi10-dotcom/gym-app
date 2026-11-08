# CLAUDE.md — MD Pro Training

Guía para trabajar en este repo sin romper nada. **La app la usan alumnos reales.**
Todo lo de acá está verificado leyendo el código, salvo lo marcado como **(no verificado)**.
Los números de línea son aproximados (referencia al momento de escribir esto); buscá por nombre de función.

---

## 1. Qué es la app

PWA de entrenamiento personal, en español (Uruguay). Un único archivo `app.html` con HTML + CSS + JS inline, sin build, sin frameworks, sin dependencias npm. Backend: Supabase (REST + Auth). Hosting: Vercel.

**Login** (`doLogin`): autentica contra Supabase Auth (email + contraseña). Si el email es igual a la constante `PROFE_EMAIL` → panel profe (`initProfe`). Si no, busca el email en la tabla `clientes`; si existe → panel alumno (`initAlumno`); si no existe, muestra "No encontramos tu cuenta".
La sesión se guarda en `sessionStorage` (`auth_token`, `auth_email`, `rol`, `cliente_id`) y `window.onload` la restaura.
**Registro** (`doRegister`): crea el usuario en Supabase Auth y una fila en `clientes` con `estado:'nuevo'`.

Ojo: las llamadas a la base (`SBH`) mandan la clave pública como `apikey` y como `Authorization: Bearer`, **no** el token del usuario logueado. Cómo están configuradas las políticas RLS en Supabase: **(no verificado)** — no está en el repo.

### Panel profe (admin) — `#panel-profe`
Navegación inferior con 4 pantallas (`pSwitchScreen`):
- **Clientes** (`#p-screen-clientes`): lista de alumnos con indicador de actividad de hoy (entrenó / sesión pendiente / sin sesión), buscador, detalle, alta/edición/baja de clientes.
- **Rutinas** (`#p-screen-rutinas`): selector de alumno + 3 sub-pestañas (`rutSwitchTab`):
  - *Rutina*: calendario/tira de días y la rutina día a día de ese alumno (agregar ejercicio, biserie o circuito; editar; borrar; reordenar). Muestra historial de cargas por ejercicio.
  - *Sesiones*: lo que el alumno registró, agrupado por fecha (`rutLoadSesionesAlumno`).
  - *Feedback*: comentarios (`devolucion`) que dejó el alumno (`rutRenderFeedback`).
- **Biblioteca** (`#p-screen-biblioteca`): ejercicios guardados con link de YouTube; se usan para autocompletar.
- **Plantillas** (`#p-screen-plantillas`): rutinas fijas (lista de ejercicios con series/reps y video) asignables a varios alumnos.

### Panel alumno — `#panel-alumno`
Navegación inferior con 4 pestañas (`aSwitchTab`): **Inicio**, **Timer**, **Progreso**, **Perfil**.
- **Inicio**: tira semanal de días, botón "📋 Mis rutinas" (plantillas), y los ejercicios del día seleccionado. El alumno abre cada ejercicio, carga series (kg / reps / RPE-RIR), marca "Completado" / "No completado", deja comentario y guarda la sesión. Un día con logs queda "cerrado" (se puede "Corregir" cada ejercicio).
- **Timer**: intervalos (trabajo/descanso/rondas/ciclos), cronómetro y cuenta regresiva, con beeps y vibración.
- **Progreso**: gráfico (canvas) de peso máximo por sesión por ejercicio, con filtro 1m/3m/6m/todo.
- **Perfil**: avatar (foto o preset), racha, días completados, calendario de actividad, cerrar sesión.

---

## 2. Archivos y despliegue

| Archivo | Qué es |
|---|---|
| `app.html` | Toda la app (≈3580 líneas). |
| `sw.js` | Service worker. `CACHE_NAME` (hoy `md-pro-training-v5`), cachea `/app.html` y `/manifest.json`. Estrategia network-first: intenta la red y si falla usa la caché. |
| `manifest.json` | Manifest PWA. `start_url: /app.html`, íconos `icon-192.png` / `icon-512.png`. |
| `vercel.json` | Un solo rewrite: `/` → `/app.html`. |
| `icon-192.png`, `icon-512.png` | Íconos de la PWA (rayo oro sobre negro). |
| `supabase/activar-videos-y-orden.sql` | SQL a correr una vez en el SQL Editor de Supabase: columna `ejercicios.orden`, bucket `sesion-archivos` y sus permisos. |
| `README.md` | Solo dice `# gym-app`. |

**Despliegue:** push a `main` → Vercel despliega automáticamente (según el dueño del repo; la config de Vercel no está en el repo, así que el auto-deploy en sí es **(no verificado)** desde el código). No hay paso de build ni tests automáticos.

`sw.js` se registra al final de `app.html` (`navigator.serviceWorker.register('/sw.js')`).

---

## 3. Mapa de `app.html`

| Líneas aprox. | Sección |
|---|---|
| 1–16 | `<head>`: metas PWA, manifest, Google Fonts (Anton + Inter + JetBrains Mono). |
| 15–608 | `<style>`: variables en `:root`, LOGIN, SHARED, PANEL ALUMNO (circuitos, sesión, resumen, progreso), PANEL PROFE, TIMER, BISERIE, REORDEN. |
| 612–656 | HTML login/registro (`#login-screen`). |
| 658–833 | HTML panel alumno: `#a-view-home`, `#a-view-session`, `#a-view-summary`, `#a-view-progress`, `#a-view-plantillas`, `#a-view-timer`, `#a-view-perfil`, nav `#a-bottom-nav`. |
| 835–1072 | HTML panel profe: pantallas `#p-screen-*`, modales (`#cl-modal`, `#ex-modal`, `#edit-ex-modal`, `#edit-circuit-modal`, `#circuit-modal`) y nav. |
| 1074–1075 | `#file-input` (adjuntos alumno) y `#toast`. |
| 1077–3579 | `<script>` (todo el JS). |

### JS — Config y helpers (≈1078–1200)
- Constantes: `SB_URL`, `SB_KEY`, `SBH` (headers), `PROFE_EMAIL`, `TODAY = localDateStr()`, `DAYS`, `QUOTES`.
- `localDateStr(date)`: fecha local `YYYY-MM-DD`.
- Helpers DB: `dbGet`, `dbPost`, `dbPatch`, `dbDelete`, `dbGetAll` (ver sección 4).
- `formatSeries`, `showToast`, `togglePwd`, `hideLogin`.
- **Circuitos y biseries se guardan en la tabla `ejercicios` codificados en texto**:
  - Circuito: `nombre = '__CIRCUIT__' + nombre`; `nota = modalidad + '\n---\n' + 'item|||yt'` por línea. Helpers: `isCircuit`, `parseCircuit`, `serializeCircuit`.
  - Biserie: `nombre = '__BISERIE__' + nombreA + '|||' + nombreB`; `nota = 'series|||peso|||tiempo|||nota|||yt' (A) + '\n---\n' + (B)`. Helpers: `isBiserie`, `parseBiserie`, `serializeBiserie`.
  - No cambiar estos formatos: hay datos reales guardados así.

### JS — Auth (≈1201–1280)
`switchAuthTab`, `initRegisterAvatars`, `regSelectAvatar`, `doLogin`, `doRegister`, `doLogout`.

### JS — Panel alumno (≈1281–2248)
- Estado: `aCurrentCliente`, `aEjercicios`, `aLogs`, `aSelectedDate`, `aSessionExs`, `aSessionIdx`, `aSessionState`, `aSessionStateCache` (guarda lo escrito por fecha al cambiar de día).
- Carga: `initAlumno` → `aRefreshData` (rutinas + logs del alumno, luego ejercicios de esas rutinas). `aDoRefresh` = botón ↻.
- Navegación: `aSwitchTab(tab)` (`'inicio' | 'timer' | 'progreso' | 'perfil'`), `aHideAllViews` (lista de vistas; si agregás una vista nueva, sumala ahí), `aShowHome`.
- Inicio: `aBuildDayStrip`, `aWeekShift`, `aSelectDay`, `aRenderHome`, `aIsDayClosed`, `aCalcStreak`, `aRenderCircuitPreview`, `aRenderDoneCircuit`.
- Sesión: `aOpenExercise`, `aRenderCard` (normal / biserie / circuito), `aSetStatus`, `aSaveCurrentCard`, `aNavSession`, `aSaveCardAndNext`, `aExitSession`.
- **Fotos y videos adjuntos** (solo en ejercicios normales): `aOpenFileInput`, `aHandleFileUpload` (fotos: `compressImage` → data URL; videos: `uploadVideo` al bucket `ARCH_BUCKET` con progreso; guarda al instante en `sesion_archivos`), `aLoadArchivos` (caché `aArchivosCache` por fecha), `aFillAttachBoxes` (llena los `[data-attach-ex]` de la tarjeta y del día cerrado), `aDeleteArchivo` (borra la fila y, si es video, el archivo de Storage), `openMediaViewer` (foto/video a pantalla completa). Helpers compartidos: `archivoSrcOk` (solo data URL de imagen o links del bucket propio), `archivosThumbsHtml`.
- Resumen y guardado: `aShowSummary`, `aSummaryGoTo`, **`aSaveFinalSession`** (escribe en `logs_entrenamiento` y hace PATCH de `ejercicios.completado` / `devolucion`).
- Corregir día cerrado: `aEditExercise`, `aEditBiserie`, `aEditCircuit` (borran el log de ese día y resetean `completado`).
- **"Mis rutinas"**: `aShowPlantillas()` (≈1558) lee `plantillas` filtrando `cliente_ids` que contenga el id del alumno (`cs.{id}`) y las muestra como `<details>` de solo lectura (nombre, series, link de video). Escape con `aPlEsc`.
- Progreso: `aBuildProgressView`, `aGetExercisesWithLogs`, `aExtractWeight`, `aGetFilteredLogs`, `aRenderProgressChart`, `aDrawLineChart`, `aFilterProgressChips`, `aSelectFromSearch`, `aSelectProgressEx`, `aPeriod`.
- Perfil/avatar: `aRenderPerfil`, `aRenderAvatar`, `aRenderHeaderAvatar`, `openAvatarModal`, `aSelectPreset`, `aUploadAvatar`, `AVATAR_PRESETS`.

### JS — Panel profe (≈2250–3140)
- Estado: `pClientes`, `pAllEjercicios` (cada uno con `_clientId` agregado en memoria), `pAllLogs`, `pAllSesiones`, `pBiblioteca`.
- **`initProfe()`** (≈2256): carga en paralelo `clientes` y `biblioteca_ejercicios` con `dbGet`, y `sesiones`, `rutinas`, `ejercicios`, `logs_entrenamiento` con `dbGetAll`. Mapea `rutina_id → cliente_id` para poner `_clientId` en cada ejercicio. Llena los `<select>` de cliente y llama `clRenderList`, `rutBuildCalStrip`, `rutRenderDay`, `rutRenderBiblioteca`.
- **`pSwitchScreen(name)`**: `'clientes' | 'rutinas' | 'biblioteca' | 'plantillas'`. Al entrar a biblioteca llama `rutRenderBiblioteca`; a plantillas, `plRender`.
- Clientes: `clRenderList`, `clRenderFiltered`, `filterClients`, `clShowDetail`, `showClientList`, `openClientModal`, `openEditClientModal`, `saveClient`, `deleteClient`, `pGetActivityToday`, `activityDot`.
- Historial de cargas: `pGetLoadHistory`, `pRenderLoadHistoryBlock`, `pRenderModalLoadHistory`.
- **Calendario de rutinas del profe**: `rutBuildCalStrip` (tira de 14 días alrededor de hoy + `rutStripOffset`), `rutSelectDate`, `rutShiftStrip(±14)`, `rutPickDate` (input date + botón "Hoy"), `rutOnClientChange`, `rutSwitchTab`.
- **Rutinas día a día**: `rutRenderDay` (lista los `ejercicios` del alumno con `fecha_sesion === rutSelectedDate`; si hay logs ese día oculta los botones de agregar y muestra "El alumno ya completó esta sesión"), `rutToggleDetail`, `rutRemoveEx`.
  - Agregar: `openExModal` / `addExercise` (ejercicio o biserie con `toggleBiserieField`), `openCircuitModal` / `saveCircuit`. Ambos buscan la primera fila de `rutinas` del alumno (`limit=1`) y si no existe la crean ("Rutina de …"); el ejercicio se inserta con `rutina_id` y `fecha_sesion`.
  - Editar: `openEditExModal` / `saveEditExercise`, `openEditCircuitModal` / `saveEditCircuit`.
  - Autocompletado desde biblioteca: `onNameInput`, `rutSelectExercise`, `onNameInputB`, `rutSelectExerciseB`, `onCircuitItemInput`, `selectCircuitItem`, `onEditCircuitItemInput`, `selectEditCircuitItem`.
  - **Orden de ejercicios**: columna `ejercicios.orden` (la crea el SQL de `supabase/`). Helpers globales `exOrderKey` / `sortExs` (con `orden` si existe; si no, por `id`), usados por el alumno (`aRenderHome`) y el profe (`rutApplyOrder`). `rutMoveEx` guarda con `rutPersistOrder`; `rutNextOrden` pone los ejercicios nuevos al final. `ordenColExists()` detecta si la columna existe: si no existe, se usa el orden viejo en `localStorage` del profe (`ex_order_<cliente>_<fecha>`) y el alumno ve el orden de carga. Si existe, un orden que solo estaba en `localStorage` se pasa a la base una vez.
- Fotos del alumno en la rutina del día: `pFillAttachBoxes` (llena los `[data-p-attach-ex]`, caché `pArchivosCache` por `cliente_fecha`; `rutSelectDate` la refresca).
- Sesiones/feedback: `rutLoadSesionesAlumno`, `rutRenderFeedback`.
- Biblioteca: `rutRenderBiblioteca`, `addToBiblioteca`, `deleteBib`.
- **Plantillas (funciones `pl*`)** (≈3037–3126): estado `plData`, `plEjs`, `plClientes`, `plEditingId`. `plRender` (entrada a la pantalla), `plLoad`, `plRenderEx`, `plSetEx`, `plAc` / `plPick` (autocompletado desde biblioteca), `plAddEx`, `plDelEx`, `plRenderClientes`, `plToggleCli`, `plRenderList`, `plReset`, `plEdit`, `plSave`, `plDelete`, `plEsc` (escape HTML).

### JS — Init, Timer y SW (≈3140–3578)
- `window.onload`: restaura sesión desde `sessionStorage` o muestra el login.
- Timer: `timerState`, `TIMER_PHASES`, `timerMode`, `timerSetMode`, `timerRender`, `timerDOMUpdate`, `timerStart/Pause/Resume/Stop/Reset/Skip`, `timerTick`, `timerNextPhase`; cronómetro `sw*`; cuenta regresiva `cd*`; audio `getAudioCtx`, `unlockAudio`, `playBeep`, `timerVibrate`, `timerCountdownBeep`.
- Registro del service worker.

---

## 4. Base de datos (Supabase REST)

### Helpers (≈1106–1120)
- `dbGet(tabla, query)` → GET `/rest/v1/<tabla>?<query>`. **Máximo 1000 filas.**
- `dbGetAll(tabla, query)` → igual pero pagina con header `Range` de a 1000 hasta traer todo.
- `dbPost(tabla, body)` → POST con `Prefer: return=representation` (devuelve array con la fila creada, usar `res[0]`).
- `dbPatch(tabla, id, body)` → PATCH `?id=eq.<id>`.
- `dbDelete(tabla, id)` → DELETE `?id=eq.<id>`.
- Todos tiran `Error` si la respuesta no es ok. Los filtros usan sintaxis PostgREST (`eq.`, `in.(…)`, `cs.{…}`, `order=`).

### Tablas y campos usados en el código
Tipos exactos y restricciones en Supabase: **(no verificado)**. Todas usan `id` como clave.

- **`clientes`**: `id`, `nombre`, `email`, `edad`, `contacto`, `objetivo`, `estado` (`'activo'` | `'nuevo'`), `fecha_alta`.
- **`biblioteca_ejercicios`**: `id`, `nombre`, `link_youtube`.
- **`rutinas`**: `id`, `cliente_id`, `nombre`, `fecha`. En la práctica funciona como contenedor por alumno (se usa la primera).
- **`ejercicios`** (la rutina día a día): `id`, `rutina_id`, `nombre`, `series`, `reps` (sin uso en el código), `peso`, `tiempo`, `nota`, `link_youtube`, `completado` (bool), `devolucion` (comentario del alumno), `fecha_sesion` (`YYYY-MM-DD`), `orden` (int, opcional; solo existe después de correr el SQL). Circuitos y biseries viven acá con los prefijos `__CIRCUIT__` / `__BISERIE__`.
- **`logs_entrenamiento`**: `id`, `cliente_id`, `ejercicio_id`, `fecha`, `series_realizadas` (texto, ej. `S1: 60kg 8 reps | S2: …`; biserie `A-S1: … || B-S1: …`), `peso_usado`, `rpe`, `nota`.
- **`sesiones`**: el profe la carga con `dbGetAll('sesiones','order=fecha.asc,id.asc')` en `pAllSesiones`, pero **ninguna otra parte del código la usa**. Campos: solo se ve que tiene `fecha` e `id` **(resto no verificado)**.
- **`plantillas`**: `id`, `nombre`, `ejercicios` (array JSON de `{nombre, series, link}`), `cliente_ids` (array de ids de clientes; se filtra con `cs.{id}`).
- **`sesion_archivos`** (fotos adjuntas del alumno): `id`, `created_at`, `cliente_id`, `ejercicio_id`, `fecha`, `url`, `tipo`. Columnas confirmadas consultando la API; puede tener otras **(no verificado)**. Fotos: se comprimen en el navegador (máx. 1280 px, JPEG) y se guardan como data URL en `url`, `tipo:'imagen'`. Videos: se suben al bucket público `sesion-archivos` de Supabase Storage (ruta `<cliente_id>/<fecha>/<archivo>`, máx. 50 MB) y en `url` queda el link público, `tipo:'video'`. El bucket lo crea el SQL de `supabase/`; si no existe, la app avisa que falta activarlo.

### Datos que NO están en la base
- Avatar del alumno: `localStorage` (`avatar_<email>`), por dispositivo.
- Orden de ejercicios del profe: `localStorage` (`ex_order_<cliente>_<fecha>`), por dispositivo.

---

## 4b. Diseño (identidad visual)

- **Paleta** (tokens en `:root`): Negro hierro `#0B0B0B` (`--bg`, ~60%), Grafito `#26262A` (`--surface-2`; tarjetas `--surface`), Oro `#C9A227` (`--gold`, acento/CTA/datos clave, ~10%), Hueso `#EDE6D6` (`--text`). Error `--red` `#E0524A`. Circuitos en hueso, biseries en `--biserie` `#DEC478`.
- Ojo: la variable **`--green` es el acento y hoy vale oro** (se dejó el nombre porque la usan cientos de estilos). Para color nuevo usar `--gold`.
- **Tipografías**: Anton (`--font-display`) para títulos en MAYÚSCULAS e interlineado ~0.95; Inter (`--font-body`) para texto y UI; JetBrains Mono (`--font-mono`) para datos (series, kilos, tiempos) y etiquetas. Máximo esas 3 familias.
- Estilo: plano y serio. **Sin brillos/neón** (`box-shadow`/`text-shadow` de color), sin degradados en botones. Botón principal = oro sólido con texto negro en mayúsculas.
- La capa de marca está al final del `<style>` (bloque `MARCA`). Para retocar el look, preferir esa capa antes que tocar estilos sueltos.
- UX: inputs de series con `inputmode="decimal"` (teclado numérico), campos a 16px (evita zoom en iPhone), botones de al menos 48px, `env(safe-area-inset-bottom)` en la barra inferior, `:focus-visible` dorado, `prefers-reduced-motion`.
- No usar el logo ni contenidos del manual de referencia: solo paleta y tipografías.

---

## 5. Reglas que no se pueden romper

1. **El archivo principal se llama exactamente `app.html`.** `vercel.json`, `manifest.json` (`start_url`) y `sw.js` lo referencian. Si se renombra, la web deja de existir.
2. **Fechas locales: usar siempre `localDateStr()`; nunca `toISOString()`.** `toISOString()` da UTC y en Uruguay (UTC-3) a la noche cambia de día. Hoy el código no usa `toISOString()` en ningún lado: mantenerlo así. Para parsear una fecha `YYYY-MM-DD` el código usa `new Date(fecha + 'T00:00:00')` (hora local).
3. **Supabase corta cada consulta en 1000 filas.** Para tablas grandes (`ejercicios`, `logs_entrenamiento`, `sesiones`, `rutinas`) usar `dbGetAll`, que pagina.
   - Ojo, existente hoy: el panel alumno (`aRefreshData`, y la recarga de logs en `aSaveFinalSession`) usa `dbGet` para `rutinas`, `logs_entrenamiento` y `ejercicios` filtrados por alumno. Si un alumno pasa las 1000 filas, se pierden datos. No cambiarlo sin pedirlo, pero tenerlo en cuenta.
4. **Solo la clave pública de Supabase puede estar en el código** (la constante `SB_KEY`, que es una clave `sb_publishable_…` / anon). **Nunca** poner una `service_role` ni ninguna clave secreta. No copiar claves ni la URL del proyecto en docs, commits o mensajes.
5. **`sw.js` cachea con un nombre de versión (`CACHE_NAME`).** Si se agregan o separan archivos (CSS/JS aparte, íconos, etc.), agregarlos a `ASSETS` y subir la versión (`md-pro-training-v4` → `v5`…), así los teléfonos de los alumnos dejan la caché vieja.
6. **La sección Cobros fue eliminada de la interfaz.** No dejar referencias a sus elementos HTML: `getElementById` de algo que no existe da `null` y rompe en silencio. Los restos que quedaban (`cob-client`, `cob-t-client`, `cobCalMonth`, `cobCalYear`) ya se borraron: no volver a agregar nada de Cobros.
7. **Plantillas = solo lectura para el alumno** (ejercicio, series/reps, video). No tienen seguimiento, ni logs, ni "completado". **Las rutinas día a día (`ejercicios` con `fecha_sesion`) sí tienen seguimiento** (`logs_entrenamiento`, `completado`, `devolucion`). No mezclar los dos.
8. **No cambiar los formatos de texto codificado** (`__CIRCUIT__`, `__BISERIE__`, separadores `|||`, `\n---\n`, ` | `, ` || `): hay datos reales guardados así y varias funciones los parsean.

### Otras cosas a tener en cuenta (verificadas)
- Código muerto ya borrado (no reintroducir): `pRenderDashboard`, `pGoToClient`, `plPickBib`, `rutLoadHistorial` + `#rut-historial`, y las versiones duplicadas de `aShowProgress` / `aShowTimer`. La navegación usa `aSwitchTab` / `pSwitchScreen`.
- Seguridad: el rol profe se decide solo en el navegador (`PROFE_EMAIL` + `sessionStorage`), y todas las consultas van con la clave pública. La protección real depende de las políticas RLS de Supabase **(no verificado)**.
- Mucho HTML se arma con template strings e `innerHTML` sin escapar (salvo plantillas, que usan `plEsc` / `aPlEsc`).

---

## 6. Forma de trabajo

- El dueño escribe en **español informal (rioplatense)**. Responder en español, con **pasos claros y numerados**.
- **Todo cambio va en una rama**, nunca directo a `main` (push a `main` = deploy a producción para los alumnos).
- **Las pruebas escriben en la base real de Supabase.** Usar siempre un **alumno de prueba**, nunca datos de alumnos reales.
- No hay tests ni linter. Para probar: abrir `app.html` en el navegador (por ejemplo con un servidor estático local) y loguearse con el alumno de prueba.
- Cambios chicos y puntuales; `app.html` es un archivo único y grande, editar con cuidado y buscar por nombre de función.
