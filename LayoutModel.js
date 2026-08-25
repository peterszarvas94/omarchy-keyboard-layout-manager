function isTypedKeyboard(name) {
  return !/^(hl-virtual-keyboard|power-button|sleep-button|lid-switch|video-bus|.*consumer-control|.*system-control|yubico-yubikey|razer-inc\.-razer-seiren)/.test(String(name || ""))
}

function configuredLayouts(devices) {
  var keyboards = devices && Array.isArray(devices.keyboards) ? devices.keyboards : []
  for (var i = 0; i < keyboards.length; i++) {
    var keyboard = keyboards[i]
    if (!keyboard || !keyboard.layout || !keyboard.name || !isTypedKeyboard(keyboard.name)) continue
    return {
      keyboard: String(keyboard.name),
      layouts: String(keyboard.layout).split(",").map(function(layout) {
        return layout.trim().toLowerCase()
      }),
      activeIndex: Number(keyboard.active_layout_index || 0)
    }
  }
  return { keyboard: "", layouts: [], activeIndex: 0 }
}

function layoutLabel(layout) {
  return String(layout || "").toUpperCase()
}

function parseLayouts(text) {
  var layouts = []
  var byCode = {}
  var current = null
  String(text || "").split("\n").forEach(function(line) {
    var match = line.match(/^\s*- layout: ['"]?([^'"\s]+)['"]?\s*$/)
    if (match) {
      if (current && current.code && (!byCode[current.code] || current.variant === "")) byCode[current.code] = current
      current = { code: match[1], variant: "", description: match[1] }
      return
    }
    if (!current) return
    var variant = line.match(/^\s+variant: ['"]?(.*?)['"]?\s*$/)
    var description = line.match(/^\s+description: ['"]?(.*?)['"]?\s*$/)
    if (variant) current.variant = variant[1]
    if (description) current.description = description[1]
  })
  if (current && current.code && (!byCode[current.code] || current.variant === "")) byCode[current.code] = current
  for (var code in byCode) layouts.push(byCode[code])
  layouts.sort(function(a, b) { return a.description.localeCompare(b.description) })
  return layouts
}

if (typeof module !== "undefined") module.exports = {
  configuredLayouts: configuredLayouts,
  layoutLabel: layoutLabel,
  parseLayouts: parseLayouts
}
