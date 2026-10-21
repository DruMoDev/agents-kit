# Fase 3: changelog y avisos. Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el formato de `CHANGELOG.md` se valide antes de fusionar, que el resumen de cada `kit-run` quede en el issue fijado "📦 Changelog" y que Dru reciba avisos en el móvil (ntfy) cuando un issue le necesita y al terminar cada `kit-run`.

**Architecture:** Tres scripts nuevos en la línea de los de la fase 2 (bash + `gh` + `jq` + `curl`, salidas 0/1/2 y línea `FIN:`): `kit-changelog.sh` (validar formato y publicar resumen), `kit-notify.sh` (adaptadores `ntfy`, `claude-push`, `none`) y `lib/transport.sh` (dónde corro). `kit-issue.sh decision|bloquear` avisan solos; `kit-pr.sh fusionar` exige un changelog bien formado; la skill `kit-run` usa el resto. El formato queda fijado por fixtures compartidos en `tests/fixtures/changelog/`, que la web (fase 4) reutilizará para su parser.

**Tech Stack:** bash, jq, gh, curl, git. Sin dependencias nuevas.

**Spec:** `docs/superpowers/specs/2026-10-18-agents-kit-plugin-design.md` (secciones "Changelog y avisos" y "Transporte").

## Global Constraints

- Scripts sin dependencias nuevas (shell + `gh` + `git` + `jq`; `curl` ya está en macOS y Linux).
- Códigos de salida: 0 bien, 1 rechazo o error de uso, 2 error de entorno. Éxito termina con `FIN: ...`.
- Toda llamada a `gh` lleva `--repo <slug>` o el slug en la ruta de la API.
- Nada se activa sin `.agents-kit.json` (`kit_require_marker`).
- Mensajes en español, sin rayas largas, lenguaje neutro.
- Los tests nunca tocan la red ni el origin real: `curl` y `gh` van con stubs; cada test empieza con `source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1`.
- Un aviso que falla nunca rompe el flujo: el script sale 2 y quien lo llama sigue.

## Rulings (decisiones del controlador, sin Dru)

- **Canal por defecto `ntfy`, no `claude-push`.** El spec pide verificar `claude-push` primero. La notificación push de Claude Code es una herramienta del modelo (`PushNotification`): solo existe dentro de una sesión de Claude Code, solo llega al móvil con Remote Control conectado y se omite si Dru está en la terminal. No la puede llamar un script, ni existe en Codex, OpenCode o `claude -p`. Así que no cumple "sin apenas configuración" de forma fiable y el spec manda caer a ntfy. `claude-push` se mantiene como adaptador: el script imprime `AVISO-CLAUDE: <mensaje>` y la skill, si corre en Claude Code, llama a `PushNotification` con ese texto. Coste si es erróneo: cambiar un valor por defecto en la plantilla.
- **Tema ntfy secreto y global:** `~/.agents-kit/ntfy-topic`, generado una vez (`agents-kit-` + 24 hex de `/dev/urandom`), permisos 600. `ntfyTopic` en el marcador lo sustituye. Así Dru se suscribe a un solo tema para todos sus repos.
- **Formato definido una vez por fixtures:** el validador es bash/awk (sin node en el plugin); la web tendrá su parser TS probado contra los mismos fixtures.
- **`fusionar` valida el changelog** solo si existe `CHANGELOG.md`; una PR sin entrada nueva es válida (cambios internos sin efecto visible).

## Review Focus

1. `CHANGELOG.md` recién creado por `kit-on` (solo cabecera con el ejemplo dentro de `<!-- -->`): debe ser válido y el ejemplo del comentario no cuenta como entrada.
2. Títulos con `·`, acentos, emojis o `:` dentro: la línea corta se reconoce por su final `· [#N](url)`.
3. Sin red o ntfy caído: `kit-notify.sh` sale 2 en ≤10 s y `kit-issue.sh decision` sigue saliendo 0.
4. `$HOME/.agents-kit` no existe o no es escribible: se crea con `mkdir -p`; si falla, exit 2 con mensaje claro.
5. Resumen repetido (relanzar el final de `kit-run`): no duplica el comentario en el issue fijado.

---

### Task 1: `scripts/lib/transport.sh` y `scripts/kit-notify.sh`

