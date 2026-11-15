// Measure the native zoom HUD from a Retina screenshot.
//
// Usage:
//   swift tools/hud_measure.swift /path/to/screenshot.png [scale]
//
// Prints the pill and text bounds in pixels and points. The default scale is
// 2.0 (Retina); pass 1.0 for a non-Retina capture. Captures include the dark
// pill drawn by ZoomHUD, so the scan is independent of window position.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("usage: swift tools/hud_measure.swift screenshot.png [scale]\n", stderr)
    exit(1)
}

let path = arguments[1]
let scale = arguments.count > 2 ? (Double(arguments[2]) ?? 2.0) : 2.0
guard scale > 0 else {
    fputs("scale must be positive\n", stderr)
    exit(1)
}

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
    let data = image.dataProvider?.data as Data?
else {
    fputs("could not read \(path)\n", stderr)
    exit(1)
}

let bytesPerRow = image.bytesPerRow
let bytesPerPixel = image.bitsPerPixel / 8
let width = image.width
let height = image.height

func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    let offset = y * bytesPerRow + x * bytesPerPixel
    return (Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2]))
}

// ZoomHUDBackground is approximately #1B1D22 at 88% over the workspace.
func isPill(_ color: (Int, Int, Int)) -> Bool {
    let (r, g, b) = color
    return r >= 22 && r <= 36 && g >= 26 && g <= 40 && b >= 32 && b <= 50 && abs(b - g) <= 14
}

func isText(_ color: (Int, Int, Int)) -> Bool {
    let (r, g, b) = color
    return r > 235 && g > 235 && b > 235
}

var pillMinX = Int.max
var pillMaxX = 0
var pillMinY = Int.max
var pillMaxY = 0
for y in 0..<height {
    for x in 0..<width where isPill(rgb(x, y)) {
        pillMinX = min(pillMinX, x)
        pillMaxX = max(pillMaxX, x)
        pillMinY = min(pillMinY, y)
        pillMaxY = max(pillMaxY, y)
    }
}

guard pillMaxX > pillMinX, pillMaxY > pillMinY else {
    fputs("no zoom HUD pill found (is the HUD visible in the capture?)\n", stderr)
    exit(2)
}

var textMinX = Int.max
var textMaxX = 0
var textMinY = Int.max
var textMaxY = 0
for y in pillMinY...pillMaxY {
    for x in pillMinX...pillMaxX where isText(rgb(x, y)) {
        textMinX = min(textMinX, x)
        textMaxX = max(textMaxX, x)
        textMinY = min(textMinY, y)
        textMaxY = max(textMaxY, y)
    }
}

func points(_ pixels: Int) -> Double { Double(pixels) / scale }
func describe(_ minX: Int, _ maxX: Int, _ minY: Int, _ maxY: Int) -> String {
    "\(maxX - minX + 1)x\(maxY - minY + 1) px = \(points(maxX - minX + 1))x\(points(maxY - minY + 1)) pt"
}

print(
    "pill px: x \(pillMinX)...\(pillMaxX) y \(pillMinY)...\(pillMaxY)  size \(describe(pillMinX, pillMaxX, pillMinY, pillMaxY))"
)
if textMaxX > textMinX {
    print(
        "text px: x \(textMinX)...\(textMaxX) y \(textMinY)...\(textMaxY)  size \(describe(textMinX, textMaxX, textMinY, textMaxY))"
    )
    print(
        "left pad \(points(textMinX - pillMinX))pt  right pad \(points(pillMaxX - textMaxX))pt  top pad \(points(textMinY - pillMinY))pt  bottom pad \(points(pillMaxY - textMaxY))pt"
    )
}
