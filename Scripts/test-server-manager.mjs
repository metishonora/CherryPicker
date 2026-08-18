import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const codexHome = process.env.CODEX_HOME || join(homedir(), ".codex");
const managerUrl = pathToFileURL(join(codexHome, "web-server-lifecycle/manager.mjs"));
const { runCli } = await import(managerUrl.href);

await runCli();
