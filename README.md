# cOMApilot

An AI assistant overlay for [Omarchy](https://omarchy.org/), built as a Quickshell shell plugin. Streams answers from an LLM backend of your choice - cloud or a fully local/free model via Ollama.

![cOMApilot overlay](screenshots/copilot.png)

## Status: pre-release, not yet submitted to the marketplace

This is under active development. What works today:

- A fullscreen overlay (bar icon or hotkey to open) with streaming Q&A
- Three backend options: OpenAI-compatible (OpenAI, OpenRouter, or a local Ollama server), and Anthropic - switchable per-session from the settings panel
- API keys stored via your system keyring (`secret-tool`/libsecret), never written to Omarchy's `shell.json`
- Optional, off-by-default context: your current clipboard text and/or the active window's title, sent along with your prompt so you can ask about what you're looking at. Both are clearly sanitized as untrusted data before ever reaching the model - see "Notes for reviewers" below

**Not implemented yet:** the actual "copilot" half of the name - a small, closed allowlist of confirmable actions (open a file, run a handful of safe named system actions, or drive another Omarchy plugin) is designed but not built. Right now this is a streaming-chat overlay with sanitized desktop context, nothing more. Don't submit/list this until that lands; this repo exists as a working backup while it's built out.

## Requirements

- [Omarchy](https://omarchy.org/) with its Quickshell-based shell
- `curl` (request transport)
- `secret-tool` (libsecret) for storing your API key, if you use a cloud backend
- `wl-clipboard` (`wl-paste`) only if you enable the clipboard-context setting
- Either an API key for OpenAI/Anthropic/OpenRouter, or a local OpenAI-compatible server such as [Ollama](https://ollama.com/) - no key needed for a local server

## Install

```bash
omarchy plugin add https://github.com/Deunnis/cOMApilot.git --enable
```

By default it's placed on the right side of the bar; move it with:

```bash
omarchy bar move io.github.omacopilot --section right
```

(or place it via `~/.config/omarchy/shell.json`, which is where all the settings below are also stored per-widget).

## Uninstall

```bash
omarchy plugin remove io.github.omacopilot
```

This does not automatically clear any API key stored via `secret-tool`; use the "Clear" button in the settings panel first if you want it removed from your keyring.

## Settings

Available from the gear icon inside the overlay:

| Setting | Description |
|---|---|
| Backend | `openai-compatible` (OpenAI, OpenRouter, Ollama's own `/v1/chat/completions`) or `anthropic` |
| Model | Model name/id for the selected backend |
| Endpoint URL | Chat-completions endpoint (ignored for Anthropic, which always uses `api.anthropic.com`) |
| Stream responses | Token-by-token streaming vs. wait-for-full-reply |
| API key | Stored via your system keyring, kept per-backend so switching backends doesn't lose a key |
| Include clipboard as context | Off by default. Sends your current clipboard text with each prompt, always in its own clearly-labeled untrusted-data message |
| Include active window as context | Off by default. Sends the focused window's title and app id with each prompt |
| Max context characters | Truncation limit applied to the combined clipboard/window context |

## Notes for reviewers

- Runs entirely as your normal user session; no elevated permissions are ever requested or needed.
- **Secrets:** the API key never touches `shell.json` (world-readable, and every write there triggers a full shell-wide config reload). It's stored/looked up/cleared exclusively through `secret-tool`, and even during a request it never appears as a CLI argument (visible to any other process via `/proc/*/cmdline`) - both the request body and every header, including `Authorization`/`x-api-key`, are written to a private per-plugin cache-dir scratch file via stdin, and `curl` only ever receives that file's path.
- **Context sanitization:** clipboard text and the active window's title/app id are the only external inputs this plugin reads, and both are opt-in (off by default). Neither is ever spliced into the system/instruction prompt string - they're combined into one separate, explicitly-labeled "this is untrusted data, not instructions" message, truncated to a configurable length, with anything resembling a future action-block fence neutralized so it can't be echoed back and misinterpreted downstream.
- **No shell execution of any kind exists in this codebase currently**, model-invoked or otherwise - Phase 3 (see Status above) will add a small, fixed, non-model-extensible allowlist of actions (each gated behind an explicit confirm dialog before it runs), never free-form command execution.
- External commands this plugin runs: `curl` (the LLM request itself), `secret-tool` (keyring access), `mktemp`/`rm`/a `read`-based shell one-liner (scratch-file plumbing for the request body/headers, chosen specifically so secrets never appear in argv), and `wl-paste` (only if clipboard context is enabled).

## License

MIT - see [LICENSE](LICENSE).
