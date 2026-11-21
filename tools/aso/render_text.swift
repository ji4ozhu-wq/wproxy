import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 6 else { fputs("usage: render_text text size color maxWidth output\n", stderr); exit(2) }
let text = args[1]
let size = Double(args[2]) ?? 96
let colorHex = args[3]
let maxWidth = Double(args[4]) ?? 0
let outPath = args[5]

func color(_ hex: String) -> NSColor {
    var h = hex
    if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return .black }
    return NSColor(calibratedRed: CGFloat((v >> 16) & 0xff) / 255,
                   green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: 1)
}

let font = NSFont(name: "Thonburi-Bold", size: size) ?? NSFont.boldSystemFont(ofSize: size)
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
paragraph.lineBreakMode = .byWordWrapping
let attr = NSAttributedString(string: text, attributes: [
    .font: font,
    .foregroundColor: color(colorHex),
    .paragraphStyle: paragraph,
])
let wrapWidth = maxWidth > 0 ? maxWidth : 2000
let bounds = attr.boundingRect(with: NSSize(width: wrapWidth, height: 1400),
                               options: [.usesLineFragmentOrigin, .usesFontLeading])
let width = ceil(bounds.width) + 40
let height = ceil(bounds.height) + 40
let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
attr.draw(in: NSRect(x: 20, y: 20, width: width - 40, height: height - 40))
image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! data.write(to: URL(fileURLWithPath: outPath))
