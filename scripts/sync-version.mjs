import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDirectory, "..");
const packageJsonPath = path.join(repoRoot, "package.json");
const versionJsonPath = path.join(repoRoot, "site", "version.json");

function toDisplayVersion(version) {
  const match = version.match(/^(\d+)\.(\d+)\.0$/);
  return match ? `${match[1]}.${match[2]}` : version;
}

async function main() {
  const packageJson = JSON.parse(await readFile(packageJsonPath, "utf8"));
  const version = String(packageJson.version || "").trim();

  if (!/^(\d+)\.(\d+)\.(\d+)$/.test(version)) {
    throw new Error(`package.json version "${version}" is not x.y.z semver.`);
  }

  const payload = {
    version,
    displayVersion: `v${toDisplayVersion(version)}`,
    source: "package.json"
  };

  await writeFile(versionJsonPath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
  console.log(`[version:sync] site/version.json <- ${version}`);
}

main().catch((error) => {
  console.error(`[version:sync] ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
});

