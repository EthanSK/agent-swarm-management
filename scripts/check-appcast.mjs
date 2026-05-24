import { readFileSync } from "node:fs";
import { argv, exit, env } from "node:process";

const inputPath = argv[2];
if (!inputPath) {
  console.error("Usage: check-appcast.mjs <path-to-appcast.xml>");
  exit(2);
}

let xml;
try {
  xml = readFileSync(inputPath, "utf8");
} catch (error) {
  console.error(`[appcast-check] failed to read ${inputPath}: ${error.message}`);
  exit(1);
}

const problems = [];
const expectedVersion = env.EXPECTED_VERSION;

if (!xml.includes("<rss") || !xml.includes("<channel>")) problems.push("missing rss/channel wrapper");
if (!xml.includes("sparkle:edSignature")) problems.push("missing Sparkle EdDSA signature");
if (!xml.includes("Agent-Swarm-Management-") || !xml.includes("-mac-universal.zip")) problems.push("missing mac universal zip enclosure");
if (expectedVersion && !xml.includes(`sparkle:shortVersionString="${expectedVersion}"`) && !xml.includes(`<sparkle:shortVersionString>${expectedVersion}</sparkle:shortVersionString>`)) {
  problems.push(`expected version ${expectedVersion} not found in appcast`);
}

if (problems.length > 0) {
  console.error(`[appcast-check] ${inputPath} FAILED:`);
  for (const problem of problems) console.error(`  - ${problem}`);
  exit(1);
}

console.log(`[appcast-check] ${inputPath} OK`);

