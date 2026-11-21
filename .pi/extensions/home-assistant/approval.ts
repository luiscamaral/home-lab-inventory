import { randomBytes } from "node:crypto";

export const APPROVAL_MINUTES = 2;
const TTL_MS = APPROVAL_MINUTES * 60_000;
const MAX_BYTES = 8192;

type Pending = { id: string; name: string; args: string; expiresAt: number };

export function parseApproval(text: string) {
  const match = /^(approve|cancel)\s+(HA-[0-9A-F]{8})$/i.exec(text.trim());
  return match && { action: match[1].toLowerCase(), id: match[2].toUpperCase() };
}

export class ApprovalQueue {
  #pending?: Pending;

  current(now = Date.now()) {
    if (this.#pending && now >= this.#pending.expiresAt) this.clear();
    return this.#pending;
  }

  stage(name: string, input: Record<string, unknown>, token: string, now = Date.now()) {
    const existing = this.current(now);
    if (existing) return { reason: `Request ${existing.id} is already pending. Approve or cancel it first.` };
    const args = JSON.stringify(input, null, 2);
    if (Buffer.byteLength(args) > MAX_BYTES || args.includes(token)) {
      return { reason: "The request is too large or contains the connection credential. No request was staged." };
    }
    this.#pending = Object.freeze({ id: `HA-${randomBytes(4).toString("hex").toUpperCase()}`, name, args, expiresAt: now + TTL_MS });
    return { request: this.#pending };
  }

  take(id: string, now = Date.now()) {
    const request = this.current(now);
    if (!request || request.id !== id) return;
    this.clear();
    return request;
  }

  clear() {
    this.#pending = undefined;
  }
}
