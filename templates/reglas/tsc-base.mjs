// Usage: node tsc-base.mjs generar
//        node tsc-base.mjs comprobar [--cambiados <fichero>...]
// Baseline of tsc errors per file (debt that may only go down). Node >= 20, no dependencies. Run from the repo root.
// Runs `${KIT_TSC:-npx tsc} --noEmit --incremental --pretty false` (KIT_TSC may be a command with arguments, split on
// spaces) and counts errors per file with /^(.+?)\(\d+,\d+\): error TS\d+/, paths relative to the root (cwd).
//   generar:   writes .agents-kit/tsc-base.json ({"<ruta>": <nº de errores>}, keys sorted); FIN: <n> ficheros con deuda.
//   comprobar: exit 1 if a file has more errors than its baseline, a file without baseline has errors, or a file of
//     --cambiados has any error (even if it is in the baseline). Prints every error that counts; FIN: ok otherwise.
//     A global error line (`error TS5083: ...`, no file) always fails. Without tsc-base.json the baseline is empty: no errors allowed.
// Exit: 0 ok, 1 usage or rejected, 2 environment error (tsc does not start, or exits non-zero with no recognizable
// error in its output; generar also exits 2 if tsc gives global errors).
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import path from "node:path";

const BASE = path.join(".agents-kit", "tsc-base.json");
const RE = /^(.+?)\(\d+,\d+\): error TS\d+/;
const RE_GLOBAL = /^error TS\d+:/;

const norm = (p) => {
  let r = path.normalize(p);
  if (path.isAbsolute(p)) {
    // cwd and its realpath can differ (/var vs /private/var on macOS): take the one that contains the path
    const raices = [process.cwd(), realpathSync(process.cwd())];
    const rutas = [p, "/private" + p, p.replace(/^\/private(?=\/)/, "")];
    r = raices.flatMap((x) => rutas.map((y) => path.relative(x, y))).find((x) => !x.startsWith("..")) ?? path.relative(raices[0], p);
  }
  r = r.split(path.sep).join("/");
  return r.replace(/^(\.\/)+/, "");
};

const salir = (code, msg) => {
  if (msg) (code === 0 ? console.log : console.error)(msg);
  process.exit(code);
};

function correrTsc() {
  const partes = (process.env.KIT_TSC || "npx tsc").split(/\s+/).filter(Boolean);
  const r = spawnSync(partes[0], [...partes.slice(1), "--noEmit", "--incremental", "--pretty", "false"], {
    cwd: process.cwd(),
    encoding: "utf8",
    maxBuffer: 1024 * 1024 * 512,
  });
  if (r.error) salir(2, `No se pudo lanzar tsc (${partes.join(" ")}): ${r.error.message}`);
  const lineas = `${r.stdout || ""}\n${r.stderr || ""}`.split(/\r?\n/);
  const errores = [];
  const globales = [];
  for (const linea of lineas) {
    const m = RE.exec(linea);
    if (m) errores.push({ fichero: norm(m[1]), linea });
    else if (RE_GLOBAL.test(linea)) globales.push(linea);
  }
  if (errores.length === 0 && globales.length === 0 && r.status !== 0) {
    salir(2, `tsc terminó con código ${r.status} sin errores reconocibles en su salida:\n${(r.stdout || "") + (r.stderr || "")}`);
  }
  return { errores, globales };
}

const cuentas = (errores) => {
  const c = {};
  for (const e of errores) c[e.fichero] = (c[e.fichero] || 0) + 1;
  return c;
};

const [cmd, ...args] = process.argv.slice(2);

if (cmd === "generar") {
  const { errores, globales } = correrTsc();
  if (globales.length) salir(2, `tsc da errores globales, sin fichero; arréglalos antes de generar la línea base:\n${globales.join("\n")}`);
  const c = cuentas(errores);
  const ordenado = Object.fromEntries(Object.keys(c).sort().map((k) => [k, c[k]]));
  mkdirSync(path.dirname(BASE), { recursive: true });
  writeFileSync(BASE, JSON.stringify(ordenado, null, 2) + "\n");
  salir(0, `FIN: ${Object.keys(ordenado).length} ficheros con deuda`);
} else if (cmd === "comprobar") {
  let cambiados = [];
  if (args.length) {
    if (args[0] !== "--cambiados") salir(1, `Argumento desconocido: ${args[0]}. Uso: comprobar [--cambiados <fichero>...]`);
    cambiados = args.slice(1).map(norm);
  }
  let base = {};
  if (existsSync(BASE)) {
    try {
      base = JSON.parse(readFileSync(BASE, "utf8"));
    } catch (e) {
      salir(2, `${BASE} no es JSON válido: ${e.message}`);
    }
  }
  const { errores, globales } = correrTsc();
  const c = cuentas(errores);
  const malos = new Set();
  const motivo = {};
  for (const [f, n] of Object.entries(c)) {
    const permitido = base[f] ?? 0;
    if (cambiados.includes(f)) {
      malos.add(f);
      motivo[f] = `fichero cambiado con ${n} errores de tipos (debe quedar sin ninguno)`;
    } else if (n > permitido) {
      malos.add(f);
      motivo[f] = permitido === 0 && !(f in base)
        ? `fichero sin línea base con ${n} errores de tipos`
        : `${n} errores de tipos, la línea base permite ${permitido}`;
    }
  }
  if (globales.length) console.error(`Errores globales de tsc (sin fichero, nunca permitidos):\n${globales.join("\n")}`);
  if (malos.size || globales.length) {
    for (const f of [...malos].sort()) {
      console.error(`${f}: ${motivo[f]}`);
      for (const e of errores) if (e.fichero === f) console.error(`  ${e.linea}`);
    }
    process.exit(1);
  }
  salir(0, "FIN: ok");
} else {
  salir(1, "Uso: node tsc-base.mjs generar | comprobar [--cambiados <fichero>...]");
}
