import { test } from "@playwright/test";

// Capturas para revisar el diseño a mano: SHOTS=<directorio> npx playwright test shots
// (sin SHOTS no hace nada). Se hacen con el estado recién borrado: todo sin ver.
const dir = process.env.SHOTS;

test.skip(!dir, "solo con SHOTS=<directorio>");

for (const scheme of ["light", "dark"] as const) {
  for (const width of [360, 1280]) {
    test(`capturas ${scheme} ${width}`, async ({ page }) => {
      await page.emulateMedia({ colorScheme: scheme, reducedMotion: "reduce" });
      await page.setViewportSize({ width, height: width < 600 ? 780 : 900 });
      await page.goto("/");
      await page.screenshot({ path: `${dir}/home-${width}-${scheme}.png`, fullPage: true });
      await page.goto("/app/recetario");
      // abrir sin marcar visto: el estado se mantiene igual para la siguiente captura
      await page.route("**/api/seen", (r) => r.fulfill({ status: 500 }));
      await page.evaluate(() => {
        document.querySelector<HTMLDetailsElement>('details.entry[data-pr="14"]')!.open = true;
      });
      await page.waitForFunction(() => {
        const img = document.querySelector<HTMLImageElement>('details.entry[data-pr="14"] img');
        return !img || (img.complete && img.naturalWidth > 0);
      });
      // el guardado falla (500) y la marca "Sin ver" vuelve; luego se borra el aviso
      await page.waitForFunction(() => document.querySelector("[data-status]")?.textContent);
      await page.evaluate(() => document.querySelector<HTMLElement>("[data-status]")!.replaceChildren());
      await page.screenshot({ path: `${dir}/app-${width}-${scheme}.png`, fullPage: true });
    });
  }
}
