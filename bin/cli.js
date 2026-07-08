#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import readlineBase from 'node:readline';
import readlinePromises from 'node:readline/promises';
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

init    installs docs/agent rules, AGENTS.md and the CLAUDE.md shim (idempotent),
        then lets you pick recommended skills/MCPs (checkboxes) and installs them
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

async function ask(question) {
  const rl = readlinePromises.createInterface({ input: process.stdin, output: process.stdout });
  const answer = await rl.question(question);
  rl.close();
  return answer.trim();
}

async function promptFramework() {
  const names = Object.keys(FRAMEWORKS);
  names.forEach((n, i) => console.log(`  ${i + 1}. ${n}`));
  const answer = await ask(`Framework [1-${names.length}]: `);
  const pick = names[Number(answer) - 1];
  if (!pick) die('Invalid choice.');
  return pick;
}

// Interactive checkbox list. Arrows move, space toggles, "a" toggles all, enter confirms, q/esc skips.
function multiSelect(title, items) {
  return new Promise((resolve) => {
    const checked = items.map((it) => it.preselected !== false);
    let cursor = 0;
    const draw = (redraw) => {
      if (redraw) process.stdout.write(`\x1b[${items.length + 1}A`);
      process.stdout.write(`\x1b[2K${title}\n`);
      items.forEach((it, i) => {
        const ptr = i === cursor ? '\x1b[36m>\x1b[0m' : ' ';
        process.stdout.write(`\x1b[2K ${ptr} [${checked[i] ? 'x' : ' '}] ${it.label}\n`);
      });
    };
    readlineBase.emitKeypressEvents(process.stdin);
    process.stdin.setRawMode(true);
    process.stdin.resume();
    draw(false);
    const finish = (result) => {
      process.stdin.setRawMode(false);
      process.stdin.pause();
      process.stdin.off('keypress', onKey);
      resolve(result);
    };
    const onKey = (str, key = {}) => {
      if (key.ctrl && key.name === 'c') {
        process.stdin.setRawMode(false);
        process.exit(130);
      } else if (key.name === 'up') cursor = (cursor - 1 + items.length) % items.length;
      else if (key.name === 'down') cursor = (cursor + 1) % items.length;
      else if (key.name === 'space' || str === ' ') checked[cursor] = !checked[cursor];
      else if (str === 'a') checked.fill(!checked.every(Boolean));
      else if (key.name === 'return' || key.name === 'enter') return finish(items.filter((_, i) => checked[i]));
      else if (key.name === 'escape' || str === 'q') return finish([]);
      draw(true);
    };
    process.stdin.on('keypress', onKey);
  });
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

function printCommands(fw) {
  if (fw.skills.length) {
    console.log('\nRecommended skills (one command each - pick what this project needs):');
    for (const s of fw.skills) console.log(`  npx skills add ${s.source} --skill ${s.name}   # ${s.why}`);
  }
  if (fw.mcps.length) {
    console.log('\nRecommended MCP servers (each configures Claude Code + opencode, project scope):');
    for (const m of fw.mcps) console.log(`  npx github:DruMoDev/agents-kit mcp ${m.name}   # ${m.why}`);
  }
}

function printNotes(fw, rec) {
  console.log('\nNotes:');
  for (const n of [...(fw.notes ?? []), ...rec.global.notes]) console.log(`  - ${n}`);
}

async function offerExtras(framework) {
  const rec = readJson(path.join(KIT_ROOT, 'recommendations.json'), { frameworks: {}, global: { notes: [] } });
  const fw = { skills: [], mcps: [], notes: [], ...(rec.frameworks[framework] ?? {}) };
  if (!fw.skills.length && !fw.mcps.length) {
    printNotes(fw, rec);
    return;
  }
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    printCommands(fw);
    printNotes(fw, rec);
    return;
  }
  const items = [
    ...fw.skills.map((s) => ({ ...s, kind: 'skill', label: `skill  ${s.name.padEnd(34)} ${s.why}` })),
    ...fw.mcps.map((m) => ({ ...m, kind: 'mcp', label: `mcp    ${m.name.padEnd(34)} ${m.why}` })),
  ];
  console.log('');
  const chosen = await multiSelect(
    'Select extras to install now (arrows move, space toggles, "a" all, enter confirms, q skips):',
    items,
  );
  for (const it of chosen.filter((i) => i.kind === 'skill')) {
    console.log(`\n> npx skills add ${it.source} --skill ${it.name} -y`);
    const r = spawnSync('npx', ['skills', 'add', it.source, '--skill', it.name, '-y'], { stdio: 'inherit' });
    if (r.status !== 0) console.log(`  install failed - run it manually later`);
  }
  const mcpNames = chosen.filter((i) => i.kind === 'mcp').map((i) => i.name);
  if (mcpNames.length) {
    let projectRef = null;
    if (mcpNames.includes('supabase')) projectRef = (await ask('\nSupabase project ref (empty to skip the param): ')) || null;
    console.log('');
    mcp({ names: mcpNames, projectRef });
  }
  printNotes(fw, rec);
}

async function init(args) {
  const framework = args.framework ?? (await promptFramework());
  console.log(`Installing agent rules (framework: ${framework})`);
  for (const [dest, src] of kitFiles(framework)) report(installFile(src, dest, args.force), dest);
  report(ensureAgentsMd(framework), 'AGENTS.md');
  report(ensureClaudeMd(), 'CLAUDE.md');
  await offerExtras(framework);
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

const args = parseArgs(process.argv.slice(2));
if (args.cmd === 'init') await init(args);
else if (args.cmd === 'update') update(args);
else if (args.cmd === 'mcp') mcp(args);
else {
  console.log(HELP);
  if (args.cmd && args.cmd !== 'help') process.exit(1);
}
