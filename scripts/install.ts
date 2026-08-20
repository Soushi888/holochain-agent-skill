#!/usr/bin/env node
/**
 * install.ts - installs the skills in this package into whichever agent
 * harnesses are present on the machine.
 *
 * Built to `bin/install.mjs` with `bun build --target=node`, so the source
 * stays TypeScript while the published binary runs under plain node with zero
 * runtime dependencies. Both entry points resolve the payload the same way:
 * `<package root>/skills`, one level up from the directory holding this file.
 *
 * The primary caller is an agent, not a person. An agent handed the repository
 * URL runs this non-interactively, so a blocking prompt is a hang, not a
 * question. Every code path below either has a TTY and may ask, or has no TTY
 * and must decide by itself and say what it decided.
 */

import { existsSync, mkdirSync, readdirSync, readFileSync, lstatSync, rmSync, cpSync, symlinkSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createInterface } from "node:readline";

/**
 * Where each harness looks for skills.
 *
 * Every path carries the source it was read from. This table is the one place
 * in the package where being wrong is silent: an install into a directory
 * nothing scans looks exactly like a successful install. Nothing goes in here
 * from recall.
 */
type Target = {
  id: string;
  label: string;
  /** Path relative to the project root. */
  project: string;
  /** Path relative to $HOME, or null when the harness has no global scope. */
  global: string | null;
  /**
   * Project-scope presence markers, for a harness whose skills path sits under
   * a directory too generic to mean anything on its own. Any one of them
   * existing counts as detection. Omitted wherever the harness's own
   * dot-directory is the signal.
   */
  projectMarkers?: string[];
  /** Where this path was verified. */
  source: string;
};

const TARGETS: Target[] = [
  {
    id: "claude",
    label: "Claude Code",
    project: ".claude/skills",
    global: ".claude/skills",
    source: "docs.github.com and opencode.ai both name .claude/skills as a path they also scan",
  },
  {
    id: "agents",
    label: "Agent Skills (tool-agnostic)",
    project: ".agents/skills",
    global: ".agents/skills",
    source: "opencode.ai/docs/skills, geminicli.com/docs/cli/skills, docs.github.com all list .agents/skills",
  },
  {
    id: "opencode",
    label: "opencode",
    project: ".opencode/skills",
    global: ".config/opencode/skills",
    source: "opencode.ai/docs/skills",
  },
  {
    id: "copilot",
    label: "GitHub Copilot",
    project: ".github/skills",
    global: ".copilot/skills",
    // `.github/` alone is not a Copilot signal: almost every repository on
    // GitHub has one for workflows or issue templates, and deriving the marker
    // from the skills path installed this skill into `.github/skills/` in all of
    // them. Measured in this very repository, which has no `.claude/`: the
    // installer reported "Detected GitHub Copilot" and would have written there.
    projectMarkers: [
      ".github/skills",
      ".github/copilot-instructions.md",
      ".github/instructions",
      ".github/prompts",
    ],
    source: "docs.github.com/en/copilot/concepts/agents/about-agent-skills",
  },
  {
    id: "gemini",
    label: "Gemini CLI",
    project: ".gemini/skills",
    global: ".gemini/skills",
    source: "geminicli.com/docs/cli/skills",
  },
  {
    id: "cursor",
    label: "Cursor",
    project: ".cursor/skills",
    global: ".cursor/skills",
    source: "cursor.com/docs/skills, which also names .agents/skills and reads .claude/skills for compatibility",
  },
];

/**
 * Fallback when nothing is detected. `.claude/skills` and `.agents/skills` are
 * the two paths the widest set of harnesses scan, so installing to both is the
 * highest-coverage guess available when the machine gives no signal.
 */
const FALLBACK_IDS = ["claude", "agents"];

type Options = {
  targets: string[];
  skills: string[];
  global: boolean;
  yes: boolean;
  link: boolean;
  dryRun: boolean;
};

function packageRoot(): string {
  return resolve(dirname(fileURLToPath(import.meta.url)), "..");
}

function skillsRoot(): string {
  return join(packageRoot(), "skills");
}

/** Every directory under skills/ that actually holds a SKILL.md. */
function availableSkills(): string[] {
  const root = skillsRoot();
  if (!existsSync(root)) return [];
  return readdirSync(root, { withFileTypes: true })
    .filter((e) => e.isDirectory() && existsSync(join(root, e.name, "SKILL.md")))
    .map((e) => e.name)
    .sort();
}

