import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import homeAssistant, { TRANSCRIPT_ENTRY } from "./extension.ts";

export default function (pi: ExtensionAPI) {
  pi.registerEntryRenderer<string>(TRANSCRIPT_ENTRY, (entry, _options, theme) =>
    new Text(typeof entry.data === "string" ? entry.data : "", 1, 0, (line) => theme.bg("customMessageBg", line)));
  homeAssistant(pi);
}