**Files:**
- Create: `scripts/lib/transport.sh`, `scripts/kit-notify.sh`, `tests/stubs/notify/curl`, `tests/test_notify.sh`
- Modify: `templates/agents-kit.json` (`"notify": "ntfy"`)

**Interfaces:**
- Produces: `kit_transport` (imprime `local` o `nube`; `nube` si `CLAUDE_CODE_REMOTE=true`, si no `local`). `scripts/kit-notify.sh <root> <titulo> <mensaje> [url]`.

Comportamiento de `kit-notify.sh`:
- `kit_require_marker`; canal = `kit_config <root> '.notify'`.
- `none`: imprime `FIN: sin-aviso`, exit 0.
- `claude-push`: imprime `AVISO-CLAUDE: <titulo>: <mensaje> <url>` y `FIN: claude-push`, exit 0.
- `ntfy`: tema = `.ntfyTopic` del marcador si es string no vacío; si no, `~/.agents-kit/ntfy-topic` (lo crea si falta, `umask 077`). Validar tema `^[A-Za-z0-9_-]{1,64}$` (exit 2 si no). `curl -fsS --max-time 10 -H "Title: <titulo>" [-H "Click: <url>"] -d "<mensaje>" "${KIT_NTFY_SERVER:-https://ntfy.sh}/<tema>"`. Éxito: `FIN: ntfy`. Fallo de curl: `error: no se pudo enviar el aviso por ntfy` en stderr, exit 2. Si el tema se acaba de crear, imprime antes `tema ntfy nuevo: <tema> (suscríbete en la app ntfy)`.
- Canal desconocido: exit 1 con `canal de aviso desconocido: <x>`.
- `kit_transport` = `nube`: `ntfy` y `none` funcionan igual; no hay nada más específico de nube en esta fase.
- Título y mensaje sin saltos de línea (los sustituye por espacios); la cabecera `Title` con UTF-8 va tal cual (ntfy la acepta).

Stub `tests/stubs/notify/curl`: registra argumentos en `$CURL_LOG`; `CURL_FAIL=1` sale 22.

- [ ] **Step 1: tests** en `tests/test_notify.sh` (con `HOME` temporal y el stub de curl en `PATH`):
  - `none` → `FIN: sin-aviso`, sin llamada a curl.
  - `claude-push` → línea `AVISO-CLAUDE: T: M https://x` y `FIN: claude-push`.
  - `ntfy` sin tema → crea `~/.agents-kit/ntfy-topic` con modo 600 y formato `agents-kit-[0-9a-f]{24}`, imprime `tema ntfy nuevo:`, curl recibe `-H Title: T`, `-H Click: https://x`, `-d M` y la URL `https://ntfy.sh/<tema>`; segunda llamada reutiliza el tema sin la línea de tema nuevo.
  - `ntfyTopic: "mi-tema"` en el marcador → URL `.../mi-tema`.
  - `ntfyTopic: "a/b"` → exit 2.
  - `CURL_FAIL=1` → exit 2 y mensaje.
  - Mensaje con salto de línea → llega con espacio.
  - Canal `"sms"` → exit 1. Sin marcador → exit 1 con `kit no activado`.
  - `kit_transport`: `CLAUDE_CODE_REMOTE=true` → `nube`; sin variable → `local`.
  - Plantilla: `jq -r .notify templates/agents-kit.json` es `ntfy`.
- [ ] **Step 2:** `bash tests/test_notify.sh` falla.
- [ ] **Step 3:** implementar.
- [ ] **Step 4:** `bash tests/test_notify.sh` y `tests/run.sh` en verde (ajusta tests existentes que fijen `claude-push` como valor por defecto, si los hay).
- [ ] **Step 5:** commit `feat: avisos por ntfy (kit-notify.sh) y detección de transporte`.

### Task 2: `scripts/kit-changelog.sh validar` y fixtures del formato

**Files:**
- Create: `scripts/kit-changelog.sh`, `tests/fixtures/changelog/{valido-vacio,valido-completo,invalido-tipo,invalido-orden,invalido-enlace,invalido-imagen}.md`, `tests/test_changelog.sh`
- Modify: `scripts/kit-pr.sh` (puerta en `fusionar`), `tests/test_pr.sh`