function skillDescription(name: string): string {
  const file = join(skillsRoot(), name, "SKILL.md");
  try {
    const text = readFileSync(file, "utf8");
    const match = text.match(/^description:\s*>?-?\s*\n?((?:\s+.*\n|.*\n)*?)^[a-z_-]+:/mi);
    const raw = match ? match[1] : "";
    const flat = raw.replace(/\s+/g, " ").trim();
    return flat.length > 100 ? `${flat.slice(0, 97)}...` : flat;
  } catch {
    return "";
  }
}

/**
 * A harness counts as present when its marker directory exists: `.claude/`
 * for `.claude/skills`, `.config/opencode/` for `.config/opencode/skills`.
 * The skills directory itself usually does not exist yet, which is exactly the
 * case an installer is for, so testing for it would detect nothing.
 */
function markerDir(relativeSkillsPath: string): string {
  const parts = relativeSkillsPath.split("/");
  return parts.slice(0, -1).join("/");
}

function detect(opts: Options): Target[] {
  const base = opts.global ? homedir() : process.cwd();
  return TARGETS.filter((t) => {
    const rel = opts.global ? t.global : t.project;
    if (!rel) return false;
    const markers = !opts.global && t.projectMarkers ? t.projectMarkers : [markerDir(rel)];
    return markers.some((m) => existsSync(join(base, m)));
  });
}

function destinationFor(target: Target, opts: Options): string | null {
  const rel = opts.global ? target.global : target.project;
  if (!rel) return null;
  return join(opts.global ? homedir() : process.cwd(), rel);
}

function ask(question: string): Promise<string> {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((res) => rl.question(question, (answer) => { rl.close(); res(answer); }));
}

async function chooseTargets(detected: Target[], opts: Options): Promise<Target[]> {
  if (opts.targets.length > 0) {
    const chosen = opts.targets.map((id) => {
      const t = TARGETS.find((x) => x.id === id);
      if (!t) {
        console.error(`error: unknown target '${id}'. Known targets: ${TARGETS.map((x) => x.id).join(", ")}`);
        process.exit(2);
      }
      if (opts.global && !t.global) {
        console.error(`error: target '${id}' has no global scope`);
        process.exit(2);
      }
      return t;
    });
    return chosen;
  }

  if (detected.length === 0) {
    const fallback = TARGETS.filter((t) => FALLBACK_IDS.includes(t.id));
    console.log("No agent harness detected. Installing to the two most widely scanned paths:");
    for (const t of fallback) console.log(`  ${destinationFor(t, opts)}`);
    return fallback;
  }

  if (detected.length === 1) {
    console.log(`Detected ${detected[0].label}.`);
    return detected;
  }

  // More than one, and nobody told us which. Only ask when there is a human.
  if (opts.yes || !process.stdin.isTTY) {
    console.log(`Detected ${detected.length} harnesses, installing to all of them:`);
    for (const t of detected) console.log(`  ${t.label.padEnd(28)} ${destinationFor(t, opts)}`);
    return detected;
  }

  console.log("Detected more than one agent harness:\n");
  detected.forEach((t, i) => {
    console.log(`  ${i + 1}) ${t.label.padEnd(28)} ${destinationFor(t, opts)}`);
  });
  console.log("");
  const answer = (await ask("Install to which? (numbers separated by commas, or Enter for all) ")).trim();
  if (answer === "") return detected;

  const picked = answer
    .split(",")
    .map((s) => Number.parseInt(s.trim(), 10))
    .filter((n) => Number.isInteger(n) && n >= 1 && n <= detected.length)
    .map((n) => detected[n - 1]);

  if (picked.length === 0) {
    console.error("error: nothing selected");
    process.exit(2);
  }
  return [...new Set(picked)];
}

function installOne(skill: string, dest: string, opts: Options): void {
  const src = join(skillsRoot(), skill);
  const target = join(dest, skill);

  if (opts.dryRun) {
    console.log(`  would ${opts.link ? "link" : "copy"} ${src} -> ${target}`);
    return;
  }

  mkdirSync(dest, { recursive: true });

  // lstat, not existsSync: a broken symlink from an earlier --link install is
  // invisible to existsSync and would make the write below fail with EEXIST.
  let replaced = false;
  try {
    lstatSync(target);
    replaced = true;
  } catch {
    // nothing there, which is the normal first install
  }
  if (replaced) {
    // Say so in the output. Prompting is not an option here (the primary caller
    // is an agent with no TTY, and a prompt is a hang), but silently deleting a
    // directory someone may have hand-edited is worse than a noisy line.
    rmSync(target, { recursive: true, force: true });
  }

  if (opts.link) {
    symlinkSync(src, target, "dir");
  } else {
    cpSync(src, target, {
      recursive: true,
      // Build output and dependency trees are not skill content. They are
      // absent from the published tarball but present in a git checkout, and
      // `--link` aside, a repo-local install would otherwise copy a Rust
      // target/ directory into the consumer's project.
      filter: (source) => {
        const base = source.split("/").pop() ?? "";
        return base !== "target" && base !== "node_modules" && base !== ".DS_Store";
      },
    });
  }

  const verb = opts.link ? "linked" : "installed";
  console.log(`  ${replaced ? `replaced (existing contents deleted), ${verb}` : verb} ${skill} -> ${target}`);
}

