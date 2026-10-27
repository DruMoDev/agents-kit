// Usage: node opencode_v2_harness.mjs <plugin.js> <directory>
// Loads the default export as OpenCode 2.x does (setup(ctx)) with a fake context.
// Prints JSON {exports, hooks, skills, system, systemAgain}: the default export's keys, the hooks it registered,
// the skills the skill transform added (id, path, description, content start) on top of a user skill "kit-on"
// and the system parts of two context calls.
const [, , pluginPath, directory] = process.argv;
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
};
await plugin.setup(ctx);
const system = async () => {
  const event = { sessionID: 's1', system: [{ type: 'text', text: 'base' }], messages: [], tools: {}, options: {} };
  await hooks['session.context'](event);
  return event.system.map((p) => p.text);
};
console.log(JSON.stringify({
  exports: Object.keys(plugin).sort(),
  hooks: Object.keys(hooks).sort(),
  skills: skills.map((s) => ({ id: s.id, path: s.path, description: s.description || '', start: s.content.slice(0, 40) })),
  system: await system(),
  systemAgain: await system(),
}));
