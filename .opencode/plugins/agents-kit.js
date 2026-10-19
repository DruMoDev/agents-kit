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

const contextCache = new Map(); // directory -> context string ('' = inactive)

export const kitContext = (directory) => {
  if (contextCache.has(directory)) return contextCache.get(directory);
  let ctx = '';
  try {
    const out = execFileSync(HOOK, {
      cwd: directory,
      input: JSON.stringify({ cwd: directory }),
      encoding: 'utf8',
      env: { ...process.env, CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT },
    });
    if (out.trim()) ctx = JSON.parse(out).hookSpecificOutput?.additionalContext || '';
  } catch (err) {
    console.error('[agents-kit] session-start failed:', err.message);
  }
  contextCache.set(directory, ctx);
  return ctx;
};

export const AgentsKitPlugin = async ({ directory }) => ({
  config: async (config) => {
    if (Array.isArray(config.skills)) return;
    config.skills = config.skills || {};
    config.skills.paths = config.skills.paths || [];
    const dir = path.join(PLUGIN_ROOT, 'skills');
    if (!config.skills.paths.includes(dir)) config.skills.paths.push(dir);

    // The skills read and run files under the plugin root, outside the project;
    // allow that directory unless the user already set a rule for it.
    config.permission = config.permission || {};
    const ext = config.permission.external_directory;
    if (ext === undefined || (ext && typeof ext === 'object')) {
      config.permission.external_directory = ext || {};
      const pattern = `${PLUGIN_ROOT}/**`;
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
    if (firstUser.parts.some((p) => p.type === 'text' && p.text.includes(MARK))) return;
    firstUser.parts.unshift({ ...firstUser.parts[0], type: 'text', text: ctx });
  },
});

export default { id: 'agents-kit', server: AgentsKitPlugin };
