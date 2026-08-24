// OpenAI-compatible chat/completions streaming backend. Covers OpenAI
// itself, OpenRouter, and any OpenAI-wire-compatible server (Ollama's own
// /v1/chat/completions endpoint reuses this module unchanged - only
// endpointUrl/auth differ, both handled by settings).

function buildRequest(settings, apiKey, messages) {
  var headers = [["Content-Type", "application/json"]]
  if (apiKey) headers.push(["Authorization", "Bearer " + apiKey])
  return {
    url: settings.endpointUrl,
    headers: headers,
    bodyJson: JSON.stringify({
      model: settings.model,
      stream: true,
      messages: messages
    })
  }
}

// state is a plain object the caller keeps per in-flight request; this
// backend doesn't need any of its own fields in it (Anthropic's does).
//
// trim() matters here beyond cosmetics: SSE events are blank-line-separated
// ("data: {...}\n\n"), and Quickshell's SplitParser (default splitMarker
// "\n") delivers every chunk after the first with that blank separator's
// newline still attached as a leading "\n" - confirmed via debug logging,
// e.g. onRead fires with "\ndata: {...}" not "data: {...}". Without
// trimming, indexOf("data:") === 0 fails for every line but the first,
// silently dropping every subsequent delta and the final [DONE] too.
function parseSseLine(rawLine, state) {
  var line = String(rawLine || "").trim()
  if (line.indexOf("data:") !== 0) return null
  var payload = line.slice(5).trim()
  if (payload === "[DONE]") return { done: true }
  if (!payload) return null
  var obj
  try {
    obj = JSON.parse(payload)
  } catch (e) {
    return null
  }
  if (obj.error) return { error: obj.error.message || JSON.stringify(obj.error) }
  var choice = obj.choices && obj.choices[0]
  var delta = choice && choice.delta && typeof choice.delta.content === "string" ? choice.delta.content : ""
  var usage = obj.usage ? obj.usage : null
  if (!delta && !usage) return null
  return { delta: delta, usage: usage }
}

var OpenAiCompatBackend = {
  buildRequest: buildRequest,
  parseSseLine: parseSseLine
}
