// Renders a centred, wrapped line of marketing copy with Core Text, so every
// script (Arabic, Thai, CJK…) is shaped and laid out the way iOS would.
// compose.py builds and calls it for the languages Pillow can't shape.
// A "\n" in the text is an explicit line break.
//
//   text <serif|sans> <pixel size> <RRGGBB> <max width> <out.png> <text…>
//
// Prints the number of lines. Lines are balanced: the narrowest width that
// keeps the same number of lines, so no line is a lonely word.
import AppKit

let args = CommandLine.arguments
guard args.count >= 7, let size = Double(args[2]), let maxWidth = Double(args[4]) else {
    FileHandle.standardError.write("usage: text <serif|sans> <size> <RRGGBB> <maxWidth> <out.png> <text>\n".data(using: .utf8)!)
    exit(1)
}
let text = args[6...].joined(separator: " ")
let hex = UInt32(args[3], radix: 16) ?? 0xFFFFFF
let color = NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)

var font = NSFont.systemFont(ofSize: size, weight: .medium)
if args[1] == "serif", let serif = font.fontDescriptor.withDesign(.serif) {
    font = NSFont(descriptor: serif.withSymbolicTraits(.italic), size: size) ?? font
}
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
paragraph.lineBreakMode = .byWordWrapping
paragraph.lineBreakStrategy = [.hangulWordPriority, .pushOut]
paragraph.lineHeightMultiple = args[1] == "serif" ? 1.0 : 1.08
let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])

func layout(_ width: Double) -> (lines: Int, size: CGSize, manager: NSLayoutManager, container: NSTextContainer, storage: NSTextStorage) {
    let storage = NSTextStorage(attributedString: attributed)
    let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    let manager = NSLayoutManager()
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)
    manager.ensureLayout(for: container)
    var lines = 0
    manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { _, _, _, _, _ in lines += 1 }
    let used = manager.usedRect(for: container)
    return (lines, CGSize(width: ceil(used.width), height: ceil(used.height)), manager, container, storage)
}

let full = layout(maxWidth)
var width = maxWidth
// Copy with its own line breaks (Japanese, which has no spaces) is left as written.
if full.lines > 1 && !text.contains("\n") {
    var low = maxWidth * 0.3, high = maxWidth
    while high - low > 2 {
        let mid = (low + high) / 2
        if layout(mid).lines > full.lines { low = mid } else { high = mid }
    }
    width = high
}
let final = layout(width)
let pad = ceil(size * 0.35)
let canvas = CGSize(width: width + 2 * pad, height: final.size.height + 2 * pad)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
// Draw with the same layout that was measured, so the line breaks match.
NSGraphicsContext.current?.cgContext.translateBy(x: 0, y: canvas.height)
NSGraphicsContext.current?.cgContext.scaleBy(x: 1, y: -1)
let flipped = NSGraphicsContext(cgContext: NSGraphicsContext.current!.cgContext, flipped: true)
NSGraphicsContext.current = flipped
final.manager.drawGlyphs(forGlyphRange: NSRange(location: 0, length: final.manager.numberOfGlyphs), at: CGPoint(x: pad, y: pad))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[5]))
print(final.lines)
