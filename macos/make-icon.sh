#!/usr/bin/env bash
# Generate macos/build/AppIcon.icns entirely from code (no binary assets in the repo).
#
# Pipeline:
#   1. Emit a small Swift program (below) that draws the 1024x1024 master icon with
#      AppKit/CoreGraphics and writes build/AppIcon.png.
#   2. Down-scale the master into a .iconset (16..512 + @2x) with `sips`.
#   3. `iconutil -c icns` -> build/AppIcon.icns.
#
# The look matches the FelixDes identity of the widget: dark graphite squircle with an
# orange (#e8884a) speedometer gauge, a red end-zone, ticks and a needle at ~70%.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
SWIFT_SRC="$BUILD/draw-icon.swift"
MASTER="$BUILD/AppIcon.png"
ICONSET="$BUILD/AppIcon.iconset"
ICNS="$BUILD/AppIcon.icns"

mkdir -p "$BUILD"

cat > "$SWIFT_SRC" <<'SWIFT'
import AppKit
import CoreGraphics

// ---- output path -----------------------------------------------------------
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

// ---- canvas ----------------------------------------------------------------
let S: CGFloat = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S),
                          bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("could not create context")
}

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    return CGColor(colorSpace: cs, components: [r/255, g/255, b/255, a])!
}
func deg(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

// Palette (FelixDes look)
let orange   = rgb(232, 136, 74)   // #e8884a  protagonist
let orangeHi = rgb(255, 170, 110)  // needle highlight
let red      = rgb(220, 53, 69)    // #dc3545  end zone
let track    = rgb(58, 58, 66)     // subtle gauge track
let tickCol  = rgb(214, 214, 220)  // light ticks

// ---- squircle background ---------------------------------------------------
// macOS Big Sur+ icons: content lives on an ~824x824 rounded square centred in the
// 1024 canvas, leaving the standard transparent margin.
let side: CGFloat = 824
let originXY = (S - side) / 2          // 100
let corner: CGFloat = 185
let squircle = CGPath(roundedRect: CGRect(x: originXY, y: originXY, width: side, height: side),
                      cornerWidth: corner, cornerHeight: corner, transform: nil)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
// vertical gradient #2e2e33 (top) -> #1b1b1f (bottom)
let grad = CGGradient(colorsSpace: cs,
                      colors: [rgb(46, 46, 51), rgb(27, 27, 31)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: 0, y: S),   // top (flipped y-up space)
                       end:   CGPoint(x: 0, y: 0),   // bottom
                       options: [])
// faint inner top sheen
let sheen = CGGradient(colorsSpace: cs,
                       colors: [rgb(255, 255, 255, 0.05), rgb(255, 255, 255, 0)] as CFArray,
                       locations: [0, 1])!
ctx.drawLinearGradient(sheen,
                       start: CGPoint(x: 0, y: S),
                       end:   CGPoint(x: 0, y: S * 0.55),
                       options: [])
ctx.restoreGState()

// subtle inner border
ctx.saveGState()
ctx.addPath(squircle)
ctx.setStrokeColor(rgb(255, 255, 255, 0.06))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

// ---- gauge geometry --------------------------------------------------------
// 220 deg sweep, symmetric about the top. 0% at 200 deg, 100% at -20 deg,
// progressing clockwise (angle decreases with value).
let center = CGPoint(x: S/2, y: 470)
let radius: CGFloat = 292
let arcWidth: CGFloat = 48
let startDeg: CGFloat = 200
let sweep: CGFloat = 220
func angle(_ frac: CGFloat) -> CGFloat { deg(startDeg - frac * sweep) }

// full track (grey)
func strokeArc(from f0: CGFloat, to f1: CGFloat, color: CGColor, width: CGFloat) {
    ctx.saveGState()
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(color)
    let p = CGMutablePath()
    p.addArc(center: center, radius: radius,
             startAngle: angle(f0), endAngle: angle(f1), clockwise: true)
    ctx.addPath(p)
    ctx.strokePath()
    ctx.restoreGState()
}

// 1) base track across the whole arc
strokeArc(from: 0, to: 1, color: track, width: arcWidth)
// 2) orange progress fill up to the needle (70%)
strokeArc(from: 0, to: 0.70, color: orange, width: arcWidth)
// 3) red end zone (last 15%)
strokeArc(from: 0.85, to: 1, color: red, width: arcWidth)

// ---- ticks -----------------------------------------------------------------
// major ticks every 10%, sitting just inside the arc
let tickOuter = radius - arcWidth/2 - 14
for i in 0...10 {
    let f = CGFloat(i) / 10
    let a = angle(f)
    let major = (i % 5 == 0)
    let len: CGFloat = major ? 34 : 20
    let w:  CGFloat = major ? 8 : 5
    let inner = tickOuter - len
    let p0 = CGPoint(x: center.x + cos(a) * tickOuter, y: center.y + sin(a) * tickOuter)
    let p1 = CGPoint(x: center.x + cos(a) * inner,     y: center.y + sin(a) * inner)
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineWidth(w)
    ctx.setStrokeColor(tickCol.copy(alpha: major ? 0.95 : 0.55)!)
    ctx.move(to: p0)
    ctx.addLine(to: p1)
    ctx.strokePath()
    ctx.restoreGState()
}

// ---- needle at 70% ---------------------------------------------------------
let na = angle(0.70)
let needleLen: CGFloat = radius - 6
let baseHalf: CGFloat = 17
// direction + perpendicular
let dx = cos(na), dy = sin(na)
let px = -dy, py = dx
let tip  = CGPoint(x: center.x + dx * needleLen, y: center.y + dy * needleLen)
let tail = CGPoint(x: center.x - dx * 46,        y: center.y - dy * 46)
let bL   = CGPoint(x: center.x + px * baseHalf,  y: center.y + py * baseHalf)
let bR   = CGPoint(x: center.x - px * baseHalf,  y: center.y - py * baseHalf)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 22, color: rgb(0, 0, 0, 0.55))
let needle = CGMutablePath()
needle.move(to: tip)
needle.addLine(to: bL)
needle.addLine(to: tail)
needle.addLine(to: bR)
needle.closeSubpath()
ctx.addPath(needle)
// subtle gradient along needle for depth
ctx.clip()
let nGrad = CGGradient(colorsSpace: cs, colors: [orangeHi, orange] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(nGrad, start: tip, end: center, options: [.drawsAfterEndLocation])
ctx.restoreGState()

// ---- central hub -----------------------------------------------------------
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: rgb(0, 0, 0, 0.5))
ctx.setFillColor(rgb(30, 30, 34))
ctx.fillEllipse(in: CGRect(x: center.x - 46, y: center.y - 46, width: 92, height: 92))
ctx.restoreGState()
ctx.setFillColor(orange)
ctx.fillEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))
ctx.setFillColor(rgb(30, 30, 34))
ctx.fillEllipse(in: CGRect(x: center.x - 13, y: center.y - 13, width: 26, height: 26))

// ---- write PNG -------------------------------------------------------------
guard let img = ctx.makeImage() else { fatalError("no image") }
let rep = NSBitmapImageRep(cgImage: img)
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
try! data.write(to: URL(fileURLWithPath: outPath))
SWIFT

echo "==> drawing master 1024x1024 PNG"
swift "$SWIFT_SRC" "$MASTER"

echo "==> building iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
gen() { # gen <px> <name>
    sips -z "$1" "$1" "$MASTER" --out "$ICONSET/$2" >/dev/null
}
gen 16   icon_16x16.png
gen 32   icon_16x16@2x.png
gen 32   icon_32x32.png
gen 64   icon_32x32@2x.png
gen 128  icon_128x128.png
gen 256  icon_128x128@2x.png
gen 256  icon_256x256.png
gen 512  icon_256x256@2x.png
gen 512  icon_512x512.png
gen 1024 icon_512x512@2x.png

echo "==> packing .icns"
iconutil -c icns "$ICONSET" -o "$ICNS"

echo "OK: $ICNS"
