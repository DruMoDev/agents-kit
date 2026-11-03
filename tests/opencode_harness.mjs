// Usage: node opencode_harness.mjs <plugin.js> <directory> [config-json] [marker-to-create] [tool-events-json]
// Prints JSON {skills, permission, texts, textsAfter, tools}: config + two transform
// passes; with a marker path, creates it and runs one more pass on fresh
// messages in the same process (textsAfter). For each {tool, args} of tool-events-json, tools gets {before, output}:
// the error thrown by tool.execute.before (or null) and the output after tool.execute.after (it started as "hecho").
const [, , pluginPath, directory, configJson, marker, toolEvents] = process.argv;
const { AgentsKitPlugin } = await import(pluginPath);
const fs = await import('fs');
const hooks = await AgentsKitPlugin({ directory });
const config = JSON.parse(configJson || '{}');
await hooks.config(config);
const messages = () => ({ messages: [
  { info: { role: 'assistant' }, parts: [] },
  { info: { role: 'user', sessionID: 's1' }, parts: [{ id: 'p1', sessionID: 's1', messageID: 'm1', type: 'text', text: 'hola' }] },
] });
const texts = async (output) => {
  await hooks['experimental.chat.messages.transform']({}, output);
  await hooks['experimental.chat.messages.transform']({}, output);
  return output.messages[1].parts.map((p) => p.text);
};
const result = { skills: config.skills.paths, permission: config.permission, texts: await texts(messages()) };
if (marker && marker !== '-') {
  fs.writeFileSync(marker, '{}');
  result.textsAfter = await texts(messages());
}
result.tools = [];
for (const { tool, args } of JSON.parse(toolEvents || '[]')) {
  let before = null;
  try { await hooks['tool.execute.before']({ tool, sessionID: 's1', callID: 'c1' }, { args }); } catch (err) { before = err.message; }
  const output = { title: '', output: 'hecho', metadata: {} };
  await hooks['tool.execute.after']({ tool, sessionID: 's1', callID: 'c1', args }, output);
  result.tools.push({ before, output: output.output });
}
console.log(JSON.stringify(result));
