import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { parseChangelog, type Day } from "../src/lib/changelog";

const dir = fileURLToPath(new URL("../../tests/fixtures/changelog/", import.meta.url));
const fixture = (name: string) => readFileSync(dir + name, "utf8");
const entries = (days: Day[]) => days.flatMap((d) => d.entries);

describe("parseChangelog contra los fixtures compartidos", () => {
  it("cubre todos los fixtures del contrato", () => {
    const names = readdirSync(dir).filter((f) => f.endsWith(".md")).sort();
    expect(names).toEqual([
      "invalido-comentario.md",
      "invalido-enlace.md",
      "invalido-imagen.md",
      "invalido-orden.md",
      "invalido-tipo.md",
      "valido-codigo.md",
      "valido-completo.md",
      "valido-vacio.md",
    ]);
    for (const n of names) expect(() => parseChangelog(fixture(n))).not.toThrow();
  });

  it("valido-completo: 4 entradas en 2 fechas, con el separador final y el cuerpo", () => {
    const days = parseChangelog(fixture("valido-completo.md"));
    expect(days.map((d) => d.date)).toEqual(["2026-10-18", "2024-02-29"]);
    const all = entries(days);
    expect(all).toHaveLength(4);
    expect(all.map((e) => [e.type, e.title, e.pr])).toEqual([
      ["Nuevo", "Login con Google", 12],
      ["Mejora", "Ajustes: más rápidos · y claros", 11],
      ["Arreglo", "Fecha inexistente en 2026", 9],
      ["Interno", "Limpieza 🧹", 8],
    ]);
    const [login, ajustes, , limpieza] = all;
    expect(login.url).toBe("https://github.com/dru/demo/pull/12");
    expect(login.date).toBe("2026-10-18");
    expect(login.body).toBe(
      "Ahora puedes entrar con tu cuenta de Google en un clic.\n\n![Pantalla de acceso](docs/changelog/12-login.png)",
    );
    expect(ajustes.body).toBe("");
    expect(limpieza.date).toBe("2024-02-29");
    expect(limpieza.body).toBe("Texto libre con ### y ## en medio de una frase.");
  });

  it("valido-codigo: los bloques de código no crean fechas ni entradas y quedan en el cuerpo", () => {
    const days = parseChangelog(fixture("valido-codigo.md"));
    expect(days.map((d) => d.date)).toEqual(["2026-10-18"]);
    const all = entries(days);
    expect(all).toHaveLength(1);
    expect(all[0].title).toBe("Ejemplos en la ayuda");
    expect(all[0].body).toContain("```bash\n## Paso 1\n### hola\n");
    expect(all[0].body).toContain("<!-- dentro de código no abre comentario\n```");
    expect(all[0].body.endsWith("~~~\n## 2026-99-99\n~~~")).toBe(true);
  });

  it("valido-vacio: ninguna entrada", () => {
    expect(parseChangelog(fixture("valido-vacio.md"))).toEqual([]);
  });

  it("invalido-tipo: descarta la entrada de tipo desconocido", () => {
    expect(entries(parseChangelog(fixture("invalido-tipo.md")))).toEqual([]);
  });

  it("invalido-enlace: descarta la entrada cuyo número no coincide con el enlace", () => {
    expect(entries(parseChangelog(fixture("invalido-enlace.md")))).toEqual([]);
  });

  it("invalido-imagen: la entrada es válida para el parser (la imagen la resuelve el servidor)", () => {
    const all = entries(parseChangelog(fixture("invalido-imagen.md")));
    expect(all).toHaveLength(1);
    expect(all[0].body).toBe("![Falta](docs/changelog/no-existe.png)");
  });

  it("invalido-orden: conserva ambas entradas y ordena las fechas de más reciente a más antigua", () => {
    const days = parseChangelog(fixture("invalido-orden.md"));
    expect(days.map((d) => d.date)).toEqual(["2026-10-18", "2026-10-01"]);
    expect(entries(days).map((e) => e.pr)).toEqual([2, 1]);
  });

  it("invalido-comentario: un <!-- sin cerrar oculta el resto, como en el validador", () => {
    const all = entries(parseChangelog(fixture("invalido-comentario.md")));
    expect(all.map((e) => e.pr)).toEqual([1]);
    expect(all[0].body).toBe("Usa `");
  });
});

describe("parseChangelog en casos sueltos", () => {
  it("texto vacío o sin changelog: sin fechas", () => {
    expect(parseChangelog("")).toEqual([]);
  });

  it("CRLF, espacios finales, fechas inexistentes, mal formadas y entradas fuera de fecha", () => {
    const text = [
      "# Changelog",
      "### Nuevo: Huérfana · [#1](https://github.com/o/r/pull/1)",
      "## 2026-02-30",
      "### Nuevo: Bajo fecha imposible · [#2](https://github.com/o/r/pull/2)",
      "## ayer",
      "### Nuevo: Bajo fecha rara · [#3](https://github.com/o/r/pull/3)",
      "## 2026-10-18   ",
      "### Arreglo: Buena · [#4](https://github.com/o/r/pull/4)   ",
      "### Arreglo:  · [#5](https://github.com/o/r/pull/5)",
      "### Arreglo: Sin enlace",
      "### Arreglo: Enlace raro · [#6](https://example.com/o/r/pull/6)",
      "Cuerpo   ",
      "",
    ].join("\r\n");
    const days = parseChangelog(text);
    expect(days).toEqual([
      {
        date: "2026-10-18",
        entries: [
          {
            type: "Arreglo",
            title: "Buena",
            pr: 4,
            url: "https://github.com/o/r/pull/4",
            date: "2026-10-18",
            body: "",
          },
        ],
      },
    ]);
  });

  it("une fechas repetidas en un solo día y comentarios en línea no cuentan", () => {
    const text = [
      "## 2026-10-18",
      "### Nuevo: A · [#1](https://github.com/o/r/pull/1)",
      "Hola <!-- oculto --> mundo",
      "<!-- ### Nuevo: Oculta · [#9](https://github.com/o/r/pull/9) -->",
      "## 2026-10-18",
      "### Mejora: B · [#2](https://github.com/o/r/pull/2)",
    ].join("\n");
    const days = parseChangelog(text);
    expect(days).toHaveLength(1);
    expect(days[0].entries.map((e) => e.pr)).toEqual([1, 2]);
    expect(days[0].entries[0].body).toBe("Hola  mundo");
  });
});
