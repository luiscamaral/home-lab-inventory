import { PROMPT, RESOURCE, URL } from "./catalog.ts";

const TIMEOUT_MS = 15_000;
const MAX_RESPONSE_BYTES = 512 * 1024;

type JsonObject = Record<string, unknown>;
type Tool = { name: string; inputSchema: { properties?: JsonObject; required?: string[] } };

type Reply = { id?: number; result?: unknown; error?: { code?: number } };

async function readJson(response: Response): Promise<Reply> {
  if (!response.headers.get("content-type")?.toLowerCase().startsWith("application/json")) {
    await response.body?.cancel();
    throw new Error("The Home Assistant shortcut needs a JSON reply. Use native Pi MCP for streamed tool replies.");
  }
  const reader = response.body?.getReader();
  if (!reader) throw new Error("Home Assistant sent no response body.");
  let bytes = 0;
  let text = "";
  const decoder = new TextDecoder();
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    bytes += value.byteLength;
    if (bytes > MAX_RESPONSE_BYTES) {
      await reader.cancel();
      throw new Error("Home Assistant sent more than 512 KiB. Try a narrower query.");
    }
    text += decoder.decode(value, { stream: true });
  }
  try {
    return JSON.parse(text + decoder.decode()) as Reply;
  } catch {
    throw new Error("Home Assistant sent invalid JSON.");
  }
}

export class HomeAssistantClient {
  #headers: Headers;
  #request: typeof fetch;
  #id = 0;

  constructor(token: string, request = fetch) {
    this.#request = request;
    this.#headers = new Headers({
      Authorization: `Bearer ${token}`,
      Accept: "application/json, text/event-stream",
      "Content-Type": "application/json",
    });
  }

  async connect() {
    const info = await this.#rpc<{ protocolVersion?: string }>("initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: { name: "pi-inventory-ha-shortcuts", version: "1.0.0" },
    });
    if (info.protocolVersion !== "2025-06-18" && info.protocolVersion !== "2025-11-25") {
      throw new Error("The Home Assistant shortcut cannot use the negotiated MCP protocol version.");
    }
    this.#headers.set("MCP-Protocol-Version", info.protocolVersion);
    const res = await this.#post({ jsonrpc: "2.0", method: "notifications/initialized" });
    await res.body?.cancel();
  }

  async listTools() {
    const tools: Tool[] = [];
    let cursor: string | undefined;
    for (let page = 0; page < 8; page++) {
      const result = await this.#rpc<{ tools: Tool[]; nextCursor?: string }>("tools/list", cursor ? { cursor } : {});
      tools.push(...result.tools);
      cursor = result.nextCursor;
      if (!cursor) return tools;
    }
    throw new Error("Home Assistant returned too many tool pages.");
  }

  call(name: string, args: JsonObject) {
    return this.#rpc<{ isError?: boolean; content?: unknown; structuredContent?: unknown }>("tools/call", { name, arguments: args });
  }

  prompt() {
    return this.#rpc("prompts/get", { name: PROMPT });
  }

  snapshot() {
    return this.#rpc("resources/read", { uri: RESOURCE });
  }

  async close() {
    if (!this.#headers.has("Mcp-Session-Id")) return;
    const res = await this.#request(URL, {
      method: "DELETE", headers: this.#headers, redirect: "error", signal: AbortSignal.timeout(3000),
    });
    await res.body?.cancel();
  }

  async #post(message: JsonObject) {
    const res = await this.#request(URL, {
      method: "POST", headers: this.#headers, body: JSON.stringify(message),
      redirect: "error", signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!res.ok) {
      await res.body?.cancel();
      throw new Error(`Home Assistant returned HTTP ${res.status}.`);
    }
    return res;
  }

  async #rpc<T>(method: string, params: JsonObject): Promise<T> {
    const id = ++this.#id;
    const response = await this.#post({ jsonrpc: "2.0", id, method, params });
    if (method === "initialize") {
      const session = response.headers.get("Mcp-Session-Id");
      if (session) this.#headers.set("Mcp-Session-Id", session);
    }
    const reply = await readJson(response);
    if (reply?.id !== id) throw new Error("Home Assistant returned an unexpected response ID.");
    if (reply.error) throw new Error(`Home Assistant returned MCP error ${Number(reply.error.code)}.`);
    if (!reply.result || typeof reply.result !== "object") throw new Error("Home Assistant returned no result.");
    return reply.result as T;
  }
}
