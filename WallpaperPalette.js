// Wallpaper-adaptive accent color, same approach as OmaDeezer's BarWidget.qml:
// a 5-color histogram of the current wallpaper via ImageMagick, most-common
// color first, clamped into a legible lightness/saturation band so a raw
// histogram color (often shadow-black or highlight-white) still reads well
// as UI accent. Kept here as pure functions - the Process/Quickshell.env
// wiring that drives them lives in Copilot.qml since this module has no
// access to QML types.

function paletteCommand(backgroundPath) {
  return ["magick", backgroundPath, "-resize", "150x150", "-colors", "5", "+dither", "-depth", "8", "-format", "%c", "histogram:info:-"]
}

// Returns an array of {count, hex} objects, most common first, deduplicated.
function parsePaletteHex(text) {
  var lines = String(text || "").split("\n")
  var entries = []
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*(\d+):\s*\([^)]*\)\s*(#[0-9A-Fa-f]{6,8})/)
    if (m) entries.push({ count: parseInt(m[1], 10), hex: m[2].substring(0, 7) })
  }
  entries.sort(function(a, b) { return b.count - a.count })
  var seen = {}
  var result = []
  for (var j = 0; j < entries.length && result.length < 5; j++) {
    if (seen[entries[j].hex]) continue
    seen[entries[j].hex] = true
    result.push(entries[j].hex)
  }
  return result
}

var WallpaperPalette = {
  paletteCommand: paletteCommand,
  parsePaletteHex: parsePaletteHex
}
