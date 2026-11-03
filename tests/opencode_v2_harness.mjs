// Usage: node opencode_v2_harness.mjs <plugin.js> <directory> [tool-events-json]
// Loads the default export as OpenCode 2.x does (setup(ctx)) with a fake context.
// Prints JSON {exports, hooks, skills, system, systemAgain, tools}: the default export's keys, the hooks it registered,
// the skills the skill transform added (id, path, description, content start) on top of a user skill "kit-on",
// the system parts of two context calls and, for each {tool, input} of tool-events-json, {before, content}: the
// error thrown by tool.execute.before (or null) and the result content after tool.execute.after (a completed call
// whose content was [{type: "text", text: "hecho"}]).
const [, , pluginPath, directory, toolEvents] = process.argv;
const plugin = (await import(pluginPath)).default;
const hooks = {};
const skills = [{ id: 'kit-on', name: 'mía', path: '/user/kit-on/SKILL.md', content: 'del usuario' }];
const editor = {
  list: () => skills,
  get: (id) => skills.find((s) => s.id === id),
  add: (s) => skills.push(s),
  update: () => {},
  remove: () => {},
};
const ctx = {
  location: { directory, project: { id: 'p' } },
  skill: { transform: async (cb) => { cb(editor); return { dispose: async () => {} }; } },
  permission: { hook: async (name, cb) => { hooks[`permission.${name}`] = cb; } },
  session: { hook: async (name, cb) => { hooks[`session.${name}`] = cb; } },
  // HARNESS_TOOL_HOOK_FALLA=1: registering a tool hook throws (an OpenCode without it, or a broken one).
  tool: { hook: async (name, cb) => {
    if (process.env.HARNESS_TOOL_HOOK_FALLA) throw new Error('sin tool.hook');
    hooks[`tool.${name}`] = cb;
  } },
};
await plugin.setup(ctx);
const system = async () => {
  const event = { sessionID: 's1', system: [{ type: 'text', text: 'base' }], messages: [], tools: {}, options: {} };
  await hooks['session.context'](event);
  return event.system.map((p) => p.text);
};
const tools = [];
for (const { tool, input } of (hooks['tool.execute.before'] ? JSON.parse(toolEvents || '[]') : [])) {
  const base = { tool, sessionID: 's1', agent: 'build', messageID: 'm1', id: 'c1', input };
  let before = null;
  try { await hooks['tool.execute.before']({ ...base }); } catch (err) { before = err.message; }
  const after = { ...base, status: 'completed', result: { content: [{ type: 'text', text: 'hecho' }] } };
  await hooks['tool.execute.after'](after);
  tools.push({ before, content: after.result.content.map((p) => p.text) });
}
console.log(JSON.stringify({
  exports: Object.keys(plugin).sort(),
  hooks: Object.keys(hooks).sort(),
  skills: skills.map((s) => ({ id: s.id, path: s.path, description: s.description || '', start: s.content.slice(0, 40) })),
  system: await system(),
  systemAgain: await system(),
  tools,
}));
