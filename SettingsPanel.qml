import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Secrets.js" as Secrets
import "OllamaProbe.js" as OllamaProbe

// Non-secret fields (backend/model/endpoint/streaming) are read from and
// written back to `settings` by the caller (Copilot.qml), exactly like
// OmaDeezer's persist()/shell.updateEntryInline() pattern. The API key never
// flows through `settings`/shell.json at all - it's looked up, stored, and
// cleared here directly via secret-tool, keyed per-backend so switching
// backends doesn't lose a previously-stored key.
Column {
  id: root

  property var settings: ({})
  property color foreground: Color.menu.text
  property string fontFamily: Style.font.menuFamily

  signal changed(string key, var value)

  // "checking" | "set" | "unset"
  property string apiKeyStatus: "checking"
  property string apiKeyDraft: ""

  function backendValue() {
    return settings.backend || "openai-compatible"
  }

  function refreshKeyStatus() {
    apiKeyStatus = "checking"
    lookupProc.command = Secrets.lookupCommand(backendValue())
    lookupProc.running = true
  }

  function storeKey() {
    if (!apiKeyDraft) return
    storeProc.pendingSecret = apiKeyDraft
    storeProc.command = Secrets.storeCommand(backendValue())
    storeProc.running = true
  }

  function clearKey() {
    apiKeyDraft = ""
    clearProc.command = Secrets.clearCommand(backendValue())
    clearProc.running = true
  }

  // "checking" | "detected" | "not-detected"
  property string ollamaStatus: "checking"
  property var ollamaModels: []

  function refreshOllamaStatus() {
    ollamaStatus = "checking"
    ollamaProbeProc.command = OllamaProbe.probeCommand()
    ollamaProbeProc.running = true
  }

  onSettingsChanged: refreshKeyStatus()
  Component.onCompleted: {
    refreshKeyStatus()
    refreshOllamaStatus()
  }
  // Probed when the panel becomes visible, not per-keystroke - this Column
  // is created once and just toggled visible/invisible by Copilot.qml
  // rather than re-instantiated, so Component.onCompleted alone would only
  // ever probe once for the whole overlay's lifetime.
  onVisibleChanged: if (visible) refreshOllamaStatus()

  Process {
    id: ollamaProbeProc
    stdout: StdioCollector { id: ollamaProbeOut; waitForEnd: true }
    onExited: function(code) {
      if (code === 0) {
        root.ollamaModels = OllamaProbe.parseModelNames(ollamaProbeOut.text)
        root.ollamaStatus = "detected"
      } else {
        root.ollamaModels = []
        root.ollamaStatus = "not-detected"
      }
    }
  }

  Process {
    id: lookupProc
    stdout: StdioCollector {
      id: lookupOut
      waitForEnd: true
      onStreamFinished: root.apiKeyStatus = String(lookupOut.text || "").trim().length > 0 ? "set" : "unset"
    }
    onExited: function(code) { if (code !== 0) root.apiKeyStatus = "unset" }
  }

  Process {
    id: storeProc
    property string pendingSecret: ""
    stdinEnabled: true
    onStarted: { write(pendingSecret + "\n"); pendingSecret = "" }
    onExited: function(code) {
      root.apiKeyDraft = ""
      root.refreshKeyStatus()
    }
  }

  Process {
    id: clearProc
    onExited: function(code) { root.refreshKeyStatus() }
  }

  width: parent ? parent.width : 0
  spacing: Style.spacing.lg

  Dropdown {
    width: parent.width
    label: "Backend"
    value: root.backendValue()
    options: ["openai-compatible", "anthropic", "ollama"]
    foreground: root.foreground
    fontFamily: root.fontFamily
    onChanged: function(value) {
      root.changed("backend", value)
      // Ollama's endpoint is fixed (not user-edited, see endpointField's
      // visibility below) - fill it in automatically so OpenAiCompatBackend
      // (reused unchanged for this backend) has a working URL right away.
      if (value === "ollama") root.changed("endpointUrl", OllamaProbe.OLLAMA_ENDPOINT_URL)
    }
  }

  Text {
    visible: root.backendValue() === "ollama"
    width: parent.width
    text: root.ollamaStatus === "checking" ? "Checking for a local Ollama server…"
      : root.ollamaStatus === "detected" ? ("Ollama detected - " + root.ollamaModels.length + " model(s) available")
      : "Ollama not detected at localhost:11434 - make sure it's running"
    color: root.foreground
    opacity: 0.65
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Dropdown {
    visible: root.backendValue() === "ollama" && root.ollamaModels.length > 0
    width: parent.width
    label: "Model"
    value: root.settings.model || ""
    options: root.ollamaModels
    foreground: root.foreground
    fontFamily: root.fontFamily
    onChanged: function(value) { root.changed("model", value) }
  }

  TextField {
    id: modelField
    visible: root.backendValue() !== "ollama" || root.ollamaModels.length === 0
    width: parent.width
    placeholderText: "Model"
    text: root.settings.model || ""
    foreground: root.foreground
    font.family: root.fontFamily
    onEditingFinished: root.changed("model", text)
  }

  TextField {
    id: endpointField
    width: parent.width
    visible: root.backendValue() !== "anthropic" && root.backendValue() !== "ollama"
    height: visible ? implicitHeight : 0
    placeholderText: "Endpoint URL"
    text: root.settings.endpointUrl || ""
    foreground: root.foreground
    font.family: root.fontFamily
    onEditingFinished: root.changed("endpointUrl", text)
  }

  Toggle {
    width: parent.width
    label: "Stream responses"
    checked: root.settings.streaming !== false
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: root.changed("streaming", !checked)
  }

  Toggle {
    width: parent.width
    label: "Include clipboard as context"
    description: "Sent as clearly-labeled untrusted data, never as instructions."
    checked: root.settings.includeClipboardContext === true
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: root.changed("includeClipboardContext", !checked)
  }

  Toggle {
    width: parent.width
    label: "Include active window as context"
    description: "Sends the focused window's title and app id."
    checked: root.settings.includeActiveWindowContext === true
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: root.changed("includeActiveWindowContext", !checked)
  }

  NumberField {
    id: maxContextCharsField
    label: "Max context characters"
    value: root.settings.maxContextChars || 4000
    from: 500
    to: 20000
    stepSize: 500
    foreground: root.foreground
    fontFamily: root.fontFamily
    onModified: root.changed("maxContextChars", value)
  }

  Toggle {
    width: parent.width
    label: "Allow the assistant to propose actions"
    description: "Every proposed action still requires your explicit confirmation before it runs."
    checked: root.settings.actionsEnabled === true
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: root.changed("actionsEnabled", !checked)
  }

  Column {
    width: parent.width
    spacing: Style.spacing.sm
    visible: root.backendValue() !== "ollama"

    Text {
      width: parent.width
      text: "API key (" + root.backendValue() + "): " +
        (root.apiKeyStatus === "set" ? "stored in your keyring"
          : root.apiKeyStatus === "checking" ? "checking…" : "not set")
      color: root.foreground
      opacity: 0.65
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Row {
      width: parent.width
      spacing: Style.spacing.sm

      TextField {
        id: keyField
        width: parent.width - saveBtn.width - clearBtn.width - Style.spacing.sm * 2
        password: true
        placeholderText: "Paste API key…"
        text: root.apiKeyDraft
        foreground: root.foreground
        font.family: root.fontFamily
        onTextChanged: root.apiKeyDraft = text
        onAccepted: root.storeKey()
      }

      Button {
        id: saveBtn
        text: "Save"
        foreground: root.foreground
        bordered: true
        onClicked: root.storeKey()
      }

      Button {
        id: clearBtn
        text: "Clear"
        foreground: root.foreground
        bordered: true
        onClicked: root.clearKey()
      }
    }
  }
}
