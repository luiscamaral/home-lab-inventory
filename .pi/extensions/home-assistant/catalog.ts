type Access = "read" | "review" | "write";

export const SERVER = "inventory_ha";
export const PREFIX = `mcp__${SERVER}__`;
export const URL = "https://ha.home.lcamaral.com/api/mcp";
export const RESOURCE = "homeassistant://assist/context-snapshot";
export const PROMPT = "Merged LLM API";

export const TOOLS = {
  state: ["homeassistant__GetLiveContext", "read"],
  time: ["llm__GetDateTime", "read"],
  "todo-items": ["todo__get_items", "read"],
  integrations: ["config__get_config_entries", "read"],
  "integration-search": ["config__search_integrations", "read"],
  logs: ["hassio__get_logs", "read"],
  history: ["history__get_history", "read"],
  template: ["homeassistant__render_template", "review"],
  "action-search": ["homeassistant__search_actions", "read"],
  search: ["search__search", "read"],
  health: ["system_health__get_system_info", "read"],
  "system-log": ["system_log__get_entries", "read"],
  broadcast: ["assist_satellite__HassBroadcast", "write"],
  on: ["intent__HassTurnOn", "write"],
  off: ["intent__HassTurnOff", "write"],
  position: ["intent__HassSetPosition", "write"],
  stop: ["intent__HassStopMoving", "write"],
  "timers-cancel": ["intent__HassCancelAllTimers", "write"],
  light: ["light__HassLightSet", "write"],
  play: ["media_player__HassMediaUnpause", "write"],
  pause: ["media_player__HassMediaPause", "write"],
  next: ["media_player__HassMediaNext", "write"],
  previous: ["media_player__HassMediaPrevious", "write"],
  volume: ["media_player__HassSetVolume", "write"],
  "volume-step": ["media_player__HassSetVolumeRelative", "write"],
  mute: ["media_player__HassMediaPlayerMute", "write"],
  unmute: ["media_player__HassMediaPlayerUnmute", "write"],
  "todo-add": ["todo__HassListAddItem", "write"],
  "todo-complete": ["todo__HassListCompleteItem", "write"],
  "todo-remove": ["todo__HassListRemoveItem", "write"],
  "integration-reload": ["config__reload_config_entry", "write"],
  action: ["homeassistant__call_action", "write"],
} as const satisfies Record<string, readonly [string, Access]>;

export const ACCESS = new Map<string, Access>(Object.values(TOOLS));
export const TOOL_EXPOSURE = Object.fromEntries(
  Object.values(TOOLS).map(([name, access]) => [name, access === "read" ? "codemode" : "deferred"] as const),
);

export function parseCommand(args: string) {
  const [, alias, raw] = /^(\S+)(?:\s+([\s\S]*))?$/.exec(args.trim()) ?? [];
  if (!alias || !Object.hasOwn(TOOLS, alias)) throw new Error("Use /ha-tools to see the command aliases.");
  const input: unknown = raw ? JSON.parse(raw) : {};
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("Arguments must be a JSON object.");
  const [name] = TOOLS[alias as keyof typeof TOOLS];
  return { name, input: input as Record<string, unknown> };
}

export function terminalText(text: string) {
  return text.replace(/[\p{Cc}\p{Cf}]/gu, (char) =>
    char === "\n" || char === "\t" ? char : `\\u{${char.codePointAt(0)!.toString(16)}}`);
}