function usage(): void {
  console.log(`holochain-agent-skills installer

Usage:
  holochain-skills install [skill...] [options]
  holochain-skills list
  holochain-skills help

Installs the Holochain agent skill into whichever agent harnesses are present.
With no [skill...] argument, every skill in the package is installed.

Options:
  -t, --target <id>   Install to a specific harness (repeatable, or comma-separated).
                      Known: ${TARGETS.map((t) => t.id).join(", ")}
  -g, --global        Install to the home-directory scope instead of the project.
  -y, --yes           Never prompt. Install to every detected harness.
      --link          Symlink instead of copying, so a git pull updates the install.
      --dry-run       Print what would happen and change nothing.
  -h, --help          This text.

Detection looks for each harness's marker directory (.claude, .opencode,
.github, ...) in the project root, or in $HOME with --global. When exactly one
is found it is used. When several are found and the terminal is interactive you
are asked; otherwise all of them are installed. When none is found the skill
goes to .claude/skills and .agents/skills.

Without a TTY this command never prompts, so it is safe to run from an agent
or from CI.`);
}

function parseArgs(argv: string[]): { command: string; opts: Options } {
  const opts: Options = { targets: [], skills: [], global: false, yes: false, link: false, dryRun: false };
  let command = "install";
  let seenCommand = false;

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "-t":
      case "--target":
        opts.targets.push(...(argv[++i] ?? "").split(",").map((s) => s.trim()).filter(Boolean));
        break;
      case "-g":
      case "--global":
        opts.global = true;
        break;
      case "-y":
      case "--yes":
        opts.yes = true;
        break;
      case "--link":
        opts.link = true;
        break;
      case "--dry-run":
        opts.dryRun = true;
        break;
      case "-h":
      case "--help":
        command = "help";
        seenCommand = true;
        break;
      default:
        if (arg.startsWith("-")) {
          console.error(`error: unknown option '${arg}'`);
          process.exit(2);
        }
        if (!seenCommand && ["install", "list", "help"].includes(arg)) {
          command = arg;
          seenCommand = true;
        } else {
          opts.skills.push(arg);
        }
    }
  }

  return { command, opts };
}

async function main(): Promise<void> {
  const { command, opts } = parseArgs(process.argv.slice(2));

  if (command === "help") {
    usage();
    return;
  }

  const skills = availableSkills();
  if (skills.length === 0) {
    console.error(`error: no skills found under ${skillsRoot()}`);
    process.exit(2);
  }

  if (command === "list") {
    console.log("Skills in this package:\n");
    for (const s of skills) console.log(`  ${s.padEnd(16)} ${skillDescription(s)}`);
    console.log("\nHarness paths:\n");
    for (const t of TARGETS) {
      console.log(`  ${t.id.padEnd(10)} ${t.label.padEnd(28)} ${t.project}${t.global ? `  (global: ~/${t.global})` : ""}`);
    }
    return;
  }

  const wanted = opts.skills.length > 0 ? opts.skills : skills;
  for (const s of wanted) {
    if (!skills.includes(s)) {
      console.error(`error: no skill named '${s}'. Available: ${skills.join(", ")}`);
      process.exit(2);
    }
  }

  const detected = detect(opts);
  const chosen = await chooseTargets(detected, opts);

  for (const target of chosen) {
    const dest = destinationFor(target, opts);
    if (!dest) continue;
    console.log(`\n${target.label}  (${dest})`);
    for (const skill of wanted) installOne(skill, dest, opts);
  }

  if (!opts.dryRun) {
    console.log(`\nDone. Restart your agent so it picks the skill up, then ask it anything about Holochain.`);
  }
}

main().catch((err) => {
  console.error(`error: ${err instanceof Error ? err.message : String(err)}`);
  process.exit(1);
});