**Interfaces:**
- Produces: `scripts/kit-changelog.sh validar <root>`: exit 0 `FIN: valido <n> entradas`; exit 1 con una línea por error `CHANGELOG.md:<línea>: <motivo>` en stderr. Sin `CHANGELOG.md`: `FIN: sin-changelog`, exit 0.

Formato (el de `templates/CHANGELOG.md`), ignorando todo lo que esté dentro de `<!-- ... -->`:
- Fechas `## YYYY-MM-DD`, fecha válida, estrictamente descendentes y sin repetir.
- Entrada `### <Tipo>: <título> · [#<N>](<url>)` con tipo en `Nuevo|Mejora|Arreglo|Interno`, título no vacío, `<url>` = `https://github.com/<owner>/<repo>/pull/<N>` con el mismo `<N>`. El final ` · [#N](url)` se busca al final de la línea (el título puede contener `·`).
- Toda entrada va bajo una fecha. Cualquier otra línea `### ` o `## ` fuera de formato es error.
- Imágenes `![...](<ruta>)` relativas: el fichero debe existir desde `<root>`. URLs `http(s)` se aceptan sin comprobar.
- Aviso (no error, stderr `aviso:`) si una imagen local pasa de 500 KB.
- El texto libre de la versión extendida no se valida.

`valido-completo.md`: dos fechas, cuatro entradas (una con `·` en el título, una con imagen `docs/changelog/12-login.png` que el test crea, una sin extendida). Cada `invalido-*.md` tiene un solo error, el que dice su nombre.

Puerta en `kit-pr.sh fusionar`: antes de fusionar, si `<wt>/CHANGELOG.md` existe, ejecutar `kit-changelog.sh validar <wt>`; si sale 1, `fusionar` sale 1 con `CHANGELOG.md mal formado` y los errores.

- [ ] **Step 1: tests** en `tests/test_changelog.sh`: cada fixture con el resultado esperado (exit y línea con el número de línea correcto); la plantilla `templates/CHANGELOG.md` es válida con 0 entradas; repo sin changelog → `sin-changelog`; imagen de 600 KB → aviso y exit 0; sin marcador → exit 1. En `tests/test_pr.sh`: `fusionar` con changelog inválido sale 1 sin llamar a `gh pr merge`.
- [ ] **Step 2:** fallan.
- [ ] **Step 3:** implementar (awk para el recorrido; bash para comprobar imágenes y fechas con `date`, portable macOS/Linux: validar con regex y comparar como texto `YYYY-MM-DD`, y comprobar día/mes con aritmética, sin `date -d`).
- [ ] **Step 4:** `tests/run.sh` en verde.
- [ ] **Step 5:** commit `feat: validar el formato de CHANGELOG.md antes de fusionar`.

### Task 3: resumen en el issue fijado y avisos en el flujo

**Files:**
- Modify: `scripts/kit-changelog.sh` (subcomando `resumen`), `scripts/kit-issue.sh` (avisar en `decision` y `bloquear`), `tests/test_changelog.sh`, `tests/test_issue.sh`, `tests/stubs/flow/gh` (si hace falta para listar el issue fijado)
- Modify: `skills/kit-run/SKILL.md`, `skills/kit-on/SKILL.md`, `tests/test_skills.sh`

**Interfaces:**
- Consumes: `kit-notify.sh` (Task 1), `kit-changelog.sh validar` (Task 2).
- Produces: `scripts/kit-changelog.sh resumen <root> <id> <fichero>`: busca el issue abierto titulado exactamente `📦 Changelog` (`gh issue list --repo <slug> --state open --search "in:title 📦 Changelog"` + filtro exacto con jq); si no existe, exit 2 `no hay issue "📦 Changelog": ejecuta kit-on`. Publica un comentario `<!-- kit-resumen: <id> -->` + el fichero. Idempotente: si ya hay un comentario propio (login de `gh api user`) con ese marcador, no publica otro e imprime su URL. `FIN: <url del comentario>`.

`kit-issue.sh decision|bloquear`: tras el éxito actual, ejecutar `kit-notify.sh <root> "<repo>: necesita decisión" "#<N> <título del issue>" <url del issue>` (o `bloqueado`). Si el aviso sale distinto de 0, `aviso: no se pudo avisar (<motivo>)` en stderr; la salida sigue siendo 0 y `FIN:` sigue siendo la última línea (las líneas del aviso van antes). Si el aviso imprime `AVISO-CLAUDE:`, esa línea se reenvía a stdout antes de `FIN:`.

