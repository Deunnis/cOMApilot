// Pure-JS helpers for storing/looking up/clearing the per-backend API key via
// secret-tool (libsecret CLI). No QML Process type can be instantiated from a
// plain .js module, so these functions only build argv/scripts and parse
// output - the actual Process elements live in Copilot.qml.

var SERVICE = "io.github.comapilot"

function secretKey(backend) {
  return "api-key-" + String(backend || "")
}

// secret-tool store reads the secret from stdin until EOF, but QML's Process
// exposes write() with no way to close stdin/signal EOF from the caller side.
// Wrapping in a small bash script sidesteps that: `read -r` only needs the
// newline we already write, and its own internal pipe into secret-tool
// naturally EOFs when printf finishes - so the parent Process's stdin never
// needs to be closed at all.
function storeCommand(backend) {
  var script = 'IFS= read -r secret && printf \'%s\' "$secret" | ' +
    'secret-tool store --label="cOMApilot API key ($1)" service "$2" key "$3"'
  return ["bash", "-c", script, "omacopilot-store-secret", backend, SERVICE, secretKey(backend)]
}

function lookupCommand(backend) {
  return ["secret-tool", "lookup", "service", SERVICE, "key", secretKey(backend)]
}

function clearCommand(backend) {
  return ["secret-tool", "clear", "service", SERVICE, "key", secretKey(backend)]
}

var Secrets = {
  storeCommand: storeCommand,
  lookupCommand: lookupCommand,
  clearCommand: clearCommand
}
