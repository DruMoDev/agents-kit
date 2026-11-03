// agents-kit plugin for OpenCode, V1 (`opencode` 1.x, `server`) and V2 (2.x, `setup`).
// Registers the plugin skills and, only in repos with .agents-kit.json, injects
// the same context as hooks/session-start (V1: first user message; V2: system)
// and runs hooks/pre-edit and hooks/post-edit around the edit tools, and hooks/pre-bash before the bash tool
// (editHook). The hooks find the repo of each
// edited file themselves and stay inert outside repos with .agents-kit.json; if a hook cannot run (it fails to start,
// dies or passes its time limit), the edit goes through, as in Claude Code.

import { execFile, execFileSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const PLUGIN_ROOT = path.resolve(path.dirname(fs.realpathSync(fileURLToPath(import.meta.url))), '../..');
const HOOK = path.join(PLUGIN_ROOT, 'hooks', 'session-start');
const PRE_EDIT = path.join(PLUGIN_ROOT, 'hooks', 'pre-edit');
const POST_EDIT = path.join(PLUGIN_ROOT, 'hooks', 'post-edit');
const PRE_BASH = path.join(PLUGIN_ROOT, 'hooks', 'pre-bash');
// What hooks/pre-bash looks for, checked first so a plain command spawns nothing.
const SKIP_HOOKS = /no-verify|HUSKY|LEFTHOOK|SKIP|hooksPath/;
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

// Rule hooks (hooks/pre-edit, hooks/post-edit, hooks/pre-bash), fed with the same JSON as Claude Code (Codex's for the
// patch tool). V1 tools take filePath, V2 tools path; the patch tool (V1 `patch`/`apply_patch`, V2 `patch`) takes
// patchText; bash takes command.
const hookInput = (directory, sessionID, tool, args) => {
  const a = args && typeof args === 'object' ? args : {};
  const file = a.filePath ?? a.path;
  let name = '';
  let input;
  if (tool === 'patch' || tool === 'apply_patch') {
    name = 'apply_patch';
    input = { command: a.patchText ?? a.patch ?? a.input };
  } else if (tool === 'write') {
    name = 'Write';
    input = { file_path: file, content: a.content };
  } else if (tool === 'edit') {
    name = 'Edit';
    input = { file_path: file, old_string: a.oldString, new_string: a.newString, replace_all: a.replaceAll === true };
  } else if (tool === 'multiedit') {
    name = 'MultiEdit';
    const edits = (Array.isArray(a.edits) ? a.edits : []).map((e) => ({
      old_string: e?.oldString, new_string: e?.newString, replace_all: e?.replaceAll === true }));
    input = { file_path: file, edits };
  } else if (tool === 'bash') {
    name = 'Bash';
    input = { command: a.command };
  } else return null;
  return { session_id: sessionID || '', cwd: directory, tool_name: name, tool_input: input };
};

// Time limit of a hook run: pre-edit 15 s; post-edit KIT_LINT_TIMEOUT (10 s) per file of the edit plus 15 s.
const hookTimeout = (hook, input) => {
  if (hook !== POST_EDIT) return 15000;
  const per = Number(process.env.KIT_LINT_TIMEOUT) > 0 ? Number(process.env.KIT_LINT_TIMEOUT) : 10;
  const files = input.tool_name === 'apply_patch'
    ? (String(input.tool_input.command || '').match(/^\s*\*\*\* (Add|Update) File:/gm) || []).length : 1;
  return (per * Math.max(1, files) + 15) * 1000;
};

// editHook <hook> <directory> <sessionID> <tool> <args>: resolves to '' when the hook lets it pass (exit 0, an inert
// repo or a hook that could not run) and to its stderr when it blocks (exit 2). For the bash tool, PRE_EDIT means
// hooks/pre-bash (only when the command has something it looks for) and POST_EDIT runs nothing.
export const editHook = (hook, directory, sessionID, tool, args) => new Promise((resolve) => {
  const input = hookInput(directory, sessionID, tool, args);
  if (!input) return resolve('');
  if (input.tool_name === 'Bash') {
    if (hook !== PRE_EDIT || !SKIP_HOOKS.test(String(input.tool_input.command ?? ''))) return resolve('');
    hook = PRE_BASH;
  }
  let child;
  try {
    child = execFile(hook, [], {
      cwd: directory, encoding: 'utf8', timeout: hookTimeout(hook, input), maxBuffer: 4 * 1024 * 1024,
      env: { ...process.env, CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT },
    }, (err, _stdout, stderr) => {
      if (!err) return resolve('');
      if (err.code === 2) return resolve(String(stderr || '').trim() || 'agents-kit: el hook de reglas bloquea la edición');
      console.error(`[agents-kit] ${path.basename(hook)} no se pudo ejecutar: ${err.message}`);
      resolve('');
    });
  } catch (err) {
    console.error(`[agents-kit] ${path.basename(hook)} no se pudo ejecutar: ${err.message}`);
    return resolve('');
  }
  child.stdin.on('error', () => {});
  child.stdin.end(JSON.stringify(input));
});

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

  // Throwing here blocks the tool; the message reaches the model.
  'tool.execute.before': async (input, output) => {
    const msg = await editHook(PRE_EDIT, directory, input.sessionID, input.tool, output.args);
    if (msg) throw new Error(msg);
  },
  'tool.execute.after': async (input, output) => {
    const msg = await editHook(POST_EDIT, directory, input.sessionID, input.tool, input.args);
    if (msg) output.output = `${output.output ?? ''}\n\n${msg}`;
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

  // System parts are rebuilt for every model call and never persisted: no guard needed. Registered before the rule
  // hooks so a failure there cannot leave the session without the rules.
  await ctx.session.hook('context', (event) => {
    const ctxText = kitContext(directory);
    if (ctxText) event.system.push({ type: 'text', text: ctxText });
  });

  // Same rule hooks as V1: throwing in execute.before blocks the tool (the SDK turns it into the tool's error); after a
  // completed edit, the lint failure is added to the result the model reads.
  try {
    await ctx.tool.hook('execute.before', async (event) => {
      const msg = await editHook(PRE_EDIT, directory, event.sessionID, event.tool, event.input);
      if (msg) throw new Error(msg);
    });
  } catch (err) {
    console.error(`[agents-kit] no se pudo registrar tool.execute.before: ${err.message}`);
  }
  try {
    await ctx.tool.hook('execute.after', async (event) => {
      if (event.status !== 'completed' || !event.result) return;
      const msg = await editHook(POST_EDIT, directory, event.sessionID, event.tool, event.input);
      if (!msg) return;
      const r = event.result;
      if (Array.isArray(r.content)) r.content.push({ type: 'text', text: msg });
      else if (typeof r.content === 'string') r.content = `${r.content}\n\n${msg}`;
      else r.content = [{ type: 'text', text: msg }];
    });
  } catch (err) {
    console.error(`[agents-kit] no se pudo registrar tool.execute.after: ${err.message}`);
  }
};

export default { id: 'agents-kit', setup, server: AgentsKitPlugin };
