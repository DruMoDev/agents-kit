// agents-kit plugin for OpenCode (V1, `opencode` 1.x).
// Registers the plugin skills and, only in repos with .agents-kit.json, injects
// the same context as hooks/session-start into the first user message.

import { execFileSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const PLUGIN_ROOT = path.resolve(path.dirname(fs.realpathSync(fileURLToPath(import.meta.url))), '../..');
const HOOK = path.join(PLUGIN_ROOT, 'hooks', 'session-start');
const MARK = 'agents-kit está activo';
// What the kit skills read or run outside the project. Never hooks/ or .opencode/.
const ALLOWED_DIRS = ['scripts', 'skills', 'rules', 'templates'];

const gitRoot = (directory) => {
  try {
    return execFileSync('git', ['-C', directory, 'rev-parse', '--show-toplevel'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return '';
  }
};

const markerOf = (root) => (root ? path.join(root, '.agents-kit.json') : '');

// The marker is checked on every call (kit-on/kit-off change it mid-process);
// the hook only runs when it exists, and its output is reused while the marker
// file stays the same.
const cache = { key: '', ctx: '' };
let warned = false;

export const kitContext = (directory) => {
  const marker = markerOf(gitRoot(directory));
  if (!marker || !fs.existsSync(marker)) return '';
  const key = `${marker}:${fs.statSync(marker).mtimeMs}`;
  if (cache.key === key) return cache.ctx;
  let ctx = '';
  try {
    const out = execFileSync(HOOK, {
      cwd: directory,
      input: JSON.stringify({ cwd: directory }),
      encoding: 'utf8',
      timeout: 5000,
      env: { ...process.env, CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT },
    });
    if (out.trim()) ctx = JSON.parse(out).hookSpecificOutput?.additionalContext || '';
  } catch (err) {
    ctx = '';
    if (!warned) console.error(`[agents-kit] no se pudieron cargar las reglas: ${err.message}`);
    warned = true;
    return '';
  }
  if (!ctx) {
    if (!warned) console.error('[agents-kit] el repo tiene .agents-kit.json pero el hook no devolvió reglas (¿falta jq?)');
    warned = true;
    return '';
  }
  cache.key = key;
  cache.ctx = ctx;
  return ctx;
};

export const AgentsKitPlugin = async ({ directory }) => ({
  config: async (config) => {
    if (Array.isArray(config.skills)) return;
    config.skills = config.skills || {};
    config.skills.paths = config.skills.paths || [];
    const dir = path.join(PLUGIN_ROOT, 'skills');
    if (!config.skills.paths.includes(dir)) config.skills.paths.push(dir);

    // Only in activated repos: let the skills read and run plugin files without
    // asking, unless the user already set a rule. Elsewhere OpenCode asks.
    const marker = markerOf(gitRoot(directory));
    if (!marker || !fs.existsSync(marker)) return;
    config.permission = config.permission || {};
    const ext = config.permission.external_directory;
    if (ext !== undefined && (!ext || typeof ext !== 'object')) return;
    config.permission.external_directory = ext || {};
    for (const d of ALLOWED_DIRS) {
      const pattern = `${path.join(PLUGIN_ROOT, d)}/**`;
      if (!(pattern in config.permission.external_directory)) config.permission.external_directory[pattern] = 'allow';
    }
  },

  // Fires on every agent step with messages reloaded from the DB, so the guard
  // keeps the injection to one copy.
  'experimental.chat.messages.transform': async (_input, output) => {
    const ctx = kitContext(directory);
    if (!ctx) return;
    const firstUser = output.messages.find((m) => m.info.role === 'user');
    if (!firstUser || !firstUser.parts.length) return;
    if (firstUser.parts.some((p) => p.synthetic && p.type === 'text' && p.text.includes(MARK))) return;
    const { id, sessionID, messageID } = firstUser.parts[0];
    firstUser.parts.unshift({ id, sessionID, messageID, type: 'text', text: ctx, synthetic: true });
  },
});

export default { id: 'agents-kit', server: AgentsKitPlugin };
