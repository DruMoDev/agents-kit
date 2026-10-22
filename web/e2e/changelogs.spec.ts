import { expect, test, type Page } from "@playwright/test";

// Los tests comparten el KV (se borra al arrancar el servidor) y van en orden:
// cada uno parte del estado que deja el anterior.
test.describe.configure({ mode: "serial" });

const card = (page: Page, name: string) => page.locator(`[data-repo="${name}"]`);

async function noHorizontalScroll(page: Page) {
  const { scroll, client } = await page.evaluate(() => ({
    scroll: document.documentElement.scrollWidth,
    client: document.documentElement.clientWidth,
  }));
  const wide = await page.evaluate(() =>
    [...document.querySelectorAll("body *")]
      .filter((e) => e.getBoundingClientRect().right > document.documentElement.clientWidth + 1)
      .map((e) => `${e.tagName}.${e.className}`),
  );
  expect(scroll, `desbordan: ${wide.join(", ")}`).toBeLessThanOrEqual(client);
}

test("inicio: una tarjeta por app con su contador, ordenadas por novedades", async ({ page }) => {
  await page.goto("/");
  await expect(page).toHaveTitle(/Changelogs/);
  const names = await page.locator("[data-repo]").evaluateAll((els) => els.map((e) => e.getAttribute("data-repo")));
  expect(names).toEqual(["recetario", "gastos-casa", "notas-rapidas"]);

  await expect(card(page, "recetario")).toHaveAttribute("data-unseen", "5");
  await expect(card(page, "recetario")).toContainText("5 sin ver");
  await expect(card(page, "recetario")).toContainText("20 oct 2026");
  await expect(card(page, "gastos-casa")).toContainText("1 sin ver");
  await expect(card(page, "notas-rapidas")).toHaveAttribute("data-unseen", "0");
  await expect(card(page, "notas-rapidas")).toContainText("Sin cambios");
  await expect(page.getByRole("heading", { level: 1 })).toContainText("6");
});

test("filtro por tipo", async ({ page }) => {
  await page.goto("/");
  await card(page, "recetario").getByRole("link").click();
  await expect(page).toHaveURL(/\/app\/recetario$/);
  await expect(page.locator("details.entry")).toHaveCount(5);

  const filter = page.getByRole("navigation", { name: "Filtrar por tipo" });
  await filter.getByRole("link", { name: /Arreglo/ }).click();
  await expect(page).toHaveURL(/tipo=Arreglo/);
  await expect(page.locator("details.entry")).toHaveCount(1);
  await expect(page.locator("details.entry")).toContainText("Las fotos ya no salen giradas");
  await expect(filter.getByRole("link", { name: /Arreglo/ })).toHaveAttribute("aria-current", "page");

  await filter.getByRole("link", { name: /Todos/ }).click();
  await expect(page.locator("details.entry")).toHaveCount(5);
});

test("abrir un cambio muestra la extendida, lo marca visto y baja el contador", async ({ page }) => {
  await page.goto("/app/recetario");
  const entry = page.locator('details.entry[data-pr="11"]');
  await expect(entry).toHaveAttribute("data-unseen", "true");
  await expect(entry.getByText("Sin ver")).toBeVisible();
  await expect(entry.getByText("tortilla")).toBeHidden();

  const saved = page.waitForResponse((r) => r.url().endsWith("/api/seen") && r.status() === 204);
  await entry.locator("summary").click();
  await saved;
  await expect(entry.getByText("tortilla")).toBeVisible();
  await expect(entry).not.toHaveAttribute("data-unseen", "true");
  await expect(page.locator("[data-unseen-total]")).toHaveText("4");

  // la extendida con captura: la imagen pasa por /img y carga
  const login = page.locator('details.entry[data-pr="14"]');
  await login.locator("summary").press("Enter");
  const img = login.locator("img");
  await expect(img).toHaveAttribute("src", "/img/recetario/docs/changelog/14-login.png");
  await expect.poll(() => img.evaluate((el: HTMLImageElement) => el.complete && el.naturalWidth)).toBeGreaterThan(0);

  await page.getByRole("link", { name: "Todas las apps" }).click();
  await expect(card(page, "recetario")).toHaveAttribute("data-unseen", "3");
  await expect(card(page, "recetario")).toContainText("3 sin ver");
});

test("marcar todo como visto deja el contador a 0", async ({ page }) => {
  await page.goto("/app/recetario");
  const saved = page.waitForResponse((r) => r.url().endsWith("/api/seen") && r.status() === 204);
  await page.getByRole("button", { name: "Marcar todo como visto" }).click();
  await saved;
  await expect(page.locator('details.entry[data-unseen="true"]')).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Marcar todo como visto" })).toBeHidden();

  await page.goto("/");
  await expect(card(page, "recetario")).toHaveAttribute("data-unseen", "0");
  await expect(card(page, "recetario")).toContainText("Al día");
  // ya no va primera: gastos-casa tiene novedades
  const names = await page.locator("[data-repo]").evaluateAll((els) => els.map((e) => e.getAttribute("data-repo")));
  expect(names).toEqual(["gastos-casa", "recetario", "notas-rapidas"]);
  // el estado sobrevive a recargar
  await page.reload();
  await expect(card(page, "recetario")).toHaveAttribute("data-unseen", "0");
});

test("360 px: sin scroll horizontal en inicio y en una app", async ({ page }) => {
  await page.setViewportSize({ width: 360, height: 780 });
  await page.goto("/");
  await noHorizontalScroll(page);
  await page.goto("/app/recetario");
  await page.locator('details.entry[data-pr="14"] summary').click();
  await page.locator('details.entry[data-pr="7"] summary').click();
  await noHorizontalScroll(page);
});

test("app sin changelog y app inexistente", async ({ page }) => {
  await page.goto("/app/notas-rapidas");
  await expect(page.getByText("Todavía no hay cambios")).toBeVisible();
  const res = await page.goto("/app/no-existe");
  expect(res?.status()).toBe(404);
  await expect(page.getByRole("heading", { level: 1 })).toContainText("No existe");
});

test("API e imágenes: validación", async ({ request }) => {
  expect((await request.post("/api/seen", { data: { repo: "no-existe", prs: [1] } })).status()).toBe(404);
  expect((await request.post("/api/seen", { data: { repo: "recetario", prs: "1" } })).status()).toBe(400);
  expect((await request.get("/api/seen")).status()).toBe(405);

  const ok = await request.get("/img/recetario/docs/changelog/14-login.png");
  expect(ok.status()).toBe(200);
  expect(ok.headers()["content-type"]).toBe("image/png");
  expect((await request.get("/img/recetario/docs/otra/14-login.png")).status()).toBe(404);
  expect((await request.get("/img/no-existe/docs/changelog/14-login.png")).status()).toBe(404);
  expect((await request.get("/img/recetario/docs/changelog/%2e%2e/x.png")).status()).toBe(404);
});

test("las páginas no se guardan en caché del navegador", async ({ request }) => {
  const res = await request.get("/");
  expect(res.headers()["cache-control"]).toContain("no-store");
});
