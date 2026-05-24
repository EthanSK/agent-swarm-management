import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDirectory, "..");
const packageJsonPath = path.join(repoRoot, "package.json");
const bumpType = process.argv[2] ?? "minor";

async function main() {
  const raw = await readFile(packageJsonPath, "utf8");
  const packageJson = JSON.parse(raw);
  const currentVersion = String(packageJson.version || "").trim();
  const match = currentVersion.match(/^(\d+)\.(\d+)\.(\d+)$/);

  if (!match) {
    throw new Error(`Current version "${currentVersion}" is not in x.y.0 format.`);
  }

  if (Number(match[3]) !== 0) {
    throw new Error(`Current version "${currentVersion}" has a non-zero patch. This project uses Producer-style x.y display / x.y.0 internal versioning.`);
  }

  let major = Number(match[1]);
  let minor = Number(match[2]);

  if (bumpType === "major") {
    major += 1;
    minor = 0;
  } else {
    minor += 1;
  }

  const nextVersion = `${major}.${minor}.0`;
  const updatedRaw = raw.replace(/"version"\s*:\s*"[^"]*"/, `"version": "${nextVersion}"`);
  await writeFile(packageJsonPath, updatedRaw, "utf8");
  console.log(`[version:bump] ${currentVersion} -> ${nextVersion} (display: ${major}.${minor})`);
}

main().catch((error) => {
  console.error(`[version:bump] ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
});
