// Extracts and validates ```action fenced JSON blocks from a completed
// assistant message. Fail-closed throughout: a JSON.parse failure, a
// non-array payload, an unknown type, or any type-specific validation
// failure silently drops just that one action (console.warn only) - never
// a partial or guessed interpretation. The allowlist tables themselves
// (ActionAllowlist.js) are passed in rather than imported here, so this
// module stays a plain, dependency-free transform like ConversationModel.js
// and ContextSanitizer.js.

var NAMED_ACTION_LABELS = {
  "lock-screen": "Lock the screen",
  "take-screenshot": "Take a screenshot",
  "open-terminal": "Open a terminal",
  "open-app-menu": "Open the app menu"
}

// Labels are built from model-controlled strings and flow into two Text
// consumers: our own action-card label (forced Text.PlainText in
// Copilot.qml) and the reused first-party ConfirmDialog's message Text,
// which we don't own and which defaults to Text.AutoText - Qt's automatic
// rich-text detection would kick in if the string looks like it contains
// markup. Stripping angle brackets at the source, once, covers both
// consumers - the same fix OmaDeezer already needed for MPRIS-derived text
// reaching a tooltip it didn't control either.
function stripAngleBrackets(s) {
  return String(s).replace(/[<>]/g, "")
}

function isFlatPrimitiveArgs(args) {
  if (args === undefined || args === null) return true
  if (typeof args !== "object" || Array.isArray(args)) return false
  for (var key in args) {
    var value = args[key]
    if (value !== null && typeof value !== "string" && typeof value !== "number" && typeof value !== "boolean") return false
  }
  return true
}

// target must look like either an https:// URL or an absolute local path
// (~/... or /...). Deliberately does *not* stat the filesystem to confirm
// the local path really exists - this module is a synchronous pure
// transform with no Process access, and a nonexistent target is a harmless
// no-op for xdg-open (not a security boundary), so that check is left to
// the OS at execute time rather than duplicated here.
function validateOpenPath(raw) {
  var target = raw.target
  if (typeof target !== "string" || target.length === 0) return null
  var isHttps = /^https:\/\//.test(target)
  var isLocalPath = /^(~\/|\/)/.test(target)
  if (!isHttps && !isLocalPath) return null
  return {
    type: "open_path",
    label: "Open: " + stripAngleBrackets(target),
    command: ["xdg-open", target]
  }
}

function validateRunNamedAction(raw, allowlist) {
  var name = raw.name
  if (typeof name !== "string" || !allowlist.isRunNamedActionAllowed(name)) return null
  var command = allowlist.commandForNamedAction(name)
  if (!command) return null
  return {
    type: "run_named_action",
    label: NAMED_ACTION_LABELS[name] || ("Run: " + stripAngleBrackets(name)),
    command: command
  }
}

function validatePluginIpcCall(raw, allowlist) {
  var pluginId = raw.pluginId
  var method = raw.method
  var args = raw.args
  if (typeof pluginId !== "string" || typeof method !== "string") return null
  if (!allowlist.isPluginIpcCallAllowed(pluginId, method)) return null
  if (!isFlatPrimitiveArgs(args)) return null
  var argsJson = JSON.stringify(args || {})
  return {
    type: "plugin_ipc_call",
    label: "Call " + stripAngleBrackets(pluginId) + "." + stripAngleBrackets(method) +
      (args ? " with " + stripAngleBrackets(argsJson) : ""),
    command: ["omarchy-shell", "shell", "call", pluginId, method, argsJson]
  }
}

function validateOne(raw, allowlist) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null
  if (raw.type === "open_path") return validateOpenPath(raw)
  if (raw.type === "run_named_action") return validateRunNamedAction(raw, allowlist)
  if (raw.type === "plugin_ipc_call") return validatePluginIpcCall(raw, allowlist)
  return null
}

// Fires once per completed assistant message (never mid-stream). Returns a
// flat array of validated {type, label, command} objects ready for the
// confirm-then-execute UI - every returned entry is something safe to run
// once the user explicitly confirms it, nothing more.
function extractActions(text, allowlist) {
  var out = []
  var fenceRe = /```action\s*\n([\s\S]*?)```/g
  var match
  while ((match = fenceRe.exec(String(text || ""))) !== null) {
    var parsed
    try {
      parsed = JSON.parse(match[1])
    } catch (e) {
      console.warn("ActionParser: malformed JSON in action block, dropping:", e)
      continue
    }
    if (!Array.isArray(parsed)) {
      console.warn("ActionParser: action block is not a JSON array, dropping")
      continue
    }
    for (var i = 0; i < parsed.length; i++) {
      var validated = validateOne(parsed[i], allowlist)
      if (validated) out.push(validated)
      else console.warn("ActionParser: dropped invalid/disallowed action:", JSON.stringify(parsed[i]))
    }
  }
  return out
}

var ActionParser = {
  extractActions: extractActions
}
