// Usage: node opencode_harness.mjs <plugin.js> <directory> [config-json]
// Prints JSON: {skills, permission, texts} after config + two transform passes.
const [, , pluginPath, directory] = process.argv;
const { AgentsKitPlugin } = await import(pluginPath);
const hooks = await AgentsKitPlugin({ directory });
const config = JSON.parse(process.argv[4] || '{}');
await hooks.config(config);
const output = { messages: [
  { info: { role: 'assistant' }, parts: [] },
  { info: { role: 'user', sessionID: 's1' }, parts: [{ id: 'p1', type: 'text', text: 'hola' }] },
] };
await hooks['experimental.chat.messages.transform']({}, output);
await hooks['experimental.chat.messages.transform']({}, output);
console.log(JSON.stringify({ skills: config.skills.paths, permission: config.permission, texts: output.messages[1].parts.map((p) => p.text) }));
