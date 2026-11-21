import { userInfo } from "node:os";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { ACCESS, PREFIX, SERVER, TOOLS, TOOL_EXPOSURE, URL, parseCommand, terminalText } from "./catalog.ts";
import { HomeAssistantClient } from "./client.ts";
import { formatPrompt, formatSnapshot, formatTool, prepareDisplay } from "./results.ts";
import { openViewer } from "./viewer.ts";
import { APPROVAL_MINUTES, ApprovalQueue, parseApproval } from "./approval.ts";

export const TRANSCRIPT_ENTRY = "inventory-ha-approval";
const KEYCHAIN_SERVICE = "HA-TOKEN";
const ADMIN_TOOLS = new Set(["config__reload_config_entry", "homeassistant__call_action"]);

type Connection = { client: HomeAssistantClient; token: string };

async function readToken(pi: ExtensionAPI) {
  const { code, stdout, truncated } = await pi.exec(
    "/usr/bin/security", ["find-generic-password", "-a", userInfo().username, "-s", KEYCHAIN_SERVICE, "-w"],
    { timeout: 15_000, maxBuffer: 8192 },
  );
  const token = stdout.trim();
  if (code !== 0 || truncated || !/^[A-Za-z0-9._~+/=-]+$/.test(token)) {
    throw new Error(`Cannot read a bearer token from the ${KEYCHAIN_SERVICE} Keychain entry.`);
  }
  return token;
}

function showResult(ctx: ExtensionContext, title: string, text: string, token: string) {
  return openViewer(ctx, title, prepareDisplay(text, token));
}

function mapTools(live: Awaited<ReturnType<HomeAssistantClient["listTools"]>>) {
  const byName = new Map(live.map((tool) => [tool.name, tool]));
  const rows = Object.entries(TOOLS).map(([alias, [name, access]]) => {
    const schema = byName.get(name)?.inputSchema;
    const fields = Object.keys(schema?.properties ?? {}).map((field) => schema?.required?.includes(field) ? `${field}*` : field);
    return `${alias} → ${name} [${schema ? access : "not listed"}] ${fields.join(", ")}`;
  });
  const unmapped = live.filter(({ name }) => !ACCESS.has(name)).map(({ name }) => name);
  return [`* = required. Live tools: ${live.length}.`, ...rows, `Unmapped and inaccessible: ${unmapped.join(", ") || "none"}`].join("\n");
}

