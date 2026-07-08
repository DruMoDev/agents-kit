# Testing reference

Read this before writing tests.

## What to test

- Pyramid: many unit tests (fast, isolated), some integration tests (mocked externals), few E2E on critical flows only.
- New functionality: happy path + error path minimum.
- Test shipped behavior. Never write placeholder tests, or brittle tests asserting exact internal constants, provider/model defaults, copy text, or internal wiring — they break on refactor without catching bugs.
- A test that cannot fail when the logic breaks is worse than no test.

## E2E gotchas (Playwright)

- Empty-state: tests that require pre-existing data call `test.skip()` when the data is absent — never fail on empty databases.
- Query by role with the full label: `getByRole('option', { name: '0% (Exento)' })` — substring names collide ("0%" also matches "10%").
- Implicit ARIA roles don't match CSS selectors: use `getByRole('heading')`, not `locator('[role="heading"]')`.
- After `fill()` on a controlled input, `await expect(button).toBeEnabled()` before clicking — the framework must commit state first.
- When the same text appears in several regions, scope the locator (e.g. `page.locator('tfoot').getByText(...)`).
- Responsive layouts hide elements per viewport: set an explicit viewport before asserting on tables/columns.
