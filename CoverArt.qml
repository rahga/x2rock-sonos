import QtQuick
import qs.Commons

// Cover art that fails quietly.
//
// Plenty of sources have no art at all - two of five rooms here were playing
// with none - so the placeholder is a themed glyph on a tint of the bar's own
// foreground, not an empty hole or a foreign grey box, and it is what shows
// until the image is actually decoded.
//
// **`url` is a local file or nothing.** Art arrives from Sonos as the
// speaker's own `http://<ip>:1400/getaa?...` or a music service's CDN, and an
// `Image` given either would fetch it with no limit on where or how much. So
// the widget resolves it through `x2rock art` (see `artFor` in BarWidget.qml),
// which fetches under a byte cap into its cache, and this shows only a file
// named the way that cache names them. Anything else is the placeholder.
//
// Deliberately not used on the bar pill: that is always on screen, and a
// full-colour thumbnail there would fight whatever palette the bar is themed
// to. Inside a popup the art is content the user asked to see.
Rectangle {
  id: root

  property string url: ""
  readonly property string safeUrl:
    /^file:\/\/\/.+\/x2rock\/art\/[0-9a-f]{32}\.(jpg|png|gif|webp)$/.test(url) ? url : ""
  property color foreground: "white"
  property string fontFamily: Style.font.family
  property int size: Style.space(38)
  /// Shown until - or unless - the image arrives. Follows the widget's glyphs.
  property string placeholder: "󰓃"

  implicitWidth: size
  implicitHeight: size
  radius: Style.space(4)
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
  clip: true

  Text {
    textFormat: Text.PlainText
    anchors.centerIn: parent
    visible: art.status !== Image.Ready
    text: root.placeholder
    color: Qt.darker(root.foreground, 1.9)
    font.family: root.fontFamily
    font.pixelSize: Math.round(root.size * 0.5)
  }

  Image {
    id: art
    anchors.fill: parent
    source: root.safeUrl
    // Decoding off the UI thread; covers arrive when they arrive.
    asynchronous: true
    cache: true
    fillMode: Image.PreserveAspectCrop
    // Covers come back at 544px; decoding that for a 38px tile is waste.
    // Twice the tile keeps it sharp on a scaled display without paying full price.
    sourceSize.width: root.size * 2
    sourceSize.height: root.size * 2
    visible: status === Image.Ready
  }
}
