// Fixed, closed table of everything the model is ever allowed to trigger.
// Not model-editable at runtime, not user-editable from the UI in v1 - a
// hand-editable module, same tradeoff the plan documents. Every entry maps
// to exactly one concrete command with zero model-controlled arguments
// beyond what each action type's own validation (see ActionParser.js)
// explicitly allows.

// name -> argv. Confirmed real on this machine before being listed here.
var RUN_NAMED_ACTIONS = {
  "lock-screen": ["/usr/share/omarchy/bin/omarchy-system-lock"],
  "take-screenshot": ["/usr/share/omarchy/bin/omarchy-capture-screenshot"],
  "open-terminal": ["xdg-terminal-exec"],
  "open-app-menu": ["omarchy-shell", "shell", "toggle", "omarchy.menu", "{\"menu\":\"apps\"}"]
}

// pluginId -> allowed method names. A "method" here is a function invoked
// directly on that plugin's loaded instance via `omarchy-shell shell call
// <pluginId> <method> <argsJson>` - the same call convention this plugin's
// own open()/close()/toggle()/sendPrompt() are driven by during headless
// testing (see the plugin's own memory notes on `shell call`). Deliberately
// never the bare `toggle`/`summon` shell-level verbs - every entry here
// names one specific instance method, not "any state change on this id."
var PLUGIN_IPC_ALLOWLIST = {
  "omarchy.clipboard": ["toggle", "open", "close"],
  "omarchy.network": ["toggle", "toggleNetwork"],
  "omarchy.menu": ["toggle"]
}

function isRunNamedActionAllowed(name) {
  return Object.prototype.hasOwnProperty.call(RUN_NAMED_ACTIONS, name)
}

function commandForNamedAction(name) {
  var command = RUN_NAMED_ACTIONS[name]
  return command ? command.slice() : null
}

function isPluginIpcCallAllowed(pluginId, method) {
  var methods = PLUGIN_IPC_ALLOWLIST[pluginId]
  return !!methods && methods.indexOf(method) !== -1
}

// Inlined into the outgoing prompt only when actionsEnabled is on (see
// Copilot.qml's buildOutgoingMessages()). Built from the tables above
// rather than hand-duplicated, so the instructions the model sees can
// never drift from what's actually enforced.
function buildActionPromptText() {
  var namedList = Object.keys(RUN_NAMED_ACTIONS).join(", ")
  var pluginLines = []
  for (var pluginId in PLUGIN_IPC_ALLOWLIST) {
    pluginLines.push(pluginId + " (" + PLUGIN_IPC_ALLOWLIST[pluginId].join(", ") + ")")
  }
  return "You may optionally propose actions for the user to run. Only propose one when it's " +
    "clearly useful, and only using the exact schema below - never invent a new type, field, " +
    "plugin id, or method name.\n\n" +
    "To propose actions, include exactly one fenced block like this in your reply:\n" +
    "```action\n" +
    "[{ \"type\": \"open_path\", \"target\": \"https://example.com\" }]\n" +
    "```\n" +
    "containing a JSON array of one or more of these:\n" +
    "- { \"type\": \"open_path\", \"target\": \"<an https:// URL or an absolute local path>\" }\n" +
    "- { \"type\": \"run_named_action\", \"name\": \"<one of: " + namedList + ">\" }\n" +
    "- { \"type\": \"plugin_ipc_call\", \"pluginId\": \"<allowed id>\", \"method\": \"<allowed method>\", \"args\": {} }\n" +
    "  Allowed pluginId/method pairs: " + pluginLines.join("; ") + "\n\n" +
    "The user must explicitly confirm every action before it runs, and you will never see the " +
    "result in this conversation. Never include the action block unless you're actually " +
    "proposing something to run - plain replies don't need one."
}

var ActionAllowlist = {
  RUN_NAMED_ACTIONS: RUN_NAMED_ACTIONS,
  PLUGIN_IPC_ALLOWLIST: PLUGIN_IPC_ALLOWLIST,
  isRunNamedActionAllowed: isRunNamedActionAllowed,
  commandForNamedAction: commandForNamedAction,
  isPluginIpcCallAllowed: isPluginIpcCallAllowed,
  buildActionPromptText: buildActionPromptText
}
