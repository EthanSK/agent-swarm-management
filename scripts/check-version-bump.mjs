import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execFile as execFileCallback } from "node:child_process";
import { promisify } from "node:util";

const execFile = promisify(execFileCallback);
const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDirectory, "..");
const SEMVER_PATTERN = /^(\d+)\.(\d+)\.(\d+)$/;
const IGNORE_PREFIXES = [".github/", "docs/"];
const IGNORE_EXACT = new Set(["README.md", "PLAN.md", ".gitignore", "site/version.json", "scripts/check-version-consistency.mjs", "scripts/check-version-bump.mjs", "scripts/sync-version.mjs"]);

function shouldIgnoreFile(filePath) {
  return IGNORE_EXACT.has(filePath) || IGNORE_PREFIXES.some((prefix) => filePath.startsWith(prefix));
}

function parseSemver(version, label) {
  const match = String(version).trim().match(SEMVER_PATTERN);
  if (!match) throw new Error(`${label} "${version}" is not valid x.y.z semver.`);
  return { raw: String(version).trim(), major: Number(match[1]), minor: Number(match[2]), patch: Number(match[3]) };
}

function compareSemverCore(left, right) {
  if (left.major !== right.major) return left.major > right.major ? 1 : -1;
  if (left.minor !== right.minor) return left.minor > right.minor ? 1 : -1;
  if (left.patch !== right.patch) return left.patch > right.patch ? 1 : -1;
  return 0;
}

async function git(args) {
  const { stdout } = await execFile("git", args, { cwd: repoRoot });
  return stdout.trim();
}

async function readPackageVersionFromRef(ref) {
  let raw;
  try {
    raw = await git(["show", `${ref}:package.json`]);
  } catch {
    // First release-system landing: older commits in this repo did not have
    // package.json yet, so there is no meaningful previous app version to
    // compare against. Future commits do have package.json and are enforced.
    return null;
  }
  const parsed = JSON.parse(raw);
  return String(parsed.version || "").trim();
}

async function resolveBaseCommit() {
  const requestedBase = process.env.VERSION_BUMP_BASE?.trim();
  if (requestedBase) return await git(["merge-base", "HEAD", requestedBase]).catch(() => git(["rev-parse", requestedBase]));
  return await git(["rev-parse", "HEAD^"]).catch(() => null);
}

async function main() {
  const baseCommit = await resolveBaseCommit();
  if (!baseCommit) {
    console.log("[version:bump:check] No usable base commit found; skipping bump enforcement.");
    return;
  }

  const changedFiles = (await git(["diff", "--name-only", `${baseCommit}..HEAD`])).split("\n").map((line) => line.trim()).filter(Boolean);
  const releaseRelevantFiles = changedFiles.filter((filePath) => !shouldIgnoreFile(filePath));

  if (releaseRelevantFiles.length === 0) {
    console.log("[version:bump:check] Only non-shipping files changed; version bump not required.");
    return;
  }

  const currentPackageJson = JSON.parse(await readFile(path.join(repoRoot, "package.json"), "utf8"));
  const currentVersion = String(currentPackageJson.version || "").trim();
  const baseVersion = await readPackageVersionFromRef(baseCommit);

  if (!baseVersion) {
    console.log("[version:bump:check] Base commit has no package.json version; treating this as initial release metadata setup.");
    return;
  }

  if (currentVersion === baseVersion) {
    throw new Error(`Release-relevant files changed without a package.json version bump.\n\nChanged files:\n${releaseRelevantFiles.map((f) => `  - ${f}`).join("\n")}\n\nRun: npm run version:bump:patch`);
  }

  const baseSemver = parseSemver(baseVersion, "Base package.json version");
  const currentSemver = parseSemver(currentVersion, "Current package.json version");

  if (compareSemverCore(currentSemver, baseSemver) <= 0) {
    throw new Error(`package.json version must advance above ${baseVersion}; got ${currentVersion}.`);
  }

  if (currentSemver.patch !== 0) {
    throw new Error(`package.json version "${currentSemver.raw}" has a non-zero patch. Use x.y.0 only.`);
  }

  console.log(`[version:bump:check] OK — package.json version increased from ${baseVersion} to ${currentVersion}.`);
}

main().catch((error) => {
  console.error(`[version:bump:check] ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
});
