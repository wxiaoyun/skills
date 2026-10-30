// pi extension for ~/tk, linked into ~/.pi/agent/extensions by tk-setup.sh. Applies guard.sh's rules:
// blocks bash commands that write notes or discard other sessions' edits, and before a run settles
// asks the agent once to save the notes it edited and left unsaved.
import { execFileSync } from "node:child_process";
import { existsSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const home = homedir();
const tk = join(home, "tk");
const guard = [".agents", ".claude"].map((d) => join(home, d, "skills/tribal-knowledge/guard.sh")).find((p) => existsSync(p));

export default function (pi: ExtensionAPI) {
  if (!guard || !existsSync(tk)) return;
  const roots = [tk, realpathSync(tk)];
  const edited = new Set<string>();
  let reminded = false;

  pi.on("input", async () => {
    reminded = false;
  });

  pi.on("tool_call", async (event) => {
    if (event.toolName === "edit" || event.toolName === "write") {
      const p = String(event.input.path ?? "").replace(/^~(?=\/)/, home);
      const root = roots.find((r) => p.startsWith(r + "/"));
      if (root) edited.add(p.slice(root.length + 1));
      return undefined;
    }
    if (event.toolName !== "bash") return undefined;
    try {
      execFileSync("sh", [guard], { input: JSON.stringify({ tool_input: { command: event.input.command } }), stdio: ["pipe", "ignore", "pipe"] });
    } catch (e) {
      const err = e as { status?: number; stderr?: Buffer };
      if (err.status === 2) return { block: true, reason: String(err.stderr ?? "").trim() };
    }
    return undefined;
  });

  pi.on("agent_before_settle", async () => {
    if (reminded || edited.size === 0) return undefined;
    const left = execFileSync("sh", [guard, "dirty", ...edited], { encoding: "utf8" }).trim();
    if (!left) return undefined;
    reminded = true;
    const content = `tk notes you edited are not saved: ${left.split("\n").join(" ")}. Save them with save.sh, or undo your edit if it was a mistake.`;
    return { continue: true, entries: [{ type: "custom_message", customType: "tk-guard", display: false, content }] };
  });
}
