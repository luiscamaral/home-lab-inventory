import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { ACCESS, PREFIX, PROMPT, RESOURCE, SERVER, TOOLS, URL, parseCommand } from "../.pi/extensions/home-assistant/catalog.ts";
import { HomeAssistantClient } from "../.pi/extensions/home-assistant/client.ts";
import extension from "../.pi/extensions/home-assistant/extension.ts";
import { ApprovalQueue, parseApproval } from "../.pi/extensions/home-assistant/approval.ts";
import { formatPrompt, formatSnapshot, formatTool, prepareDisplay } from "../.pi/extensions/home-assistant/results.ts";

const TOKEN = "test-token";

type Request = { id?: number; method: string; params: Record<string, unknown> };

function mockMcp(requests: Request[], reply?: (request: Request) => Response | undefined): typeof fetch {
  return async (url, init) => {
    assert.equal(url, URL);
    assert.equal(init?.redirect, "error");
    const headers = new Headers(init?.headers);
    assert.equal(headers.get("authorization"), `Bearer ${TOKEN}`);
    if (init?.method === "DELETE") {
      assert.equal(headers.get("mcp-session-id"), "test-session");
      return new Response(null, { status: 204 });
    }
    const rpc = JSON.parse(String(init?.body)) as Request;
    requests.push(rpc);
    if (rpc.method === "initialize") {
      return Response.json({ id: rpc.id, result: { protocolVersion: "2025-06-18" } }, { headers: { "Mcp-Session-Id": "test-session" } });
    }
    assert.equal(headers.get("mcp-session-id"), "test-session");
    assert.equal(headers.get("mcp-protocol-version"), "2025-06-18");
    if (rpc.method === "notifications/initialized") return new Response(null, { status: 202 });
    return reply?.(rpc) ?? Response.json({ id: rpc.id, result: { content: [{ text: TOKEN }] } });
  };
}

test("map matches the 32 authenticated tools and accepts only object arguments", () => {
  const evidence = readFileSync(new globalThis.URL("../docs/operations/evidence/2026-11-21-pi-home-assistant-mcp-authenticated.md", import.meta.url), "utf8");
  const reads = [...evidence.matchAll(/^\| `([^`]+__[^`]+)` \|/gm)].map(([, name]) => name);
  const writes = [...evidence.matchAll(/^([a-z]+(?:_[a-z]+)*__[A-Za-z0-9_]+)$/gm)].map(([, name]) => name);
  assert.equal(reads.length, 12);
  assert.equal(writes.length, 20);
  assert.equal(Object.keys(TOOLS).length, 32);
  assert.deepEqual([...ACCESS.keys()].sort(), [...reads, ...writes].sort());
  assert.ok(writes.every((name) => ACCESS.get(name) === "write"));
  for (const [alias, [name]] of Object.entries(TOOLS)) {
    assert.deepEqual(parseCommand(`${alias} {"name":"Test lamp"}`), { name, input: { name: "Test lamp" } });
  }
  assert.throws(() => parseCommand("off []"));
  assert.throws(() => parseCommand("constructor"));
  assert.throws(() => parseCommand("off {bad json}"));
});

test("shortcut client handles sessions, pagination, prompt, resource, and an uncertain write once", async () => {
  const requests: Request[] = [];
  const client = new HomeAssistantClient(TOKEN, mockMcp(requests, (rpc) => {
    if (rpc.method === "tools/list") {
      const result = rpc.params.cursor === "page2" ? { tools: [{ name: "second" }] } : { tools: [{ name: "first" }], nextCursor: "page2" };
      return Response.json({ id: rpc.id, result });
    }
    if (rpc.method === "tools/call") return new Response(null, { status: 504 });
  }));
  await client.connect();
  assert.deepEqual((await client.listTools()).map((tool) => tool.name), ["first", "second"]);
  await client.prompt();
  await client.snapshot();
  await assert.rejects(client.call("intent__HassTurnOff", { name: "Test lamp" }), /504/);
  await client.close();
  assert.deepEqual(requests.find(({ method }) => method === "prompts/get")?.params, { name: PROMPT });
  assert.deepEqual(requests.find(({ method }) => method === "resources/read")?.params, { uri: RESOURCE });
  assert.equal(requests.filter(({ method }) => method === "tools/call").length, 1);
});

