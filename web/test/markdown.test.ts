import { describe, expect, it } from "vitest";
import { renderMarkdown } from "../src/lib/markdown";

const img = (p: string) => `/img/demo/${p}`;

describe("renderMarkdown", () => {
  it("párrafos, negrita, código y enlaces http(s)", () => {
    const html = renderMarkdown(
      "Hola **mundo** y `a < b`.\nSigue igual.\n\nVer [la guía](https://example.com/a?x=1&y=2).",
      img,
    );
    expect(html).toBe(
      '<p>Hola <strong>mundo</strong> y <code>a &lt; b</code>.\nSigue igual.</p>\n' +
        '<p>Ver <a href="https://example.com/a?x=1&amp;y=2" rel="noopener noreferrer" target="_blank">la guía</a>.</p>',
    );
  });

  it("escapa HTML crudo, incluido <script>", () => {
    const html = renderMarkdown('<script>alert("x")</script> <img src=x onerror=alert(1)>', img);
    expect(html).not.toContain("<script");
    expect(html).not.toContain("<img");
    expect(html).toContain("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;");
  });

  it("no acepta enlaces javascript: ni rompe atributos con comillas", () => {
    const html = renderMarkdown('[x](javascript:alert(1)) [y](https://a.com/"onmouseover="z)', img);
    expect(html).not.toContain('href="javascript');
    expect(html).not.toContain('"onmouseover="');
  });

  it("imágenes relativas pasan por imgUrl; las https van tal cual; otras se quedan en texto", () => {
    const html = renderMarkdown(
      "![Pantalla de acceso](docs/changelog/12-login.png)\n\n![ext](https://example.com/a.png)\n\n![mala](javascript:alert(1))",
      img,
    );
    expect(html).toContain('<img src="/img/demo/docs/changelog/12-login.png" alt="Pantalla de acceso" loading="lazy">');
    expect(html).toContain('<img src="https://example.com/a.png" alt="ext" loading="lazy">');
    expect(html).not.toContain('src="javascript');
  });

  it("bloques de código ``` y ~~~ se escapan y no se interpretan", () => {
    const html = renderMarkdown("Ejemplo:\n\n```bash\n## Paso **1**\n<b>x</b>\n```\n\n~~~\n## 2026-99-99\n~~~", img);
    expect(html).toBe(
      "<p>Ejemplo:</p>\n" +
        '<pre><code class="language-bash">## Paso **1**\n&lt;b&gt;x&lt;/b&gt;</code></pre>\n' +
        "<pre><code>## 2026-99-99</code></pre>",
    );
  });

  it("listas simples con guion", () => {
    expect(renderMarkdown("- uno\n- **dos**", img)).toBe("<ul><li>uno</li><li><strong>dos</strong></li></ul>");
  });

  it("cuerpo vacío da cadena vacía", () => {
    expect(renderMarkdown("", img)).toBe("");
    expect(renderMarkdown("   \n\n", img)).toBe("");
  });

  it("el resultado de imgUrl también se escapa", () => {
    const html = renderMarkdown("![a](docs/changelog/x.png)", () => '"><script>');
    expect(html).not.toContain("<script>");
  });
});