export default function homeAssistant(pi: ExtensionAPI) {
  let connection: Connection | undefined;
  let connecting = false;
  let sending = false;
  const approvals = new ApprovalQueue();

  function transcript(text: string) {
    pi.appendEntry(TRANSCRIPT_ENTRY, text);
  }

  function stage(name: string, input: Record<string, unknown>, ctx: ExtensionContext, active: Connection) {
    if (ctx.mode !== "tui" || !ctx.hasUI || ctx.signal?.aborted) return { reason: "Approval requires the Pi terminal." };
    if (sending) return { reason: "Wait for the current Home Assistant request to finish." };
    const { request, reason } = approvals.stage(name, input, active.token);
    if (!request) return { reason };
    const note = ADMIN_TOOLS.has(name) ? " Follow the repo approval rules for infrastructure changes." : "";
    transcript(`Home Assistant needs approval: ${name}\n${terminalText(request.args)}\nType approve ${request.id} or cancel ${request.id} in chat. Expires in ${APPROVAL_MINUTES} minutes.${note}`);
    return { staged: true, reason: `Not sent. The user can type approve ${request.id} or cancel ${request.id} in chat. Do not retry.` };
  }

  async function disconnect() {
    approvals.clear();
    if (!connection) return;
    const { client } = connection;
    connection = undefined;
    pi.unregisterMcpServer(SERVER);
    await client.close().catch(() => undefined);
  }

  pi.on("session_start", disconnect);
  pi.on("session_shutdown", disconnect);
  pi.on("session_tree", () => approvals.clear());
  pi.on("input", async (event, ctx) => {
    const reply = parseApproval(event.text);
    if (!reply) return;
    if (event.source !== "interactive" || ctx.mode !== "tui" || !ctx.isProjectTrusted() || event.images?.length) {
      return { action: "handled" };
    }
    if (!ctx.isIdle() || sending) {
      ctx.ui.notify("Wait for the current turn to finish, then type the approval again.", "warning");
      return { action: "handled" };
    }
    const active = connection;
    const request = active && approvals.take(reply.id);
    if (!active || !request) ctx.ui.notify("No pending Home Assistant request matches that ID.", "warning");
    else if (reply.action === "cancel") transcript(`Home Assistant ${request.id}: canceled. Nothing sent.`);
    else {
      sending = true;
      try {
        const result = await active.client.call(request.name, JSON.parse(request.args));
        const text = prepareDisplay(formatTool(result), active.token);
        const summary = text.length > 4000 ? `${text.slice(0, 4000)}\n[Display limit reached. Use a narrower query.]` : text;
        const status = result.isError ? "returned an error. Check the state before retrying." : "completed.";
        transcript(`Home Assistant ${request.id}: ${status}\n${summary}`);
      } catch {
        transcript(`Home Assistant ${request.id}: no confirmed result. Check the live state before you retry.`);
      } finally {
        sending = false;
      }
    }
    return { action: "handled" };
  });

  pi.on("tool_call", ({ toolName, input }, ctx) => {
    if (!toolName.startsWith(PREFIX)) return;
    const name = toolName.slice(PREFIX.length);
    const active = connection;
    if (!active || !ctx.isProjectTrusted() || !ACCESS.has(name)) {
      return { block: true, reason: "Home Assistant is not connected or this tool is not mapped.", terminate: true };
    }
    if (ACCESS.get(name) !== "read") return { block: true, reason: stage(name, input, ctx, active).reason, terminate: true };
  });

  pi.registerCommand("ha-connect", {
    description: "Connect this Pi session to Home Assistant over HTTPS",
    handler: async (_args, ctx) => {
      if (!ctx.isProjectTrusted() || ctx.mode !== "tui") {
        ctx.ui.notify("Open a trusted inventory project in the Pi terminal first.", "warning");
        return;
      }
      if (connection || connecting) return;
      connecting = true;
      let client: HomeAssistantClient | undefined;
      try {
        const token = await readToken(pi);
        client = new HomeAssistantClient(token);
        await client.connect();
        pi.registerMcpServer(SERVER, {
          url: URL, headers: { Authorization: `Bearer ${token}` }, timeout: 15,
          exposure: "hidden", toolExposure: TOOL_EXPOSURE,
          description: "Home Assistant state and device tools. Writes need approval in the Pi terminal.",
        });
        connection = { client, token };
        ctx.ui.notify("Home Assistant connected. Use /ha-tools or /mcp.", "info");
      } catch (error) {
        await client?.close().catch(() => undefined);
        ctx.ui.notify(error instanceof Error && /^(Cannot read|Home Assistant returned HTTP)/.test(error.message)
          ? error.message : "Home Assistant connection failed. Check HTTPS and the Keychain entry.", "error");
      } finally {
        connecting = false;
      }
    },
  });

  pi.registerCommand("ha-disconnect", {
    description: "Disconnect Home Assistant from this Pi session",
    handler: async (_args, ctx) => {
      await disconnect();
      ctx.ui.notify("Home Assistant disconnected.", "info");
    },
  });

  pi.registerCommand("ha-status", {
    description: "Show Home Assistant registration and native tool count",
    handler: async (_args, ctx) => {
      const count = pi.getAllTools().filter(({ name }) => name.startsWith(PREFIX) && ACCESS.has(name.slice(PREFIX.length))).length;
      ctx.ui.notify(connection ? `Home Assistant is registered. Pi sees ${count}/${ACCESS.size} mapped tools. See /mcp for native status.`
        : "Home Assistant is disconnected. Use /ha-connect.", "info");
    },
  });

  const register = (command: string, description: string, run: (args: string, ctx: ExtensionContext, active: Connection) => Promise<unknown>) => {
    pi.registerCommand(command, {
      description,
      getArgumentCompletions: command === "ha" ? (prefix) => Object.keys(TOOLS).filter((alias) => alias.startsWith(prefix))
        .map((alias) => ({ value: alias, label: alias })) : undefined,
      handler: async (args, ctx) => {
        if (!connection || !ctx.isProjectTrusted() || ctx.mode !== "tui") {
          ctx.ui.notify("Use /ha-connect in the trusted inventory project first.", "warning");
          return;
        }
        const active = connection;
        try {
          await run(args, ctx, active);
        } catch (error) {
          const message = error instanceof Error ? error.message : "Request failed.";
          ctx.ui.notify(terminalText(message.replaceAll(active.token, "[redacted]")), "error");
        }
      },
    });
  };

  register("ha-tools", "List Home Assistant aliases and live argument names", async (_args, ctx, active) =>
    showResult(ctx, "Home Assistant tools", mapTools(await active.client.listTools()), active.token));
  register("ha-snapshot", "View the exposed Home Assistant entity snapshot", async (_args, ctx, active) =>
    showResult(ctx, "Home Assistant snapshot", formatSnapshot(await active.client.snapshot()), active.token));
  register("ha-prompt", "View the Home Assistant MCP prompt without sending it to a model", async (_args, ctx, active) =>
    showResult(ctx, "Home Assistant prompt", formatPrompt(await active.client.prompt()), active.token));
  register("ha", "Run a mapped tool without a model: /ha <alias> [JSON]", async (args, ctx, active) => {
    const { name, input } = parseCommand(args);
    if (ACCESS.get(name) !== "read") {
      const { staged, reason } = stage(name, input, ctx, active);
      if (!staged) ctx.ui.notify(reason, "warning");
      return;
    }
    const result = await active.client.call(name, input);
    const title = `${name}${result.isError ? " returned an error" : ""}`;
    await showResult(ctx, title, formatTool(result), active.token);
  });
}