test("snapshot and prompt show multiline text instead of the MCP envelopes", () => {
  const text = "- names: Test light\n  state: on\n";
  const snapshot = formatSnapshot({ contents: [{ text, uri: RESOURCE }, { uri: "fixture://binary", blob: "AAAB" }] });
  assert.ok(snapshot.startsWith(text));
  assert.ok(!snapshot.includes('"contents"') && !snapshot.includes("AAAB") && !snapshot.includes("\\n"));
  const prompt = formatPrompt({ description: "Test prompt", messages: [
    { role: "user", content: { type: "text", text: "Line one\nLine two" } },
    { role: "assistant", content: { type: "image", data: "AAA=" } },
  ] });
  assert.equal(prompt, "Test prompt\n\n[user]\nLine one\nLine two\n\n[assistant]\n[image content omitted]");
  assert.match(formatSnapshot({ contents: [] }), /no displayable content/);
});

test("tool results show structured data, multiline logs, plain text, and errors", () => {
  const payload = { logs: "first\nsecond", count: 0, active: false };
  const result = formatTool({ content: [{ type: "text", text: JSON.stringify(payload) }], structuredContent: payload });
  assert.equal(result, "logs:\n  first\n  second\ncount: 0\nactive: false");
  assert.equal(formatTool({ structuredContent: { devices: [{ name: "🚦 灯", state: null }] } }), "devices:\n  - name: 🚦 灯\n    state: null");
  assert.equal(formatTool({ content: [{ type: "text", text: "[2026-11-21] log" }] }), "[2026-11-21] log");
  assert.equal(formatTool({ content: [{ type: "resource", resource: { uri: RESOURCE, text: "line 1\nline 2" } }] }), "line 1\nline 2");
  assert.equal(formatTool({ isError: true, content: [{ type: "text", text: "No match found." }] }), "No match found.");
  assert.match(formatTool({ isError: true }), /error without details/);
});

test("display redacts credentials and terminal control characters without losing line breaks", () => {
  const formatted = prepareDisplay(`first\r\n\t${TOKEN}\n\x1b[2J\u202edisplay`, TOKEN);
  assert.equal(formatted, "first\n    [redacted]\n\\u{1b}[2J\\u{202e}display");
  const long = prepareDisplay("a".repeat(127_999) + "🚦rest", TOKEN);
  assert.ok(long.includes("Display limit reached"));
  assert.ok(!long.includes("\ud83d"));
});

test("approval IDs are exact, tied to frozen requests, and expire", () => {
  const queue = new ApprovalQueue();
  const input = { name: "Original" };
  const first = queue.stage("off", input, TOKEN, 100).batch!;
  input.name = "Changed";
  assert.equal(parseApproval(`Approve All ${first.id.toLowerCase()}`)?.id, first.id);
  assert.equal(parseApproval(`approve all ${first.id} then turn off another light`), null);
  assert.equal(parseApproval(`approve ${first.id}`), null);
  assert.equal(parseApproval("approve all"), null);
  const second = queue.stage("on", input, TOKEN, 105).batch!;
  assert.notEqual(second.id, first.id);
  assert.equal(first.requests.length, 1);
  assert.equal(second.requests.length, 2);
  assert.equal(queue.take(first.id, 110), undefined);
  assert.match(queue.stage("on", input, TOKEN, 110).reason!, /already staged/);
  assert.equal(queue.current(110)?.id, second.id);
  assert.equal(queue.take(second.id, second.expiresAt), undefined);
  assert.equal(queue.stage("off", { secret: TOKEN }, TOKEN, 200_000).batch, undefined);
  const third = queue.stage("off", { name: "Original" }, TOKEN, 200_000).batch!;
  assert.equal(JSON.parse(queue.take(third.id, 200_010)!.requests[0].args).name, "Original");
  assert.equal(queue.take(third.id, 200_011), undefined);
  assert.equal(JSON.parse(second.requests[0].args).name, "Original");
  for (let i = 0; i < 8; i++) assert.ok(queue.stage("on", { i }, TOKEN, 200_020).batch);
  assert.match(queue.stage("on", { i: 8 }, TOKEN, 200_020).reason!, /limit/);
  queue.clear();
  assert.match(queue.stage("on", { name: "x".repeat(8192) }, TOKEN, 200_020).reason!, /limit/);
});

