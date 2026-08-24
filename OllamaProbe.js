// Local-Ollama detection for the settings panel. Probed on panel open (not
// per-keystroke) via a short-timeout curl against Ollama's own native
// /api/tags endpoint - kept separate from the chat request path, which
// still goes through OpenAiCompatBackend.js against Ollama's OpenAI-
// compatible /v1/chat/completions endpoint unchanged.

var OLLAMA_ENDPOINT_URL = "http://localhost:11434/v1/chat/completions"

function probeCommand() {
  return ["curl", "-fsS", "--max-time", "2", "http://localhost:11434/api/tags"]
}

function parseModelNames(jsonText) {
  try {
    var obj = JSON.parse(jsonText)
    var models = obj && obj.models
    if (!Array.isArray(models)) return []
    var names = []
    for (var i = 0; i < models.length; i++) {
      if (models[i] && typeof models[i].name === "string") names.push(models[i].name)
    }
    return names
  } catch (e) {
    return []
  }
}

var OllamaProbe = {
  OLLAMA_ENDPOINT_URL: OLLAMA_ENDPOINT_URL,
  probeCommand: probeCommand,
  parseModelNames: parseModelNames
}
