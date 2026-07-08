#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline/promises';
import { fileURLToPath } from 'node:url';

const KIT_ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const TPL = (...p) => path.join(KIT_ROOT, 'templates', ...p);
const AGENT_DIR = path.join('docs', 'agent');
const HEADER_MARK = '@docs/agent/base.md';
const FRAMEWORKS = {
  next: 'nextjs.md',
  astro: 'astro.md',
  react: 'react.md',
  'node-backend': 'node-backend.md',
  python: 'python.md',
  generic: null,
};

// One definition per MCP server; rendered into .mcp.json (Claude/Cursor) and opencode.json
const MCP_CATALOG = {
  'next-devtools': { command: ['npx', '-y', 'next-devtools-mcp@latest'] },
  'astro-docs': { url: 'https://mcp.docs.astro.build/mcp' },
  supabase: { url: 'https://mcp.supabase.com/mcp' },
  playwright: { command: ['npx', '-y', '@playwright/mcp@latest'] },
};

const HELP = `agents-kit - install a reusable agent instruction set

Usage:
  npx github:DruMoDev/agents-kit init [--framework <fw>] [--force]
  npx github:DruMoDev/agents-kit update [--framework <fw>]
  npx github:DruMoDev/agents-kit mcp <name...> [--project-ref <ref>]

Frameworks: ${Object.keys(FRAMEWORKS).join(', ')}
MCP servers: ${Object.keys(MCP_CATALOG).join(', ')}

init    installs docs/agent rules, AGENTS.md and the CLAUDE.md shim (idempotent)
update  rewrites kit-owned files under docs/agent/ with the latest templates
mcp     configures MCP servers for Claude Code (.mcp.json) AND opencode (opencode.json), project scope
--force re-copies kit-owned files during init even if locally modified
`;

function die(msg) {
  console.error(msg);
  process.exit(1);
}

function parseArgs(argv) {
  const args = { cmd: argv[0], framework: null, force: false, names: [], projectRef: null };
  for (let i = 1; i < argv.length; i++) {
    if (argv[i] === '--framework' || argv[i] === '-f') args.framework = argv[++i];
    else if (argv[i] === '--force') args.force = true;
    else if (argv[i] === '--project-ref') args.projectRef = argv[++i];
    else if (!argv[i].startsWith('-')) args.names.push(argv[i]);
    else die(`Unknown argument: ${argv[i]}\n\n${HELP}`);
  }
  if (args.framework && !(args.framework in FRAMEWORKS)) {
    die(`Unknown framework "${args.framework}". Options: ${Object.keys(FRAMEWORKS).join(', ')}`);
  }
  return args;
}

async function promptFramework() {
  const names = Object.keys(FRAMEWORKS);
  names.forEach((n, i) => console.log(`  ${i + 1}. ${n}`));
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const answer = await rl.question(`Framework [1-${names.length}]: `);
  rl.close();
  const pick = names[Number(answer) - 1];
  if (!pick) die('Invalid choice.');
  return pick;
}

// Kit-owned files for a framework: [destPath, templatePath][]
function kitFiles(framework) {
  const files = [
    ['base.md', TPL('base.md')],
    ['testing.md', TPL('docs', 'testing.md')],
    ['docs-discipline.md', TPL('docs', 'docs-discipline.md')],
  ];
  const fw = FRAMEWORKS[framework];
  if (fw) files.push([fw, TPL('frameworks', fw)]);
  return files.map(([name, src]) => [path.join(AGENT_DIR, name), src]);
}

function installFile(src, dest, force) {
  const content = fs.readFileSync(src, 'utf8');
  if (!fs.existsSync(dest)) {
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, content);
    return 'created';
  }
  if (fs.readFileSync(dest, 'utf8') === content) return 'unchanged';
  if (!force) return 'skipped';
  fs.writeFileSync(dest, content);
  return 'updated';
}

function agentsHeader(framework) {
  const fw = FRAMEWORKS[framework];
  const importLine = fw ? `@docs/agent/${fw}\n` : '';
  return fs.readFileSync(TPL('AGENTS.header.md'), 'utf8').replace('{{FRAMEWORK_IMPORT}}\n', importLine);
}

