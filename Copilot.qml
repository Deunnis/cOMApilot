import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "OpenAiCompatBackend.js" as OpenAiCompatBackend
import "AnthropicBackend.js" as AnthropicBackend
import "ConversationModel.js" as ConversationModel
import "Secrets.js" as Secrets
import "ContextSanitizer.js" as ContextSanitizer
import "ActionAllowlist.js" as ActionAllowlist
import "ActionParser.js" as ActionParser
import "WallpaperPalette.js" as WallpaperPalette

Item {
  id: root

  property bool opened: false
  readonly property string moduleName: "io.github.comapilot"

  // Auto-wired by shell.qml's panel Loader (see its onLoaded: `if ("shell"
  // in item) item.shell = shell`) once this overlay is instantiated - not
  // available yet during this Item's own Component.onCompleted, only once
  // onShellChanged fires.
  property var shell: null
  onShellChanged: root.loadSettings()

  property var settings: ({
    backend: "openai-compatible",
    model: "gpt-4o-mini",
    endpointUrl: "https://api.openai.com/v1/chat/completions",
    streaming: true,
    includeClipboardContext: false,
    includeActiveWindowContext: false,
    maxContextChars: 4000,
    actionsEnabled: false,
    blur: 40,
    transparency: 40,
    borderWidth: 2,
    cornerRadius: 2
  })
  property bool settingsOpen: false

  // Reads the persisted entry for this plugin id out of shell.json (mirrors
  // what shell.qml's own updateEntryInline() looks up internally) since an
  // overlay-kind root, unlike a BarWidget-kind root, has no built-in
  // settings/setting() of its own.
  function findSettingsEntry(cfg) {
    if (!cfg) return null
    var layout = cfg.bar && cfg.bar.layout
    if (layout) {
      var sections = ["left", "center", "right"]
      for (var s = 0; s < sections.length; s++) {
        var arr = layout[sections[s]] || []
        for (var i = 0; i < arr.length; i++) {
          if (arr[i] && arr[i].id === root.moduleName) return arr[i]
        }
      }
    }
    var plugins = cfg.plugins || []
    for (var j = 0; j < plugins.length; j++) {
      if (plugins[j] && plugins[j].id === root.moduleName) return plugins[j]
    }
    return null
  }

  function loadSettings() {
    if (!root.shell) return
    var found = root.findSettingsEntry(root.shell.shellConfig)
    var merged = {
      backend: "openai-compatible",
      model: "gpt-4o-mini",
      endpointUrl: "https://api.openai.com/v1/chat/completions",
      streaming: true,
      includeClipboardContext: false,
      includeActiveWindowContext: false,
      maxContextChars: 4000,
      actionsEnabled: false,
      blur: 40,
      transparency: 40,
      borderWidth: 2,
      cornerRadius: 2
    }
    if (found) for (var k in found) if (k !== "id") merged[k] = found[k]
    root.settings = merged
  }

  function persistSetting(key, value) {
    var entry = {}
    for (var k in root.settings) entry[k] = root.settings[k]
    entry[key] = value
    root.settings = entry
    if (root.shell && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline(root.moduleName, entry)
  }

  function backendModule() {
    return root.settings.backend === "anthropic" ? AnthropicBackend : OpenAiCompatBackend
  }

  // ---------------------------------------------------------------- chrome
  //
  // blur/transparency/borderWidth/cornerRadius mirror OmaDeezer's popup
  // settings exactly (same ranges/defaults, same live-drag-then-persist
  // pattern) at the user's request. Each has a "live" mirror that a slider
  // updates continuously while dragging (no disk writes mid-drag) and which
  // gets rebound to the persisted value via relive() once the drag commits -
  // see VISUAL_SLIDER_DEFS and relive() below.

  property color background: Qt.tint(Util.alpha(Color.menu.background, 1 - root.liveTransparency / 100), Util.alpha(root.accentColor, 0.12))
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.flat(root.border, Style.space(root.liveBorderWidth))
  property color scrim: Color.menu.scrim
  readonly property int cornerRadius: Style.space(root.liveCornerRadius)
  property string fontFamily: Style.font.menuFamily

  readonly property var visualSliderDefs: [
    { key: "blur", label: "Blur", from: 0, to: 100, def: 40 },
    { key: "transparency", label: "Transparency", from: 0, to: 100, def: 40 },
    { key: "borderWidth", label: "Outline thickness", from: 0, to: 6, def: 2 },
    { key: "cornerRadius", label: "Corner roundness", from: 0, to: 20, def: 2 }
  ]

  property int liveBlur: 40
  property int liveTransparency: 40
  property int liveBorderWidth: 2
  property int liveCornerRadius: 2

  function liveKeyFor(key) { return "live" + key.charAt(0).toUpperCase() + key.slice(1) }

  function visualDefaultFor(key) {
    for (var i = 0; i < root.visualSliderDefs.length; i++) if (root.visualSliderDefs[i].key === key) return root.visualSliderDefs[i].def
    return 0
  }

  // (Re)binds live<Key> to follow root.settings[key] (falling back to def)
  // until the next drag breaks the binding by assigning a literal value -
  // called once at startup for all four, and again after each one's own
  // slider release re-persists it.
  function relive(key, def) {
    root[root.liveKeyFor(key)] = Qt.binding(function() {
      return root.settings[key] !== undefined ? root.settings[key] : def
    })
  }

  function resetVisualDefaults() {
    var entry = {}
    for (var k in root.settings) entry[k] = root.settings[k]
    for (var i = 0; i < root.visualSliderDefs.length; i++) entry[root.visualSliderDefs[i].key] = root.visualSliderDefs[i].def
    root.settings = entry
    if (root.shell && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline(root.moduleName, entry)
    for (var j = 0; j < root.visualSliderDefs.length; j++) root.relive(root.visualSliderDefs[j].key, root.visualSliderDefs[j].def)
  }

  // Same global side effect as OmaDeezer's identical slider: this sets
  // Hyprland's *global* decoration.blur.size, so turning it up blurs behind
  // every window/layer, not just this overlay.
  function applyBlur() {
    var size = Math.round(root.liveBlur / 100 * 20)
    blurProc.command = ["hyprctl", "eval", "hl.config({decoration={blur={size=" + size + "}}})"]
    blurProc.running = true
  }

  Process { id: blurProc }

  onLiveBlurChanged: root.applyBlur()

  // The blur *size* above is a global Hyprland setting, but a layer surface
  // only actually gets blurred if something has told Hyprland to blur that
  // specific namespace in the first place - confirmed by direct testing:
  // with no layer rule at all, the Blur slider correctly changed
  // decoration:blur:size (verified via `hyprctl getoption`) with zero
  // visible pixel difference behind this overlay (confirmed with
  // `magick compare -metric AE`, not just eyeballed - the first attempt at
  // this fix used a made-up `hl.config({layerrule=...})` shape that
  // returned "ok" from `hyprctl eval` but was silently a no-op).
  //
  // This machine's Hyprland runs Omarchy's own Lua config bridge
  // (`hyprctl systeminfo` reports `configProvider: lua`, and `hyprctl
  // keyword` itself refuses with "can't work with non-legacy parsers") -
  // there's no plain-text hyprland.conf `layerrule = blur, ...` line to
  // reach for. The real API, found by reading Omarchy's own
  // `/usr/share/hypr/stubs/hl.meta.lua` and a genuine first-party example
  // in `/usr/share/omarchy/default/hypr/apps/omarchy-shell.lua`
  // (`hl.layer_rule({match={namespace=...}, ...})`), is a *function* -
  // `hl.layer_rule(spec)` - not a `hl.config()` key at all. Re-verified with
  // the same pixel-diff technique: a real, nonzero difference appeared only
  // once this correct call was used.
  function applyBlurLayerRule() {
    layerRuleProc.command = ["hyprctl", "eval", "hl.layer_rule({match={namespace=\"comapilot\"},blur=true})"]
    layerRuleProc.running = true
  }

  Process { id: layerRuleProc }
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int cardWidth: Math.min(Style.space(700), scrimWindow.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(560), scrimWindow.height - Style.gapsOut * 2)

  // --------------------------------------------------- wallpaper-adaptive accent
  //
  // Same approach as OmaDeezer's popup: a 5-color histogram of the current
  // wallpaper via ImageMagick, most-common color first, re-extracted whenever
  // the wallpaper changes. Every accent-colored control below (Send/Run/
  // Regenerate buttons, settings inputs, the user's own message bubbles)
  // pulls from this instead of the theme's static Color.accent.
  readonly property var backgroundService: root.shell ? root.shell.firstPartyServiceFor("omarchy.background") : null
  readonly property string backgroundPath: backgroundService ? backgroundService.currentBackground : ""
  property var paletteHex: []

  // Raw histogram colors are often shadow-black or highlight-white; keep the
  // hue but clamp lightness/saturation into a legible band - same formula
  // and same reasoning as OmaDeezer's legibleAccent().
  function legibleAccent(hex) {
    var c = Qt.color(hex)
    var l = Math.max(0.42, Math.min(0.72, c.hslLightness))
    var s = Math.max(c.hslSaturation, 0.35)
    return Qt.hsla(c.hslHue, s, l, 1.0)
  }

  readonly property color accentColor: root.paletteHex.length > 0 ? root.legibleAccent(root.paletteHex[0]) : Color.accent

  function extractPalette() {
    if (!root.backgroundPath) return
    paletteProc.command = WallpaperPalette.paletteCommand(root.backgroundPath)
    paletteProc.running = true
  }

  Process {
    id: paletteProc
    stdout: StdioCollector {
      id: paletteOutput
      onStreamFinished: root.paletteHex = WallpaperPalette.parsePaletteHex(paletteOutput.text)
    }
  }

  onBackgroundPathChanged: root.extractPalette()

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  // ------------------------------------------------------------ conversation

  ListModel { id: conversation }

  // Action cards are deliberately NOT stored as a ListModel row role.
  // ListModel.setProperty() on an already-materialized delegate does not
  // reliably re-notify a `required property var` bound to an array/object-
  // typed dynamic role (confirmed by direct testing: neither the bound
  // property's own onChanged handler nor a Repeater child's
  // Component.onCompleted ever fired after a setProperty call, even though
  // the ListModel's own underlying data was correctly updated) - a real
  // platform quirk, not a logic bug in the code that reads the row back.
  // Keeping actions in this plain object instead, keyed by row index, gives
  // a normal QML property whose reassignment *does* properly notify every
  // bound consumer, and the delegate reads it via a plain (non-required)
  // property binding instead.
  property var actionsByRow: ({})

  function setRowActions(rowIndex, actions) {
    var updated = {}
    for (var k in root.actionsByRow) updated[k] = root.actionsByRow[k]
    updated[String(rowIndex)] = actions
    root.actionsByRow = updated
  }

  property int assistantRowIndex: -1
  property string pendingBuffer: ""
  // Bounds a single reply's accumulated size - without this, a runaway or
  // malicious server could stream indefinitely and grow this row's content
  // (and, since the full history is resent every turn, every future
  // request too) without limit.
  property int maxAssistantContentChars: 200000
  property var activeBackendModule: null
  property var lastUsage: null

  function snapshotRows() {
    var rows = []
    for (var i = 0; i < conversation.count; i++) {
      var item = conversation.get(i)
      rows.push({ role: item.role, content: item.content, error: item.error })
    }
    return rows
  }

  // ------------------------------------------------------- session persistence
  //
  // Resumes the single ongoing conversation across shell restarts/reloads -
  // not a multi-session manager, just continuity. State (not settings, so it
  // doesn't belong in shell.json) lives in the standard XDG state dir via a
  // declarative FileView rather than the mktemp/curl-style Process chain used
  // for secrets above - there's no argv-visibility concern for plain
  // (non-secret) conversation text, so the simpler API is fine here.
  // Actions are deliberately NOT restored - they're tied to a live session's
  // execution state, and re-offering a stale, possibly-already-run action
  // after a restart would be confusing at best.

  property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/io.github.comapilot"
  // Capped so the file can't grow unbounded over months of daily use.
  property int maxPersistedMessages: 200
  // Restore-time bounds are deliberately separate from (and enforced
  // independently of) the save-time cap above - this file could in
  // principle be edited, corrupted, or replaced outside this plugin, so
  // restoring never trusts its size or shape at face value.
  property int maxSessionFileBytes: 5000000
  property int maxRestoredFieldChars: 200000

  Process {
    id: stateDirInitProc
    command: ["mkdir", "-p", root.stateDir]
  }

  FileView {
    id: sessionFile
    path: root.stateDir + "/conversation.json"
    preload: true
    printErrors: false
    // Atomic so a crash mid-write can never leave a half-written/corrupt
    // JSON file behind; chmod'd to owner-only on every successful save
    // (via onSaved below) since this holds real conversation content, not
    // meant to be world-readable by default file-creation permissions.
    atomicWrites: true
    onLoaded: root.restoreConversation()
    onLoadFailed: function(error) {} // FileNotFound is expected on first run
    onSaved: {
      chmodSessionFileProc.command = ["chmod", "600", sessionFile.path]
      chmodSessionFileProc.running = true
    }
  }

  Process { id: chmodSessionFileProc }

  function restoreConversation() {
    var raw = sessionFile.text()
    if (!raw) return
    if (raw.length > root.maxSessionFileBytes) {
      console.warn("cOMApilot: session file is " + raw.length + " bytes (over the " + root.maxSessionFileBytes + " byte limit) - refusing to restore it")
      return
    }
    var rows
    try { rows = JSON.parse(raw) } catch (e) { return }
    if (!Array.isArray(rows)) return
    // Keep only the most recent maxPersistedMessages regardless of how many
    // the file actually contains - the same cap persistConversation() saves
    // under, enforced again here since the file isn't trusted at face value.
    var startIdx = Math.max(0, rows.length - root.maxPersistedMessages)
    for (var i = startIdx; i < rows.length; i++) {
      var r = rows[i]
      if (!r || typeof r.role !== "string" || typeof r.content !== "string") continue
      var role = (r.role === "user" || r.role === "assistant") ? r.role : "assistant"
      var content = r.content.length > root.maxRestoredFieldChars ? r.content.slice(0, root.maxRestoredFieldChars) : r.content
      var errorText = typeof r.error === "string" ? r.error : ""
      if (errorText.length > root.maxRestoredFieldChars) errorText = errorText.slice(0, root.maxRestoredFieldChars)
      conversation.append({ role: role, content: content, streaming: false, error: errorText })
    }
    Qt.callLater(function() { conversationList.positionViewAtEnd() })
  }

  function persistConversation() {
    var rows = root.snapshotRows()
    if (rows.length > root.maxPersistedMessages) rows = rows.slice(rows.length - root.maxPersistedMessages)
    sessionFile.setText(JSON.stringify(rows))
  }

  function sendPrompt(text) {
    var trimmed = String(text || "").trim()
    if (!trimmed) return
    // A prompt sent while a previous reply is still streaming finalizes that
    // row as-is (whatever partial content it has) rather than losing it -
    // startRequest() below is what actually cancels the in-flight Process.
    if (root.assistantRowIndex !== -1) root.finishAssistantMessage()

    conversation.append({ role: "user", content: trimmed, streaming: false, error: "" })
    conversation.append({ role: "assistant", content: "", streaming: true, error: "" })
    root.assistantRowIndex = conversation.count - 1
    root.pendingBuffer = ""
    Qt.callLater(function() { conversationList.positionViewAtEnd() })
    root.startRequest()
  }

  function appendAssistantDelta(delta) {
    if (root.assistantRowIndex < 0 || root.assistantRowIndex >= conversation.count) return
    var row = conversation.get(root.assistantRowIndex)
    var next = row.content + delta
    if (next.length > root.maxAssistantContentChars) {
      // Truncate, finalize the row, and stop pulling more data we'd only
      // discard anyway - same cancel+suppress-restart pattern the Stop
      // button uses, so a cancelled-mid-cap stage's own delayed onExited
      // can't trigger a phantom re-send of the same prompt.
      conversation.setProperty(root.assistantRowIndex, "content",
        next.slice(0, root.maxAssistantContentChars) + "\n…[truncated - response exceeded the size limit]")
      conversationList.positionViewAtEnd()
      root.cancelInFlightRequest()
      root.suppressAutoStart = true
      root.finishAssistantMessage()
      return
    }
    conversation.setProperty(root.assistantRowIndex, "content", next)
    conversationList.positionViewAtEnd()
  }

  function finishAssistantMessage() {
    if (root.assistantRowIndex >= 0 && root.assistantRowIndex < conversation.count) {
      var idx = root.assistantRowIndex
      conversation.setProperty(idx, "streaming", false)
      // Parsed only when actionsEnabled is on - this is the master gate:
      // the model was never even told the action schema otherwise (see
      // buildOutgoingMessages()), and with actions never populated, no
      // card/Run-button/execution path can ever be reached regardless of
      // what a message's raw text happens to contain.
      if (root.settings.actionsEnabled) {
        var row = conversation.get(idx)
        var actions = ActionParser.extractActions(row.content, ActionAllowlist)
        for (var i = 0; i < actions.length; i++) actions[i].status = "pending"
        if (actions.length > 0) root.setRowActions(idx, actions)
      }
    }
    root.assistantRowIndex = -1
    root.pendingBuffer = ""
    root.persistConversation()
  }

  function finishAssistantError(message) {
    if (root.assistantRowIndex >= 0 && root.assistantRowIndex < conversation.count) {
      conversation.setProperty(root.assistantRowIndex, "streaming", false)
      conversation.setProperty(root.assistantRowIndex, "error", String(message || "Something went wrong."))
    }
    root.assistantRowIndex = -1
    root.pendingBuffer = ""
    root.persistConversation()
  }

  // ------------------------------------------------------- streaming request
  //
  // A single mktemp -> write body -> write curl config -> curl chain, reused
  // across turns rather than spawned fresh each time - same reasoning and
  // the same "wanted vs running" cancellation-race guard as OmaDeezer's
  // mktemp -> curl -> stat art-download chain (BarWidget.qml there): a
  // terminated Process still emits onExited, so only ever clearing
  // runningRequestId inside that handler itself keeps a cancelled chain's
  // late completion from being mistaken for the current one.
  //
  // The API key never appears in any Process.command (visible via
  // /proc/*/cmdline to any other process on the system) - both the request
  // body and every header (including Authorization/x-api-key) are written to
  // private scratch files via stdin, and curl only ever receives the config
  // file's path as an argument.

  property int wantedRequestId: 0
  property int runningRequestId: -1
  property string reqCacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/omarchy/io.github.comapilot/req"
  property bool reqCacheReady: false
  property string activeBasePath: ""
  property var sseState: ({})
  // A non-2xx response from a provider isn't SSE-shaped (it's a single
  // plain JSON error body), so no line of it ever matches a backend's
  // parseSseLine() and the stream would otherwise finish with no error and
  // no "done" - buffering the raw stdout alongside the SSE parse lets
  // curlProc.onExited recover a real message from it when --fail-with-body
  // reports a failure.
  property string rawStdoutBuffer: ""
  // A real provider error body is a small JSON object - way under this.
  // Capped so a long-running successful stream doesn't grow this buffer
  // for its entire duration for no reason (it's only ever read back on
  // failure); further bytes past the cap are simply not appended.
  property int maxRawStdoutBufferChars: 8192
  // Belt-and-suspenders against one absurdly long single SSE line arriving
  // before any of the size caps above would otherwise kick in.
  property int maxSseLineChars: 65536
  // Looked up fresh (not cached) on every send, so a key stored/changed in
  // SettingsPanel mid-session is picked up immediately with no extra wiring
  // - see the apiKeyLookupProc stage below.
  property string apiKeyForRequest: ""

  // Clipboard/active-window context, re-gathered fresh on every send (never
  // cached across turns) so the model only ever sees what's live *right now*
  // - see clipboardReadProc and buildOutgoingMessages() below. Neither is
  // ever appended to the visible `conversation` ListModel; both are folded
  // into a single untrusted-data message built fresh per request.
  property string clipboardContextText: ""

  function escapeCurlConfigValue(value) {
    return String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
  }

  // Lines are joined with \u0001 (a control character that can't appear
  // in a header value) rather than a real newline: this whole config gets
  // sent to its writer Process over stdin as a single `read -r` line (see
  // the comment on writeBodyProc/writeConfigProc below for why - QML's
  // Process has no way to close stdin, so a receiving `cat > file` blocks
  // on EOF forever). The receiving shell script converts \u0001 back to
  // real newlines with `tr` before writing the file.
  function buildCurlConfig(request) {
    var lines = []
    lines.push("url = \"" + root.escapeCurlConfigValue(request.url) + "\"")
    for (var i = 0; i < request.headers.length; i++) {
      var h = request.headers[i]
      lines.push("header = \"" + root.escapeCurlConfigValue(h[0] + ": " + h[1]) + "\"")
    }
    lines.push("data-binary = @" + root.activeBasePath + ".json")
    return lines.join("\u0001")
  }

  function stageFinished() {
    var forId = root.runningRequestId
    root.runningRequestId = -1
    return forId === root.wantedRequestId
  }

  // Takes one or more paths and removes them in a single rm invocation.
  // reqCleanupProc is one shared, reused Process instance - calling this
  // multiple times in a row within the same synchronous handler would
  // silently drop everything but the last call, since reassigning .command
  // before a just-started process has actually run just reconfigures the
  // same pending process rather than queuing a second one. Always batch
  // every path a caller needs removed into one call instead.
  function rmReqFiles(paths) {
    var existing = []
    for (var i = 0; i < paths.length; i++) if (paths[i]) existing.push(paths[i])
    if (existing.length === 0) return
    reqCleanupProc.command = ["rm", "-f", "--"].concat(existing)
    reqCleanupProc.running = true
  }

  Process { id: reqCleanupProc }

  // Wiped and recreated on every widget startup - files left by a prior,
  // possibly ungracefully-killed session never linger, and a pre-existing
  // symlink at this path can't redirect our writes elsewhere.
  Process {
    id: reqCacheInitProc
    command: ["sh", "-c", "rm -rf -- \"$0\" && mkdir -p -- \"$0\"", root.reqCacheDir]
    onExited: function(code) {
      root.reqCacheReady = true
      root.tryStartRequest()
    }
  }
  Component.onCompleted: {
    reqCacheInitProc.running = true
    stateDirInitProc.running = true
    for (var i = 0; i < root.visualSliderDefs.length; i++) root.relive(root.visualSliderDefs[i].key, root.visualSliderDefs[i].def)
    root.applyBlur()
    root.applyBlurLayerRule()
  }

  // Confirmed by direct testing, in this order: (1) setting `.running =
  // false` on an already-running Process does NOT terminate the underlying
  // OS process (a curl mid-SSE-stream was still alive 30+ seconds after
  // doing exactly that); (2) `.signal(15)` *also* silently fails to kill it
  // (confirmed via a debug log that the call really was reached with
  // `running == true`, yet the process lingered indefinitely); (3) a plain
  // `kill -15 <pid>` run from a normal shell against that exact same PID
  // killed it instantly. So neither QML-side API actually delivers the
  // signal on this Quickshell build - an external `kill` process using
  // `.processId` is what actually works. Multiple potentially-running PIDs
  // are batched into one `kill` call for the same reason rmReqFiles()
  // batches its `rm` calls above: reassigning .command on an
  // already-triggered shared Process before it's actually started just
  // reconfigures that pending run rather than queuing a second one.
  function cancelInFlightRequest() {
    root.wantedRequestId += 1
    var pids = []
    if (apiKeyLookupProc.running && apiKeyLookupProc.processId) pids.push(String(apiKeyLookupProc.processId))
    if (clipboardReadProc.running && clipboardReadProc.processId) pids.push(String(clipboardReadProc.processId))
    if (mktempProc.running && mktempProc.processId) pids.push(String(mktempProc.processId))
    if (writeBodyProc.running && writeBodyProc.processId) pids.push(String(writeBodyProc.processId))
    if (writeConfigProc.running && writeConfigProc.processId) pids.push(String(writeConfigProc.processId))
    if (curlProc.running && curlProc.processId) pids.push(String(curlProc.processId))
    if (pids.length > 0) {
      killHelperProc.command = ["kill", "-15"].concat(pids)
      killHelperProc.running = true
    }
  }

  Process { id: killHelperProc }

  // Set only by stopGenerating() below - distinguishes "the in-flight chain
  // was cancelled because a *new* prompt is about to replace it" (the normal
  // startRequest() path, where tryStartRequest() SHOULD immediately pick up
  // the new wantedRequestId) from "the user explicitly asked to stop, full
  // stop." Without this flag, a killed stage's own onExited still fires
  // (kill takes a moment) and its stageFinished() mismatch correctly detects
  // the cancellation, but its "not matched" cleanup path unconditionally
  // calls tryStartRequest() again - which, seeing the same still-pending
  // wantedRequestId and no other reason to refuse, would immediately start
  // a brand new request chain nobody asked for (confirmed by direct
  // testing: Stop killed the visible curl, then a *second*, different-PID
  // curl process appeared moments later for the exact same prompt, with
  // nowhere in the UI for its output to go since assistantRowIndex was
  // already -1 - a real, confirmed resource leak, not a hypothetical one).
  property bool suppressAutoStart: false

  function startRequest() {
    root.suppressAutoStart = false
    root.cancelInFlightRequest()
    root.tryStartRequest()
  }

  // Called from the input row's Stop button. Cancels whatever stage of the
  // chain is currently in flight and finalizes the row with whatever partial
  // content already streamed in - same outcome as a dropped connection.
  function stopGenerating() {
    if (root.assistantRowIndex === -1) return
    root.cancelInFlightRequest()
    root.suppressAutoStart = true
    root.finishAssistantMessage()
  }

  // Drops the last assistant reply (and any action cards on it) and re-asks
  // the same last user prompt. Only meaningful once a first exchange exists
  // and nothing is currently streaming.
  function regenerateLast() {
    if (root.assistantRowIndex !== -1) return
    if (conversation.count < 2) return
    var lastIdx = conversation.count - 1
    if (conversation.get(lastIdx).role !== "assistant") return
    if (conversation.get(lastIdx - 1).role !== "user") return
    conversation.remove(lastIdx)
    root.setRowActions(lastIdx, [])
    conversation.append({ role: "assistant", content: "", streaming: true, error: "" })
    root.assistantRowIndex = conversation.count - 1
    root.pendingBuffer = ""
    Qt.callLater(function() { conversationList.positionViewAtEnd() })
    root.startRequest()
  }

  function formatUsage(usage) {
    if (!usage) return ""
    var input = usage.prompt_tokens !== undefined ? usage.prompt_tokens : usage.input_tokens
    var output = usage.completion_tokens !== undefined ? usage.completion_tokens : usage.output_tokens
    var parts = []
    if (input !== undefined) parts.push(input + " in")
    if (output !== undefined) parts.push(output + " out")
    return parts.join(" · ")
  }

  // First stage of the chain: a fresh secret-tool lookup right before every
  // send (not a cached property) so a key stored/changed in SettingsPanel
  // mid-session is picked up on the very next prompt with no extra wiring.
  function tryStartRequest() {
    if (root.suppressAutoStart) return
    if (root.runningRequestId !== -1) return
    if (!root.reqCacheReady) return
    if (root.wantedRequestId === 0) return // nothing has ever been sent yet
    root.runningRequestId = root.wantedRequestId
    root.sseState = {}
    root.activeBackendModule = root.backendModule()
    apiKeyLookupProc.command = Secrets.lookupCommand(root.settings.backend || "openai-compatible")
    apiKeyLookupProc.running = true
  }

  Process {
    id: apiKeyLookupProc
    stdout: StdioCollector { id: apiKeyLookupOut; waitForEnd: true }
    onExited: function(code) {
      var key = String(apiKeyLookupOut.text || "").trim()
      if (!root.stageFinished()) { root.tryStartRequest(); return }
      root.apiKeyForRequest = key
      root.runningRequestId = root.wantedRequestId
      root.proceedToContext()
    }
  }

  // wl-paste (not Quickshell.clipboardText) - Quickshell's own docs note the
  // Wayland clipboard reads empty unless a quickshell window has keyboard
  // focus, which won't reliably be true here. wl-paste goes through the
  // wlr-data-control protocol instead, which mirrors the compositor
  // clipboard regardless of focus - the same reason Omarchy's own first-
  // party Clipboard.qml plugin shells out to wl-paste rather than using the
  // QML property.
  function proceedToContext() {
    root.clipboardContextText = ""
    if (root.settings.includeClipboardContext) {
      clipboardReadProc.command = ["wl-paste", "--no-newline", "--type", "text"]
      clipboardReadProc.running = true
    } else {
      root.proceedToMktemp()
    }
  }

  Process {
    id: clipboardReadProc
    stdout: StdioCollector { id: clipboardReadOut; waitForEnd: true }
    onExited: function(code) {
      if (!root.stageFinished()) { root.tryStartRequest(); return }
      root.runningRequestId = root.wantedRequestId
      // A non-zero exit just means no text is on the clipboard right now
      // (e.g. an image is copied instead) - not an error worth surfacing.
      root.clipboardContextText = code === 0 ? String(clipboardReadOut.text || "") : ""
      root.proceedToMktemp()
    }
  }

  function proceedToMktemp() {
    mktempProc.command = ["mktemp", root.reqCacheDir + "/req-XXXXXX"]
    mktempProc.running = true
  }

  // Builds the array of {role, content} messages sent to the backend for
  // this one request: the real conversation history plus, if enabled, one
  // extra leading message carrying clipboard/active-window context. That
  // context message is built fresh every call from current live state -
  // it's never appended to the persisted `conversation` ListModel, so past
  // turns never carry stale/resent context forward.
  function buildOutgoingMessages() {
    var messages = ConversationModel.toApiMessages(root.snapshotRows())
    var parts = []
    if (root.settings.includeClipboardContext) {
      var clip = ContextSanitizer.formatClipboardPart(root.clipboardContextText)
      if (clip) parts.push(clip)
    }
    if (root.settings.includeActiveWindowContext) {
      var toplevel = ToplevelManager.activeToplevel
      var win = ContextSanitizer.formatWindowPart(toplevel ? toplevel.title : "", toplevel ? toplevel.appId : "")
      if (win) parts.push(win)
    }
    var contextMessage = ContextSanitizer.buildContextMessage(parts, root.settings.maxContextChars || 4000)
    if (contextMessage) messages = [contextMessage].concat(messages)
    // Action instructions are trusted (built by us, not user/desktop data),
    // so they lead ahead of the untrusted context message - only sent at
    // all when actionsEnabled is on.
    if (root.settings.actionsEnabled) {
      messages = [{ role: "user", content: ActionAllowlist.buildActionPromptText() }].concat(messages)
    }
    return messages
  }

  Process {
    id: mktempProc
    stdout: StdioCollector { id: mktempOut; waitForEnd: true }
    onExited: function(code) {
      var path = String(mktempOut.text || "").trim()
      if (!root.stageFinished()) { root.rmReqFiles([path]); root.tryStartRequest(); return }
      if (code !== 0 || !path) { root.finishAssistantError("Could not prepare a temp file for the request."); return }
      root.activeBasePath = path
      root.runningRequestId = root.wantedRequestId

      var request = root.activeBackendModule.buildRequest(root.settings, root.apiKeyForRequest, root.buildOutgoingMessages())
      if (request.error) {
        // e.g. a keyed request whose endpoint isn't https:// - fail closed
        // before anything is written to disk or sent anywhere. The mktemp
        // file itself still needs cleaning up since it already exists.
        root.rmReqFiles([root.activeBasePath])
        root.finishAssistantError(request.error)
        return
      }
      // JSON.stringify's compact output never contains a raw newline byte
      // (any newline inside a string value comes out as the two characters
      // \n, escaped) so it's always exactly one line - safe to send as a
      // single `read -r` line. `read -r` (not `cat`) is what makes this
      // work at all without an EOF: QML's Process.write() has no way to
      // close stdin, so a receiving `cat > file` would block forever
      // waiting for one; `read -r` only needs the newline we append below.
      writeBodyProc.pendingContent = request.bodyJson
      writeBodyProc.pendingRequest = request
      writeBodyProc.command = ["sh", "-c", "IFS= read -r line && printf '%s' \"$line\" > \"$0\"", path + ".json"]
      writeBodyProc.running = true
    }
  }

  Process {
    id: writeBodyProc
    property string pendingContent: ""
    property var pendingRequest: null
    stdinEnabled: true
    onStarted: { write(pendingContent + "\n"); pendingContent = "" }
    onExited: function(code) {
      if (!root.stageFinished()) { root.rmReqFiles([root.activeBasePath + ".json"]); root.tryStartRequest(); return }
      if (code !== 0) { root.finishAssistantError("Could not write the request body."); return }
      root.runningRequestId = root.wantedRequestId

      var cfgText = root.buildCurlConfig(pendingRequest)
      writeConfigProc.pendingContent = cfgText
      // Single control-character-joined line in, real newlines restored
      // via tr on the way to disk - see buildCurlConfig()'s comment for why.
      writeConfigProc.command = ["sh", "-c", "IFS= read -r line && printf '%s' \"$line\" | tr '\\001' '\\n' > \"$0\"", root.activeBasePath + ".cfg"]
      writeConfigProc.running = true
    }
  }

  Process {
    id: writeConfigProc
    property string pendingContent: ""
    stdinEnabled: true
    onStarted: { write(pendingContent + "\n"); pendingContent = "" }
    onExited: function(code) {
      if (!root.stageFinished()) {
        root.rmReqFiles([root.activeBasePath + ".json", root.activeBasePath + ".cfg"])
        root.tryStartRequest()
        return
      }
      if (code !== 0) { root.finishAssistantError("Could not write the request config."); return }
      root.runningRequestId = root.wantedRequestId
      root.rawStdoutBuffer = ""
      // --fail-with-body: a non-2xx response is still a plain JSON error
      // body (not SSE), so it must still reach stdout to be parseable -
      // plain --fail would suppress it entirely - while making curl exit
      // non-zero so onExited's failure path actually fires instead of the
      // stream quietly "finishing" with no delta and no done.
      curlProc.command = ["curl", "-N", "-sS", "--fail-with-body", "--max-time", "120", "-K", root.activeBasePath + ".cfg"]
      curlProc.running = true
    }
  }

  Process {
    id: curlProc
    stdout: SplitParser {
      onRead: function(line) {
        if (root.runningRequestId !== root.wantedRequestId) return
        if (line.length > root.maxSseLineChars) line = line.slice(0, root.maxSseLineChars)
        if (root.rawStdoutBuffer.length < root.maxRawStdoutBufferChars) root.rawStdoutBuffer += line + "\n"
        root.handleSseLine(line)
      }
    }
    stderr: StdioCollector { id: curlErr; waitForEnd: true }
    onExited: function(code) {
      root.rmReqFiles([root.activeBasePath, root.activeBasePath + ".json", root.activeBasePath + ".cfg"])
      var matched = root.stageFinished()
      if (!matched) { root.tryStartRequest(); return }
      if (root.assistantRowIndex >= 0) {
        var row = conversation.get(root.assistantRowIndex)
        if (row.streaming) {
          if (code !== 0) {
            root.finishAssistantError(root.describeRequestFailure(code, root.rawStdoutBuffer, String(curlErr.text || "").trim()))
          } else {
            // curl exited cleanly (HTTP transport succeeded) but no `done`
            // SSE event ever arrived - the connection ended before the
            // provider finished (e.g. it crashed or was killed mid-stream).
            // Whatever partial text arrived stays; just stop the spinner
            // rather than leaving it stuck forever with no way to tell.
            root.finishAssistantMessage()
          }
        }
      }
    }
  }

  // curl exit 22 (--fail-with-body) means the HTTP status was an error; the
  // body is still a plain JSON error object (not SSE), so try to pull a
  // real provider message out of it before falling back to raw text/stderr.
  function describeRequestFailure(code, stdoutBuffer, stderrDetail) {
    var trimmed = String(stdoutBuffer || "").trim()
    if (trimmed) {
      try {
        var obj = JSON.parse(trimmed)
        var msg = obj && obj.error && (obj.error.message || obj.error.type)
        if (msg) return String(msg)
      } catch (e) {
        // not JSON - fall through to raw text below
      }
      if (trimmed.length <= 300) return trimmed
    }
    if (stderrDetail) return stderrDetail
    return "Request failed (exit " + code + "). Check your connection, endpoint, and API key."
  }

  // ---------------------------------------------------------- action model
  //
  // Every action a completed message can carry was already validated
  // fail-closed by ActionParser.js against the fixed ActionAllowlist.js
  // tables before it ever became a card (see finishAssistantMessage()
  // above) - nothing here re-checks that, this is purely the
  // confirm-then-execute plumbing for actions already known-safe to run
  // *if* the user clicks Run.

  property int pendingConfirmRowIndex: -1
  property int pendingConfirmActionIndex: -1

  function requestActionConfirm(rowIndex, actionIndex) {
    var action = (root.actionsByRow[String(rowIndex)] || [])[actionIndex]
    if (!action || action.status !== "pending") return
    root.pendingConfirmRowIndex = rowIndex
    root.pendingConfirmActionIndex = actionIndex
    confirmDialog.message = action.label
    confirmDialog.confirmText = "Run"
    confirmDialog.cancelText = "Cancel"
    confirmDialog.selectedIndex = 0
    confirmDialog.opened = true
  }

  // Launched via startDetached() rather than the tracked running=true/
  // onExited pattern used for the streaming request above - confirmed by
  // direct testing that several of these commands (opening a browser via
  // xdg-open, a terminal, an interactive screenshot region-picker) don't
  // return until the launched app itself exits, which for a browser can be
  // arbitrarily long. Tracking exit status would leave a card stuck on
  // "Running…" for as long as that app stays open. startDetached() spawns
  // and immediately forgets the child instead - accurate to what we can
  // actually promise the user ("this was launched"), not a claim about
  // whether it succeeded. Since it's a synchronous, immediate spawn (not
  // queued), reusing one Process instance across confirmations needs no
  // queue/race-guard the way the tracked pattern above does.
  function executeConfirmedAction() {
    var rowIndex = root.pendingConfirmRowIndex
    var actionIndex = root.pendingConfirmActionIndex
    root.pendingConfirmRowIndex = -1
    root.pendingConfirmActionIndex = -1
    var action = (root.actionsByRow[String(rowIndex)] || [])[actionIndex]
    if (!action || action.status !== "pending") return
    actionExecProc.command = action.command
    actionExecProc.startDetached()
    root.markActionStatus(rowIndex, actionIndex, "launched")
  }

  function markActionStatus(rowIndex, actionIndex, status) {
    var actions = (root.actionsByRow[String(rowIndex)] || []).slice()
    if (actionIndex < 0 || actionIndex >= actions.length) return
    var updated = {}
    for (var k in actions[actionIndex]) updated[k] = actions[actionIndex][k]
    updated.status = status
    actions[actionIndex] = updated
    root.setRowActions(rowIndex, actions)
  }

  Process { id: actionExecProc }

  function handleSseLine(line) {
    var mod = root.activeBackendModule || root.backendModule()
    var result = mod.parseSseLine(line, root.sseState)
    if (!result) return
    if (result.error) { root.finishAssistantError(result.error); return }
    if (result.delta) {
      if (root.settings.streaming === false) {
        // Same cap as appendAssistantDelta() below - simply stop growing
        // past it here too, rather than accumulate content that would only
        // be truncated at flush time anyway.
        if (root.pendingBuffer.length < root.maxAssistantContentChars) root.pendingBuffer += result.delta
      } else {
        root.appendAssistantDelta(result.delta)
      }
    }
    if (result.usage) root.lastUsage = result.usage
    if (result.done) {
      if (root.settings.streaming === false && root.pendingBuffer) {
        root.appendAssistantDelta(root.pendingBuffer)
      }
      root.finishAssistantMessage()
    }
  }

  // Split into two layer-shell surfaces rather than one full-screen one,
  // specifically so the Blur slider's layer rule (which targets this
  // surface's namespace, "comapilot" - see applyBlurLayerRule() above)
  // only blurs behind the small card, not the whole screen. Confirmed by
  // direct testing that a single full-screen surface with blur enabled
  // blurs everything behind it, since Hyprland blur is a per-surface
  // effect applied across a surface's entire geometry - there's no way to
  // scope it to just part of one surface. No first-party Omarchy overlay
  // uses this two-surface pattern (every one of them is a single
  // full-screen PanelWindow with the card centered as a plain child Item),
  // so this is a deliberate departure from that convention for this one
  // reason.
  PanelWindow {
    id: scrimWindow
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "comapilot-scrim"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    implicitWidth: root.cardWidth
    implicitHeight: root.cardHeight
    color: "transparent"
    // Deliberately no anchors on any edge - per the wlr-layer-shell
    // protocol, a surface with neither edge of an axis anchored centers on
    // that axis (confirmed against Quickshell's own PanelWindow/
    // WlrLayershell qmltypes: neither exposes an x/y or centerIn concept at
    // all - positioning is anchor+margin only, so this is the only way to
    // center a fixed-size layer-shell surface).
    WlrLayershell.namespace: "comapilot"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    BorderSurface {
      id: card
      anchors.fill: parent
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (confirmDialog.opened) {
            if (confirmDialog.handleKey(event)) event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
          }
        }

        Column {
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          spacing: root.contentSpacing

          Item {
            width: parent.width
            height: Style.font.heading + Style.spacing.sm

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "cOMApilot"
              color: root.accentColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }

            Button {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: String.fromCodePoint(0xF0493)
              tooltipText: root.settingsOpen ? "Back" : "Settings"
              foreground: root.foreground
              accent: root.accentColor
              selected: root.settingsOpen
              onClicked: root.settingsOpen = !root.settingsOpen
            }
          }

          Item {
            width: parent.width
            height: parent.height - Style.font.heading - Style.spacing.sm - root.contentSpacing

            // The settings panel outgrew a single fixed-height card once the
            // visual sliders were added at the bottom - wrapped in a
            // Flickable so it scrolls (mouse wheel/drag) instead of silently
            // overflowing past the card's edge.
            Flickable {
              id: settingsScroll
              anchors.fill: parent
              visible: root.settingsOpen
              clip: true
              contentWidth: width
              contentHeight: settingsPanel.implicitHeight
              boundsBehavior: Flickable.StopAtBounds

              SettingsPanel {
                id: settingsPanel
                width: settingsScroll.width
                settings: root.settings
                foreground: root.foreground
                accentColor: root.accentColor
                fontFamily: root.fontFamily
                onChanged: function(key, value) { root.persistSetting(key, value) }
                onSliderLive: function(key, value) { root[root.liveKeyFor(key)] = value }
                onSliderReleased: function(key, value) {
                  root.persistSetting(key, value)
                  root.relive(key, root.visualDefaultFor(key))
                }
                onResetVisualRequested: root.resetVisualDefaults()
              }
            }

            Column {
              anchors.fill: parent
              visible: !root.settingsOpen
              spacing: root.contentSpacing

              ListView {
                id: conversationList
                width: parent.width
                height: parent.height - inputRow.height - root.contentSpacing -
                  (contextIndicator.visible ? contextIndicator.height + root.contentSpacing : 0) -
                  (usageIndicator.visible ? usageIndicator.height + root.contentSpacing : 0)
                clip: true
                model: conversation
                spacing: Style.spacing.md
                boundsBehavior: Flickable.StopAtBounds

                delegate: Column {
                  id: bubble
                  required property int index
                  required property string role
                  required property string content
                  required property bool streaming
                  required property string error
                  // Plain (non-required) binding, not a ListModel role -
                  // see the comment on root.actionsByRow above for why.
                  property var actions: root.actionsByRow[String(index)] || []

                  width: conversationList.width
                  spacing: Style.spacing.xs / 2

                  Text {
                    text: bubble.role === "user" ? "You" : "cOMApilot"
                    anchors.right: bubble.role === "user" ? parent.right : undefined
                    anchors.left: bubble.role === "user" ? undefined : parent.left
                    color: root.foreground
                    opacity: 0.55
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    width: bubble.width
                    height: bubbleCard.height

                    BorderSurface {
                      id: bubbleCard
                      anchors.right: bubble.role === "user" ? parent.right : undefined
                      anchors.left: bubble.role === "user" ? undefined : parent.left
                      width: Math.min(bubble.width * 0.82, Style.space(560))
                      height: contentText.implicitHeight + Style.spacing.sm * 2
                      radius: root.cornerRadius
                      color: bubble.role === "user" ? Util.alpha(root.accentColor, 0.24) : Util.alpha(root.foreground, 0.06)
                      borderSpec: Border.flat(bubble.role === "user" ? root.accentColor : Util.alpha(root.foreground, 0.18), Math.max(1, Style.space(1)))

                      Text {
                        id: contentText
                        anchors.fill: parent
                        anchors.margins: Style.spacing.sm
                        // Markdown only for the assistant - a user's own
                        // typed prompt is rendered as plain text, matching
                        // what they actually typed rather than reinterpreting
                        // any stray */_/# characters as formatting.
                        textFormat: bubble.role === "assistant" ? Text.MarkdownText : Text.PlainText
                        text: bubble.content + (bubble.streaming ? " ▍" : "")
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        wrapMode: Text.WordWrap
                      }
                    }
                  }

                  Text {
                    visible: bubble.error.length > 0
                    width: bubble.width
                    textFormat: Text.PlainText
                    text: bubble.error
                    color: Color.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                  }

                  Button {
                    text: "Regenerate"
                    bordered: true
                    foreground: root.foreground
                    accent: root.accentColor
                    visible: !bubble.streaming && bubble.role === "assistant"
                      && bubble.index === conversation.count - 1 && root.assistantRowIndex === -1
                    onClicked: root.regenerateLast()
                  }

                  Column {
                    width: bubble.width
                    spacing: Style.spacing.xs
                    visible: bubble.actions && bubble.actions.length > 0

                    Repeater {
                      model: bubble.actions || []

                      BorderSurface {
                        id: actionCard
                        required property var modelData
                        required property int index

                        width: bubble.width
                        height: actionColumn.implicitHeight + Style.spacing.sm * 2
                        radius: root.cornerRadius
                        color: root.background
                        borderSpec: Border.flat(root.foreground, Math.max(1, Style.space(1)))

                        Column {
                          id: actionColumn
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.top: parent.top
                          anchors.margins: Style.spacing.sm
                          spacing: Style.spacing.xs

                          Text {
                            width: parent.width
                            // The label is built from model-controlled
                            // strings (a target/pluginId/method/args the
                            // assistant proposed) - forced PlainText so
                            // Qt's default AutoText can never reinterpret
                            // it as rich text (same class of risk, same
                            // fix, as OmaDeezer's MPRIS-derived text).
                            textFormat: Text.PlainText
                            text: actionCard.modelData.label
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.WordWrap
                          }

                          Row {
                            spacing: Style.spacing.sm

                            Button {
                              text: "Run"
                              bordered: true
                              visible: actionCard.modelData.status === "pending"
                              foreground: root.foreground
                              accent: root.accentColor
                              onClicked: root.requestActionConfirm(bubble.index, actionCard.index)
                            }

                            Text {
                              visible: actionCard.modelData.status === "launched"
                              text: "Launched"
                              color: root.foreground
                              opacity: 0.7
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              anchors.verticalCenter: parent.verticalCenter
                            }
                          }
                        }
                      }
                    }
                  }
                }

                Text {
                  visible: conversation.count === 0
                  anchors.centerIn: parent
                  text: "Ask me anything…"
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                }
              }

              Text {
                id: contextIndicator
                width: parent.width
                visible: root.settings.includeClipboardContext || root.settings.includeActiveWindowContext
                text: "Context: " + [
                  root.settings.includeClipboardContext ? "clipboard ✓" : null,
                  root.settings.includeActiveWindowContext ? "active window ✓" : null
                ].filter(function(x) { return !!x }).join("  ·  ")
                color: root.foreground
                opacity: 0.55
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                id: usageIndicator
                width: parent.width
                visible: root.lastUsage !== null
                text: root.formatUsage(root.lastUsage) + " tokens (last reply)"
                horizontalAlignment: Text.AlignRight
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Row {
                id: inputRow
                width: parent.width
                height: promptField.implicitHeight
                spacing: Style.spacing.sm

                TextField {
                  id: promptField
                  width: parent.width - sendButton.width - Style.spacing.sm
                  placeholderText: "Ask me anything…"
                  foreground: root.foreground
                  accent: root.accentColor
                  font.family: root.fontFamily
                  onAccepted: {
                    root.sendPrompt(text)
                    text = ""
                  }
                }

                Button {
                  id: sendButton
                  text: root.assistantRowIndex !== -1 ? "Stop" : "Send"
                  bordered: true
                  foreground: root.foreground
                  accent: root.accentColor
                  onClicked: {
                    if (root.assistantRowIndex !== -1) {
                      root.stopGenerating()
                    } else {
                      root.sendPrompt(promptField.text)
                      promptField.text = ""
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    ConfirmDialog {
      id: confirmDialog
      anchors.fill: parent
      foreground: root.foreground
      background: root.background
      fontFamily: root.fontFamily
      cornerRadius: root.cornerRadius
      onConfirmed: {
        confirmDialog.opened = false
        root.executeConfirmedAction()
      }
      onCanceled: {
        confirmDialog.opened = false
        root.pendingConfirmRowIndex = -1
        root.pendingConfirmActionIndex = -1
      }
    }
  }
}
