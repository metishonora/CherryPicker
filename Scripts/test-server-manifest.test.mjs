import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const manifest = JSON.parse(await readFile(
  new URL("../.codex/web-server.json", import.meta.url),
  "utf8",
));

test("CherryPicker manifest derives the prototype port from the issue", () => {
  assert.equal(manifest.port.issueBase + 4, 11004);
  assert.equal(manifest.port.fallbackBase, 12000);
});

test("CherryPicker manifest exposes only its static prototype profile", () => {
  const matchingProfile = (server) => manifest.profiles.find(
    ({ namePattern }) => new RegExp(namePattern).test(server),
  );
  const profile = matchingProfile("prototype");

  assert.deepEqual(profile.command, [
    "python3",
    "-m",
    "http.server",
    "{port}",
    "--bind",
    "{host}",
    "--directory",
    "Prototypes/Issue{issue}",
  ]);
  assert.equal(profile.healthPath, "/");
  assert.equal(matchingProfile("dev"), undefined);
});
