// Usage: node opencode_harness.mjs <plugin.js> <directory> [config-json] [marker-to-create]
// Prints JSON {skills, permission, texts, textsAfter}: config + two transform
// passes; with a marker path, creates it and runs one more pass on fresh
// messages in the same process (textsAfter).
const [, , pluginPath, directory, configJson, marker] = process.argv;
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
if (marker) {
  fs.writeFileSync(marker, '{}');
  result.textsAfter = await texts(messages());
}
console.log(JSON.stringify(result));
