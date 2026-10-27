// agents-kit plugin for OpenCode, V1 (`opencode` 1.x, `server`) and V2 (2.x, `setup`).
// Registers the plugin skills and, only in repos with .agents-kit.json, injects
// the same context as hooks/session-start (V1: first user message; V2: system).

import { execFileSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const PLUGIN_ROOT = path.resolve(path.dirname(fs.realpathSync(fileURLToPath(import.meta.url))), '../..');
const HOOK = path.join(PLUGIN_ROOT, 'hooks', 'session-start');
const MARK = 'agents-kit está activo';
// What the kit skills read or run outside the project. Never hooks/ or .opencode/.
const ALLOWED_DIRS = ['scripts', 'skills', 'rules', 'templates'];
// Outside the project the kit also works in the repo's issue worktrees and in its temp dir (bodies, rounds, waits).
const KIT_HOME = path.join(process.env.HOME || '', '.agents-kit');
// The worktrees dir is named after the main clone, also when OpenCode starts inside an issue worktree.
const mainRoot = (root) => {
  try {
    const common = execFileSync('git', ['-C', root, 'rev-parse', '--path-format=absolute', '--git-common-dir'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    return path.basename(common) === '.git' ? path.dirname(common) : root;
  } catch {
    return root;
  }
};
const workDirs = (root) => [
  path.join(process.env.KIT_WORKTREES || path.join(KIT_HOME, 'worktrees'), path.basename(mainRoot(root))),
  process.env.KIT_TMP || path.join(KIT_HOME, 'tmp'),
];

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
    const root = gitRoot(directory);
    const marker = markerOf(root);
    if (!marker || !fs.existsSync(marker)) return;
    config.permission = config.permission || {};
    const ext = config.permission.external_directory;
    if (ext !== undefined && (!ext || typeof ext !== 'object')) return;
    config.permission.external_directory = ext || {};
    const dirs = [...ALLOWED_DIRS.map((d) => path.join(PLUGIN_ROOT, d)), ...workDirs(root)];
    for (const d of dirs) {
      const pattern = `${d}/**`;
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

// V2 (`opencode` 2.x): same behavior through setup(ctx). V2 allows external
// directories by default, so an `ask` there is always the user's rule: no permission hook.
const frontmatter = (text) => {
  const m = text.match(/^---\n([\s\S]*?)\n---\n?/);
  const field = (k) => (m && (m[1].match(new RegExp(`^${k}:\\s*(.*)$`, 'm')) || [])[1]) || '';
  return { name: field('name'), description: field('description'), body: m ? text.slice(m[0].length) : text };
};
const kitSkills = () => {
  const dir = path.join(PLUGIN_ROOT, 'skills');
  return fs.readdirSync(dir).filter((id) => fs.existsSync(path.join(dir, id, 'SKILL.md'))).map((id) => {
    const file = path.join(dir, id, 'SKILL.md');
    const fm = frontmatter(fs.readFileSync(file, 'utf8'));
    return { id, name: fm.name || id, description: fm.description, path: file, content: fm.body };
  });
};

const setup = async (ctx) => {
  const directory = ctx.location.directory;
  const skills = kitSkills();
  await ctx.skill.transform((editor) => {
    for (const s of skills) if (!editor.get(s.id)) editor.add(s);
  });

  // System parts are rebuilt for every model call and never persisted: no guard needed.
  await ctx.session.hook('context', (event) => {
    const ctxText = kitContext(directory);
    if (ctxText) event.system.push({ type: 'text', text: ctxText });
  });
};

export default { id: 'agents-kit', setup, server: AgentsKitPlugin };
