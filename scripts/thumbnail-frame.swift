// Used by make-thumbnails.sh: fits a capture onto a black canvas at 90% with its outer edge
// faded into the black, so the System Settings tile's own edge trim never cuts into the clock
// and there is no visible seam.
//   thumbnail-frame <in.png> <out.png> <width> <height>
import AppKit

let a = CommandLine.arguments
guard a.count == 5, let w = Int(a[3]), let h = Int(a[4]),
      let src = NSImage(contentsOfFile: a[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fputs("usage: thumbnail-frame in.png out.png width height\n", stderr); exit(1) }

ctx.interpolationQuality = .high
ctx.setFillColor(CGColor(gray: 0, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
let r = CGRect(x: 0, y: 0, width: w, height: h).insetBy(dx: CGFloat(w) * 0.05, dy: CGFloat(h) * 0.05)
ctx.draw(src, in: r)

let fade = min(r.width, r.height) * 0.06
let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                   colors: [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 0)] as CFArray,
                   locations: [0, 1])!
let edges: [(CGPoint, CGPoint)] = [
    (CGPoint(x: r.minX, y: 0), CGPoint(x: r.minX + fade, y: 0)),
    (CGPoint(x: r.maxX, y: 0), CGPoint(x: r.maxX - fade, y: 0)),
    (CGPoint(x: 0, y: r.minY), CGPoint(x: 0, y: r.minY + fade)),
    (CGPoint(x: 0, y: r.maxY), CGPoint(x: 0, y: r.maxY - fade)),
]
for (from, to) in edges {
    ctx.saveGState()
    ctx.clip(to: r)
    ctx.drawLinearGradient(g, start: from, end: to, options: [])
    ctx.restoreGState()
}
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
