import { readFileSync } from "node:fs";
import { resolve } from "node:path";

function readMarketingVersion(): string | undefined {
  try {
    const projectYml = readFileSync(resolve(process.cwd(), "../App/project.yml"), "utf8");
    return projectYml.match(/MARKETING_VERSION:\s*"([^"]+)"/)?.[1];
  } catch {
    return undefined;
  }
}

export const base = import.meta.env.BASE_URL.replace(/\/$/, "");

export const repo = "https://github.com/thomasguillot/audio-extractr";

export const version = readMarketingVersion();
