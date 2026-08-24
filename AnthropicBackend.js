// Anthropic Messages API streaming backend. SSE here is two-line-paired
// ("event: <type>" then "data: {...}") rather than OpenAI's single
// "data: {...}" line, so parseSseLine threads a small bit of state through
// (state.currentEvent) to know which event type the next data line belongs
// to - the event name and its payload arrive as separate lines.

var ANTHROPIC_VERSION = "2023-06-01"

function buildRequest(settings, apiKey, messages) {
  var headers = [
    ["Content-Type", "application/json"],
    ["anthropic-version", ANTHROPIC_VERSION]
  ]
  if (apiKey) headers.push(["x-api-key", apiKey])
  return {
    url: "https://api.anthropic.com/v1/messages",
    headers: headers,
    bodyJson: JSON.stringify({
      model: settings.model,
      max_tokens: 4096,
      stream: true,
      messages: messages
    })
  }
}

// See the comment in OpenAiCompatBackend.js's parseSseLine for why trim()
// here isn't just cosmetic - Quickshell's SplitParser leaves a leading "\n"
// on every SSE chunk after the first (from the blank line separating
// events), which would otherwise break every one of these indexOf checks.
function parseSseLine(rawLine, state) {
  var line = String(rawLine || "").trim()
  if (line.indexOf("event:") === 0) {
    state.currentEvent = line.slice(6).trim()
    return null
  }
  if (line.indexOf("data:") !== 0) return null
  var payload = line.slice(5).trim()
  if (!payload) return null
  var obj
  try {
    obj = JSON.parse(payload)
  } catch (e) {
    return null
  }

  if (state.currentEvent === "error" || obj.type === "error") {
    var err = obj.error || obj
    return { error: (err && err.message) || JSON.stringify(obj) }
  }
  if (state.currentEvent === "message_stop") return { done: true }
  if (state.currentEvent === "content_block_delta") {
    var delta = obj.delta
    if (delta && delta.type === "text_delta" && typeof delta.text === "string") {
      return { delta: delta.text }
    }
    return null
  }
  if (state.currentEvent === "message_delta" && obj.usage) {
    return { usage: obj.usage }
  }
  return null
}

var AnthropicBackend = {
  buildRequest: buildRequest,
  parseSseLine: parseSseLine
}