function ensureAgentsMd(framework) {
  if (!fs.existsSync('AGENTS.md')) {
    fs.writeFileSync('AGENTS.md', agentsHeader(framework));
    return 'created';
  }
  const current = fs.readFileSync('AGENTS.md', 'utf8');
  if (current.includes(HEADER_MARK)) return 'unchanged';
  const header = agentsHeader(framework).split('## Project')[0].trimEnd() + '\n\n';
  fs.writeFileSync('AGENTS.md', header + current);
  return 'updated';
}

function ensureClaudeMd() {
  if (!fs.existsSync('CLAUDE.md')) {
    fs.writeFileSync('CLAUDE.md', '@AGENTS.md\n');
    return 'created';
  }
  const current = fs.readFileSync('CLAUDE.md', 'utf8');
  if (current.split('\n').some((l) => l.trim() === '@AGENTS.md')) return 'unchanged';
  fs.writeFileSync('CLAUDE.md', '@AGENTS.md\n\n' + current);
  return 'updated';
}

function report(status, file) {
  console.log(`  ${status.padEnd(9)} ${file}`);
}

function printNextSteps(framework) {
  const rec = JSON.parse(fs.readFileSync(path.join(KIT_ROOT, 'recommendations.json'), 'utf8'));
  const fw = rec.frameworks[framework] ?? { skills: [], mcps: [], notes: [] };
  if (fw.skills.length) {
    console.log('\nRecommended skills for this framework (run them yourself):');
    for (const c of fw.skills) console.log(`  ${c}`);
  }
  if (fw.mcps.length) {
    console.log('\nRecommended MCP servers (one command configures Claude Code + opencode, project scope):');
    for (const c of fw.mcps) console.log(`  ${c}`);
  }
  console.log('\nNotes:');
  for (const n of [...fw.notes, ...rec.global.notes]) console.log(`  - ${n}`);
}

async function init(args) {
  const framework = args.framework ?? (await promptFramework());
  console.log(`Installing agent rules (framework: ${framework})`);
  for (const [dest, src] of kitFiles(framework)) report(installFile(src, dest, args.force), dest);
  report(ensureAgentsMd(framework), 'AGENTS.md');
  report(ensureClaudeMd(), 'CLAUDE.md');
  printNextSteps(framework);
}

function detectFramework() {
  for (const [name, file] of Object.entries(FRAMEWORKS)) {
    if (file && fs.existsSync(path.join(AGENT_DIR, file))) return name;
  }
  return 'generic';
}

function update(args) {
  const framework = args.framework ?? detectFramework();
  console.log(`Framework: ${framework}`);
  for (const [dest, src] of kitFiles(framework)) report(installFile(src, dest, true), dest);
  report(ensureAgentsMd(framework), 'AGENTS.md');
  report(ensureClaudeMd(), 'CLAUDE.md');
}

function readJson(file, fallback) {
  return fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : fallback;
}

function writeJson(file, data) {
  fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
}

function mcpEntries(name, projectRef) {
  const def = MCP_CATALOG[name];
  const url = def.url && projectRef ? `${def.url}?project_ref=${projectRef}` : def.url;
  return {
    claude: def.url ? { type: 'http', url } : { command: def.command[0], args: def.command.slice(1) },
    opencode: def.url ? { type: 'remote', url } : { type: 'local', command: def.command, enabled: true },
  };
}

function mcp(args) {
  if (!args.names.length) die(`Usage: mcp <name...> [--project-ref <ref>]\nAvailable: ${Object.keys(MCP_CATALOG).join(', ')}`);
  const claudeCfg = readJson('.mcp.json', {});
  claudeCfg.mcpServers ??= {};
  const openCfg = readJson('opencode.json', { $schema: 'https://opencode.ai/config.json' });
  openCfg.mcp ??= {};
  for (const name of args.names) {
    if (!(name in MCP_CATALOG)) die(`Unknown MCP "${name}". Available: ${Object.keys(MCP_CATALOG).join(', ')}`);
    const entries = mcpEntries(name, args.projectRef);
    claudeCfg.mcpServers[name] = entries.claude;
    openCfg.mcp[name] = entries.opencode;
    report('configured', `${name} -> .mcp.json + opencode.json`);
  }
  writeJson('.mcp.json', claudeCfg);
  writeJson('opencode.json', openCfg);
}

const args = parseArgs(process.argv.slice(2));
if (args.cmd === 'init') await init(args);
else if (args.cmd === 'update') update(args);
else if (args.cmd === 'mcp') mcp(args);
else {
  console.log(HELP);
  if (args.cmd && args.cmd !== 'help') process.exit(1);
}