Skill `kit-run`:
- Quitar la línea "Los avisos fuera de GitHub llegan en la fase 3...".
- Regla nueva: cualquier línea `AVISO-CLAUDE: <texto>` en la salida de un script significa llamar a la herramienta de notificación push de la sesión (en Claude Code, `PushNotification`) con ese texto; si la herramienta no existe, ignorarla.
- Paso 4: tras escribir la entrada, `kit-changelog.sh validar <wt>` en verde. Cambio visual: durante la comprobación e2e del estado final, captura con el navegador automatizado, guárdala en `docs/changelog/<pr>-<nombre>.png` del worktree, comprimida (por debajo de 500 KB) y solo las que aportan; enlázala en la versión extendida. Sin cambio visual, sin capturas.
- Resumen final, antes del texto del chat: si entró algo en `main` o hay issues esperando a Dru, escribir el resumen (PRs fusionadas con su entrada corta del changelog y su URL, issues que esperan a Dru) en un fichero temporal y `kit-changelog.sh resumen <raíz> <id> <fichero>`; después `kit-notify.sh <raíz> "<repo>: kit-run terminado" "<n> fusionadas, <m> esperan" <url del comentario>`. Si no pasó nada, sin resumen ni aviso. Los fallos de ambos se cuentan en el chat sin parar.
- Skill `kit-on`: en el resumen a Dru, si `.notify` es `ntfy`, ejecutar `kit-notify.sh <raíz> "agents-kit" "Avisos activados en <repo>"` y darle el tema (`cat ~/.agents-kit/ntfy-topic` o `ntfyTopic`) con la instrucción: instalar la app ntfy y suscribirse a ese tema.

- [ ] **Step 1: tests.** `test_changelog.sh`: `resumen` publica con marcador y `--repo`; segunda llamada no publica; sin issue fijado → exit 2; ignora un comentario con el marcador de otro autor. `test_issue.sh`: `decision` y `bloquear` llaman al aviso (con `notify: none` en el marcador, la salida contiene `FIN: necesita-decision #N` como última línea; con `ntfy` y `CURL_FAIL=1`, exit 0 y `aviso: no se pudo avisar` en stderr; con `claude-push`, `AVISO-CLAUDE:` antes de `FIN:`). `test_skills.sh`: `kit-run` menciona `kit-changelog.sh validar`, `kit-changelog.sh resumen`, `kit-notify.sh`, `AVISO-CLAUDE` y `docs/changelog/`, y ya no contiene `llegan en la fase 3`; `kit-on` menciona `ntfy`.
- [ ] **Step 2:** fallan.
- [ ] **Step 3:** implementar.
- [ ] **Step 4:** `tests/run.sh` en verde y `claude plugin validate .`.
- [ ] **Step 5:** commit `feat: resumen en el issue de changelog y avisos en el flujo`.

### Task 4: documentación

**Files:**
- Modify: `README.md`, `AGENTS.md`, `rules/core.md` (si la regla del changelog necesita la validación)

- README: sección "Avisos" (canal por defecto ntfy; instalar la app ntfy, suscribirse al tema que da `kit-on` o `cat ~/.agents-kit/ntfy-topic`; el tema es el único secreto, quien lo sepa puede leer los avisos; cambiar con `notify`/`ntfyTopic` en `.agents-kit.json`; `claude-push` solo en Claude Code con Remote Control; `none`), qué avisa (`necesita-decision`, `bloqueado`, fin de `kit-run`) y el resumen en "📦 Changelog". Quitar "changelog y avisos fuera de GitHub" de "Próximas fases".
- AGENTS.md: añadir `kit-changelog.sh`, `kit-notify.sh`, `lib/transport.sh` y `tests/fixtures/` al mapa; nota de que los fixtures del changelog son el contrato del formato para la web.
- [ ] **Step 1:** editar; `tests/run.sh` en verde.
- [ ] **Step 2:** commit `docs: avisos y validación del changelog`.

### Verificación final (controlador)

- E2E real en el sandbox `DruMoDev/agents-kit-sandbox`: `kit-notify.sh` con ntfy real (un aviso de prueba a ntfy.sh), un issue `listo` pequeño hasta `main` con `kit-run` comprobando entrada de changelog validada, comentario de resumen en "📦 Changelog" y aviso final.
