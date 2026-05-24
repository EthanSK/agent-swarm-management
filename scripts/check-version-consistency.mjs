import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDirectory, "..");

function toDisplayVersion(version) {
  const match = version.match(/^(\d+)\.(\d+)\.0$/);
  return match ? `${match[1]}.${match[2]}` : version;
}

async function readJson(relativePath) {
  return JSON.parse(await readFile(path.join(repoRoot, relativePath), "utf8"));
}

async function main() {
  const packageJson = await readJson("package.json");
  const packageVersion = String(packageJson.version || "").trim();
  const siteVersion = await readJson("site/version.json");
  const infoTemplate = await readFile(path.join(repoRoot, "Resources/Info.plist.template"), "utf8");
  const releaseWorkflow = await readFile(path.join(repoRoot, ".github/workflows/release-desktop.yml"), "utf8");

  if (!/^(\d+)\.(\d+)\.0$/.test(packageVersion)) {
    throw new Error(`package.json version "${packageVersion}" must use Producer-style two-part versioning: x.y.0.`);
  }

  if (siteVersion.version !== packageVersion) {
    throw new Error(`site/version.json (${siteVersion.version}) does not match package.json (${packageVersion}). Run: npm run version:sync`);
  }

  if (siteVersion.displayVersion !== `v${toDisplayVersion(packageVersion)}`) {
    throw new Error(`site/version.json displayVersion must be v${toDisplayVersion(packageVersion)}.`);
  }

  if (siteVersion.source !== "package.json") {
    throw new Error("site/version.json must declare source: package.json.");
  }

  if (!infoTemplate.includes("__APP_VERSION__") || !infoTemplate.includes("__BUILD_NUMBER__")) {
    throw new Error("Info.plist.template must keep __APP_VERSION__ and __BUILD_NUMBER__ placeholders for release builds.");
  }

  if (!infoTemplate.includes("SUFeedURL") || !infoTemplate.includes("SUPublicEDKey")) {
    throw new Error("Info.plist.template must include Sparkle SUFeedURL and SUPublicEDKey.");
  }

  if (!releaseWorkflow.includes("app_version=\"$(node -p \"require(\'./package.json\').version\")\"")) {
    throw new Error("release workflow must derive app_version from package.json.");
  }

  if (/\bnpm\s+version\b/.test(releaseWorkflow)) {
    throw new Error("release workflow must not rewrite package.json version in CI.");
  }

  console.log(`[version:check] OK — unified version source is package.json (${packageVersion}).`);
}

main().catch((error) => {
  console.error(`[version:check] ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
});

