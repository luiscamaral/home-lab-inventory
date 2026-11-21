import { terminalText } from "./catalog.ts";

const MAX_DISPLAY_CHARS = 128_000;
const EMPTY = "Home Assistant returned no displayable content.";

type RecordValue = Record<string, unknown>;

function record(value: unknown): RecordValue {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as RecordValue : {};
}

function list(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function indent(text: string, prefix: string) {
  return text.split("\n").map((line) => prefix + line).join("\n");
}

function fields(value: unknown, depth = 0): string {
  if (depth >= 20) return "[Nested value omitted]";
  if (Array.isArray(value)) {
    return value.map((item) => `- ${indent(fields(item, depth + 1), "  ").slice(2)}`).join("\n") || "[]";
  }
  if (value !== null && typeof value === "object") {
    return Object.entries(value).map(([key, item]) => {
      const text = fields(item, depth + 1);
      return text.includes("\n") || (item !== null && typeof item === "object")
        ? `${JSON.stringify(key).slice(1, -1)}:\n${indent(text, "  ")}` : `${JSON.stringify(key).slice(1, -1)}: ${text}`;
    }).join("\n") || "{}";
  }
  return value === "" ? '""' : String(value);
}

function toolText(text: string) {
  const trimmed = text.trimStart();
  if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) return text;
  try {
    return fields(JSON.parse(text));
  } catch {
    return text;
  }
}

function block(value: unknown, formatText: (text: string) => string): string {
  const item = record(value);
  if (typeof item.text === "string") return formatText(item.text);
  if (item.type === "resource") return block(item.resource, formatText);
  if (typeof item.uri === "string") return `[Resource: ${item.uri}]`;
  if (typeof item.type === "string") return `[${item.type} content omitted]`;
  if (typeof item.mimeType === "string") return `[${item.mimeType} content omitted]`;
  return "";
}

export function formatSnapshot(reply: unknown) {
  return list(record(reply).contents).map((item) => block(item, (text) => text)).filter(Boolean).join("\n\n") || EMPTY;
}

export function formatPrompt(reply: unknown) {
  const { description, messages } = record(reply);
  const parts = list(messages).map((message) => {
    const { role, content } = record(message);
    const text = block(content, (value) => value);
    return text ? `[${typeof role === "string" ? role : "message"}]\n${text}` : "";
  });
  if (typeof description === "string") parts.unshift(description);
  return parts.filter(Boolean).join("\n\n") || EMPTY;
}

export function formatTool(reply: unknown) {
  const { content, structuredContent, isError } = record(reply);
  const parts = list(content).map((item) => block(item, toolText)).filter(Boolean);
  if (structuredContent !== undefined) {
    const formatted = fields(structuredContent);
    if (!parts.includes(formatted)) parts.push(formatted);
  }
  return parts.join("\n\n") || (isError ? "Home Assistant returned an error without details." : EMPTY);
}

export function prepareDisplay(text: string, token: string) {
  const safe = terminalText(text.replaceAll(token, "[redacted]").replaceAll("\r\n", "\n").replaceAll("\t", "    "));
  if (safe.length <= MAX_DISPLAY_CHARS) return safe;
  return `${safe.slice(0, MAX_DISPLAY_CHARS).replace(/[\uD800-\uDBFF]$/, "")}\n\n[Display limit reached. Use a narrower query.]`;
}
