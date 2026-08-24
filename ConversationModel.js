// Pure transform: turns a snapshot of the conversation ListModel's rows
// (plain {role, content, error} objects) into the {role, content} array the
// backend request builders expect - dropping UI-only fields and any
// still-empty/errored placeholder rows.

function toApiMessages(rows) {
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (!row || row.error) continue
    if (typeof row.content !== "string" || row.content.length === 0) continue
    out.push({ role: row.role, content: row.content })
  }
  return out
}

var ConversationModel = {
  toApiMessages: toApiMessages
}
