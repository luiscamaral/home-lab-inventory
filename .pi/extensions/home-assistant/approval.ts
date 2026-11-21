import { randomBytes } from "node:crypto";

export const APPROVAL_MINUTES = 2;
export const MAX_BATCH_REQUESTS = 8;
const TTL_MS = APPROVAL_MINUTES * 60_000;
const MAX_BYTES = 8192;

type Request = Readonly<{ name: string; args: string }>;
export type Batch = Readonly<{ id: string; requests: readonly Request[]; expiresAt: number }>;

export function parseApproval(text: string) {
  const match = /^(approve all|cancel)\s+(HA-BATCH-[0-9A-F]{8})$/i.exec(text.trim());
  return match && { action: match[1].toLowerCase(), id: match[2].toUpperCase() };
}

export class ApprovalQueue {
  #pending?: Batch;

  current(now = Date.now()) {
    if (this.#pending && now >= this.#pending.expiresAt) this.clear();
    return this.#pending;
  }

  stage(name: string, input: Record<string, unknown>, token: string, now = Date.now()) {
    const existing = this.current(now);
    const args = JSON.stringify(input, null, 2);
    const requests = existing?.requests ?? [];
    if (args.includes(token)) return { reason: "The request contains the connection credential. It was not staged." };
    if (requests.some((request) => request.name === name && request.args === args)) {
      return { reason: `That request is already staged in ${existing!.id}. Do not retry.` };
    }
    if (requests.length >= MAX_BATCH_REQUESTS || Buffer.byteLength(args) + requests.reduce((size, request) => size + Buffer.byteLength(request.args), 0) > MAX_BYTES) {
      return { reason: "The batch reached its limit. The new request was not staged." };
    }
    const id = `HA-BATCH-${randomBytes(4).toString("hex").toUpperCase()}`;
    this.#pending = Object.freeze({
      id, expiresAt: now + TTL_MS, requests: Object.freeze([...requests, Object.freeze({ name, args })]),
    });
    return { batch: this.#pending };
  }

  take(id: string, now = Date.now()) {
    const batch = this.current(now);
    if (!batch || batch.id !== id) return;
    this.clear();
    return batch;
  }

  clear() {
    this.#pending = undefined;
  }
}
