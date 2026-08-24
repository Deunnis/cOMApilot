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
  property color accentColor: Color.accent
  property string fontFamily: Style.font.menuFamily

  signal changed(string key, var value)
  // Separate from `changed` above: fired continuously while dragging one of
  // the visual sliders below (no disk write - Copilot.qml just mirrors it
  // into a "live" property for instant visual feedback) vs. once on release
  // (the actual persisted commit) - same live/commit split as OmaDeezer's
  // own slider settings, to avoid writing shell.json on every drag tick.
  signal sliderLive(string key, var value)
  signal sliderReleased(string key, var value)
  signal resetVisualRequested()

  // Same 4 tunable visual settings as OmaDeezer's popup, same ranges/
  // defaults - single source of truth for the sliders below.
  readonly property var visualSliderDefs: [
    { key: "blur", label: "Blur", from: 0, to: 100, def: 40 },
    { key: "transparency", label: "Transparency", from: 0, to: 100, def: 40 },
    { key: "borderWidth", label: "Outline thickness", from: 0, to: 6, def: 2 },
    { key: "cornerRadius", label: "Corner roundness", from: 0, to: 20, def: 2 }
  ]

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
    accent: root.accentColor
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
    accent: root.accentColor
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
    accent: root.accentColor
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
    accent: root.accentColor
    font.family: root.fontFamily
    onEditingFinished: root.changed("endpointUrl", text)
  }

  Text {
    // A stored key is only ever attached to https:// requests (enforced
    // in OpenAiCompatBackend.js regardless of this warning) - this just
    // makes the risk visible before the user even tries to send anything,
    // for a keyed endpoint they just changed to something non-https.
    visible: endpointField.visible && root.apiKeyStatus === "set" && !/^https:\/\//i.test(root.settings.endpointUrl || "")
    width: parent.width
    text: "This endpoint isn't https:// - your stored API key will not be sent, and requests will fail until this is fixed."
    color: Color.urgent
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Toggle {
    width: parent.width
    label: "Stream responses"
    checked: root.settings.streaming !== false
    foreground: root.foreground
    accent: root.accentColor
    fontFamily: root.fontFamily
    onClicked: root.changed("streaming", !checked)
  }

  Toggle {
    width: parent.width
    label: "Include clipboard as context"
    description: "Sent as clearly-labeled untrusted data, never as instructions."
    checked: root.settings.includeClipboardContext === true
    foreground: root.foreground
    accent: root.accentColor
    fontFamily: root.fontFamily
    onClicked: root.changed("includeClipboardContext", !checked)
  }

  Toggle {
    width: parent.width
    label: "Include active window as context"
    description: "Sends the focused window's title and app id."
    checked: root.settings.includeActiveWindowContext === true
    foreground: root.foreground
    accent: root.accentColor
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
    accent: root.accentColor
    fontFamily: root.fontFamily
    onModified: root.changed("maxContextChars", value)
  }

  Toggle {
    width: parent.width
    label: "Allow the assistant to propose actions"
    description: "Every proposed action still requires your explicit confirmation before it runs."
    checked: root.settings.actionsEnabled === true
    foreground: root.foreground
    accent: root.accentColor
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
        accent: root.accentColor
        font.family: root.fontFamily
        onTextChanged: root.apiKeyDraft = text
        onAccepted: root.storeKey()
      }

      Button {
        id: saveBtn
        text: "Save"
        foreground: root.foreground
        accent: root.accentColor
        bordered: true
        onClicked: root.storeKey()
      }

      Button {
        id: clearBtn
        text: "Clear"
        foreground: root.foreground
        accent: root.accentColor
        bordered: true
        onClicked: root.clearKey()
      }
    }
  }

  PanelSeparator {
    width: parent.width
    foreground: root.foreground
  }

  Repeater {
    model: root.visualSliderDefs

    Column {
      id: sliderRow
      required property var modelData

      width: parent.width
      spacing: Style.spacing.xs

      Item {
        width: parent.width
        height: sliderLabel.implicitHeight

        Text {
          id: sliderLabel
          anchors.left: parent.left
          text: sliderRow.modelData.label
          color: root.foreground
          opacity: 0.75
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          anchors.right: parent.right
          text: String(root.settings[sliderRow.modelData.key] !== undefined ? root.settings[sliderRow.modelData.key] : sliderRow.modelData.def)
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      PanelSlider {
        width: parent.width
        minimum: sliderRow.modelData.from
        maximum: sliderRow.modelData.to
        integer: true
        value: root.settings[sliderRow.modelData.key] !== undefined ? root.settings[sliderRow.modelData.key] : sliderRow.modelData.def
        trackColor: Util.alpha(root.foreground, 0.15)
        fillColor: root.accentColor
        knobColor: root.foreground
        onMoved: function(v) { root.sliderLive(sliderRow.modelData.key, Math.round(v)) }
        onReleased: function(v) { root.sliderReleased(sliderRow.modelData.key, Math.round(v)) }
      }
    }
  }

  Button {
    width: parent.width
    text: "Reset visual settings to defaults"
    tooltipText: "Blur, transparency, outline, and corner roundness back to their defaults"
    bordered: true
    foreground: root.foreground
    accent: root.accentColor
    onClicked: root.resetVisualRequested()
  }
}