test("native and slash writes wait for a single matching human chat reply", async (t) => {
  type Handler = (...args: any[]) => any;
  const handlers = new Map<string, Handler>();
  const commands = new Map<string, { handler: Handler }>();
  const requests: Request[] = [];
  const registrations: Array<[string, Record<string, any>]> = [];
  const removed: string[] = [];
  const entries: string[] = [];
  const pi = {
    on: (event: string, handler: Handler) => handlers.set(event, handler),
    registerCommand: (name: string, command: { handler: Handler }) => commands.set(name, command),
    registerMcpServer: (...args: [string, Record<string, any>]) => registrations.push(args),
    unregisterMcpServer: (name: string) => removed.push(name),
    exec: async () => ({ code: 0, stdout: TOKEN }),
    getAllTools: () => [],
    appendEntry: (_kind: string, text: string) => entries.push(text),
  } as unknown as ExtensionAPI;
  let idle = true;
  const ctx = {
    hasUI: true, mode: "tui", isProjectTrusted: () => true, isIdle: () => idle,
    ui: { notify: () => undefined },
  } as unknown as ExtensionContext;
  let failTool = "";
  t.mock.method(globalThis, "fetch", mockMcp(requests, (rpc) => {
    if (rpc.method === "tools/call" && rpc.params.name === failTool) return new Response(null, { status: 504 });
  }));
  extension(pi);
  assert.equal(commands.size, 8);
  assert.equal(registrations.length, 0);
  const run = (name: string, args = "") => commands.get(name)!.handler(args, ctx);
  const gate = (name: string, context = ctx) => handlers.get("tool_call")!({ toolName: PREFIX + name, input: { name: "Test lamp" } }, context);
  await run("ha-connect");
  assert.equal(registrations[0][0], SERVER);
  assert.equal(registrations[0][1].exposure, "hidden");
  assert.deepEqual(Object.keys(registrations[0][1].toolExposure).sort(), [...ACCESS.keys()].sort());
  assert.equal(await gate("homeassistant__GetLiveContext"), undefined);
  assert.equal((await gate("unknown")).block, true);
  const reply = (text: string, source = "interactive") => handlers.get("input")!({ text, source }, ctx);
  const callParams = () => requests.filter(({ method }) => method === "tools/call").map(({ params }) => params);
  const currentId = () => /Type approve all (HA-BATCH-[A-F0-9]{8})/.exec(entries.at(-1)!)![1];
  assert.equal((await gate("intent__HassTurnOn", { ...ctx, mode: "rpc" })).block, true);
  assert.equal(entries.length, 0);
  assert.equal((await gate("intent__HassTurnOn")).block, true);
  assert.match(entries.at(-1)!, /"name": "Test lamp"/);
  const oldId = currentId();
  assert.equal((await gate("intent__HassTurnOff")).block, true);
  const id = currentId();
  assert.notEqual(id, oldId);
  assert.match(entries.at(-1)!, /1\. intent__HassTurnOn[\s\S]+2\. intent__HassTurnOff/);
  await run("ha-batch");
  assert.equal(currentId(), id);
  assert.equal(await reply("approve all"), undefined);
  assert.equal((await reply(`approve all ${id}`, "extension")).action, "handled");
  assert.equal((await reply(`approve all ${id}`, "rpc")).action, "handled");
  await reply(`approve all ${oldId}`);
  idle = false;
  await reply(`approve all ${id}`);
  idle = true;
  assert.deepEqual(callParams(), []);
  await reply(`approve all ${id}`);
  assert.match(entries.at(-1)!, /completed\.\n\[redacted\]/);
  await reply(`approve all ${id}`);
  assert.deepEqual(callParams(), [
    { name: "intent__HassTurnOn", arguments: { name: "Test lamp" } },
    { name: "intent__HassTurnOff", arguments: { name: "Test lamp" } },
  ]);
  await run("ha", 'off {"name":"Test lamp"}');
  await reply(`cancel ${currentId()}`);
  assert.match(entries.at(-1)!, /canceled\. Nothing sent/);
  await run("ha", 'template {"template":"{{ 2 + 2 }}"}');
  const templateId = currentId();
  handlers.get("session_tree")!();
  await reply(`approve all ${templateId}`);
  assert.equal(callParams().length, 2);
  failTool = "intent__HassTurnOff";
  await run("ha", 'off {"name":"Test lamp"}');
  await run("ha", 'on {"name":"Test lamp"}');
  await reply(`approve all ${currentId()}`);
  assert.equal(callParams().length, 3);
  assert.match(entries.at(-1)!, /stopped after 0\/2 confirmed successes/);
  await handlers.get("session_start")!();
  assert.deepEqual(removed, [SERVER]);
  assert.equal((await gate("homeassistant__GetLiveContext")).block, true);
});
