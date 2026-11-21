import type { ExtensionContext } from "@earendil-works/pi-coding-agent";

export function openViewer(ctx: ExtensionContext, title: string, text: string) {
  return ctx.ui.custom<boolean>(async (tui, theme, keys, done) => {
    const { matchesKey, truncateToWidth, wrapTextWithAnsi } = await import("@earendil-works/pi-tui");
    let offset = 0;
    let height = 1;
    let cachedWidth = 0;
    let lines: string[] = [];
    const signal = ctx.signal;
    const onAbort = () => done(false);
    if (signal?.aborted) onAbort();
    else signal?.addEventListener("abort", onAbort, { once: true });
    const setOffset = (target: number) => {
      offset = Math.min(Math.max(0, target), Math.max(0, lines.length - height));
    };

    return {
      render(width: number): string[] {
        if (width <= 0) return [];
        height = Math.max(1, Math.min(20, tui.terminal.rows - 10));
        if (cachedWidth !== width) {
          lines = wrapTextWithAnsi(text, width);
          cachedWidth = width;
        }
        setOffset(offset);
        const end = Math.min(offset + height, lines.length);
        return [
          theme.fg("accent", truncateToWidth(title, width)),
          ...lines.slice(offset, end),
          theme.fg("dim", truncateToWidth(`Lines ${offset + 1}–${end}/${lines.length}  ↑/↓ · PgUp/PgDn · Home/End`, width)),
          theme.fg("dim", truncateToWidth("Esc or Enter: close", width)),
        ].map((line) => theme.bg("customMessageBg", truncateToWidth(line, width, "", true)));
      },
      handleInput(input: string) {
        if (keys.matches(input, "tui.select.cancel")) return done(false);
        if (keys.matches(input, "tui.select.confirm")) return done(!signal?.aborted);
        if (keys.matches(input, "tui.select.up")) setOffset(offset - 1);
        else if (keys.matches(input, "tui.select.down")) setOffset(offset + 1);
        else if (keys.matches(input, "tui.select.pageUp")) setOffset(offset - height);
        else if (keys.matches(input, "tui.select.pageDown")) setOffset(offset + height);
        else if (matchesKey(input, "home")) setOffset(0);
        else if (matchesKey(input, "end")) setOffset(lines.length);
        else return;
        tui.requestRender();
      },
      invalidate() { cachedWidth = 0; },
      dispose() { signal?.removeEventListener("abort", onAbort); },
    };
  }, {
    overlay: true,
    overlayOptions: { width: "94%" },
    blocked: { kind: "question", message: title },
  });
}
