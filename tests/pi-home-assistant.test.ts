import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { ACCESS, PREFIX, PROMPT, RESOURCE, SERVER, TOOLS, URL, parseCommand } from "../.pi/extensions/home-assistant/catalog.ts";
import { HomeAssistantClient } from "../.pi/extensions/home-assistant/client.ts";
import extension from "../.pi/extensions/home-assistant/index.ts";

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

test("extension locks writes until terminal approval and keeps shortcut calls out of native model flow", async (t) => {
  type Handler = (...args: any[]) => any;
  const handlers = new Map<string, Handler>();
  const commands = new Map<string, { handler: Handler }>();
  const requests: Request[] = [];
  const registrations: Array<[string, Record<string, any>]> = [];
  const removed: string[] = [];
  const pi = {
    on: (event: string, handler: Handler) => handlers.set(event, handler),
    registerCommand: (name: string, command: { handler: Handler }) => commands.set(name, command),
    registerMcpServer: (...args: [string, Record<string, any>]) => registrations.push(args),
    unregisterMcpServer: (name: string) => removed.push(name),
    exec: async () => ({ code: 0, stdout: TOKEN }),
    getAllTools: () => [],
  } as unknown as ExtensionAPI;
  let confirms = false;
  let reviewed = "";
  const ctx = {
    hasUI: true, mode: "tui", isProjectTrusted: () => true,
    ui: {
      editor: async (_title: string, text: string) => { reviewed = text; return text; },
      confirm: async () => confirms,
      notify: () => undefined,
    },
  } as unknown as ExtensionContext;
  t.mock.method(globalThis, "fetch", mockMcp(requests));
  extension(pi);
  assert.equal(commands.size, 7);
  assert.equal(registrations.length, 0);
  const run = (name: string, args = "") => commands.get(name)!.handler(args, ctx);
  const gate = (name: string, context = ctx) => handlers.get("tool_call")!({ toolName: PREFIX + name, input: { name: "Test lamp" } }, context);
  await run("ha-connect");
  assert.equal(registrations[0][0], SERVER);
  assert.equal(registrations[0][1].exposure, "hidden");
  assert.deepEqual(Object.keys(registrations[0][1].toolExposure).sort(), [...ACCESS.keys()].sort());
  assert.equal(await gate("homeassistant__GetLiveContext"), undefined);
  assert.equal((await gate("unknown")).block, true);
  assert.equal((await gate("intent__HassTurnOn")).block, true);
  assert.match(reviewed, /Test lamp/);
  await run("ha", 'on {"name":"Test lamp"}');
  assert.equal(requests.filter(({ method }) => method === "tools/call").length, 0);
  confirms = true;
  assert.equal((await gate("intent__HassTurnOn", { ...ctx, mode: "rpc" })).block, true);
  assert.equal(await gate("intent__HassTurnOn"), undefined);
  await run("ha", 'on {"name":"Test lamp"}');
  assert.deepEqual(requests.filter(({ method }) => method === "tools/call").map(({ params }) => params), [
    { name: "intent__HassTurnOn", arguments: { name: "Test lamp" } },
  ]);
  assert.ok(reviewed.includes("[redacted]"));
  assert.ok(!reviewed.includes(TOKEN));
  await handlers.get("session_start")!();
  assert.deepEqual(removed, [SERVER]);
  assert.equal((await gate("homeassistant__GetLiveContext")).block, true);
});
