// Gera Resources/AppIcon.icns no estilo Liquid Glass, irmão dos ícones do Aero e do Capture:
// uma cápsula de vidro inclinada sobre verde.
// Uso: swift scripts/make-icon.swift [preview.png]
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func shadow(_ blur: CGFloat, _ y: CGFloat, _ alpha: CGFloat) {
    let s = NSShadow()
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: y)
    s.shadowColor = NSColor.black.withAlphaComponent(alpha)
    s.set()
}

/// Gradiente só na faixa da borda de dentro do `path`: é o brilho especular do vidro.
func rim(_ path: NSBezierPath, width: CGFloat, colors: [NSColor], locations: [CGFloat], angle: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    // Contorno grosso recortado pelo próprio shape = só a metade de dentro do traço.
    let stroked = NSBezierPath(cgPath: path.cgPath.copy(strokingWithWidth: width * 2, lineCap: .round,
                                                       lineJoin: .round, miterLimit: 10))
    stroked.addClip()
    NSGradient(colors: colors, atLocations: locations, colorSpace: .sRGB)!.draw(in: path.bounds, angle: angle)
    NSGraphicsContext.restoreGraphicsState()
}

/// Peça de vidro fosco: translúcida, com sombra macia, brilho em cima e reflexo embaixo.
func glass(_ path: NSBezierPath, filled: Bool) {
    let rect = path.bounds
    NSGraphicsContext.saveGraphicsState()
    shadow(44, -18, filled ? 0.28 : 0.12)
    color(0x063B33, filled ? 0.35 : 0.1).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let top = filled ? 0.96 : 0.16, bottom = filled ? 0.78 : 0.06
    NSGradient(starting: NSColor.white.withAlphaComponent(top), ending: NSColor.white.withAlphaComponent(bottom))!
        .draw(in: rect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    rim(path, width: filled ? 7 : 13,
        colors: [.white, NSColor.white.withAlphaComponent(filled ? 0.15 : 0.35), NSColor.white.withAlphaComponent(filled ? 0.6 : 0.8)],
        locations: [0, 0.55, 1], angle: -75)
}

/// Desenha no canvas de 1024×1024 do grid de ícones do macOS (origem embaixo).
func drawIcon() {
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

    NSGraphicsContext.saveGraphicsState()
    shadow(30, -14, 0.3)
    color(0x139C7F).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [color(0x7BE3B8), color(0x1FB590), color(0x0B6E66)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: body, angle: -90)
    // Luz difusa vinda de cima à esquerda.
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [NSColor.white.withAlphaComponent(0.3).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                          locations: [0, 1])!
    NSGraphicsContext.current!.cgContext.drawRadialGradient(glow, startCenter: CGPoint(x: 320, y: 900), startRadius: 0,
                                                            endCenter: CGPoint(x: 320, y: 900), endRadius: 640, options: [])
    NSGraphicsContext.restoreGraphicsState()
    rim(squircle, width: 5, colors: [NSColor.white.withAlphaComponent(0.55), NSColor.white.withAlphaComponent(0.05),
                                     NSColor.white.withAlphaComponent(0.2)],
        locations: [0, 0.5, 1], angle: -90)

    // Cápsula inclinada em duas metades: a de cima cheia, a de baixo só vidro.
    let length: CGFloat = 560, width: CGFloat = 230
    let rotate = AffineTransform(rotationByDegrees: 45)
    func half(_ upper: Bool) -> NSBezierPath {
        let gap: CGFloat = 14
        let rect = NSRect(x: upper ? gap / 2 : -length / 2, y: -width / 2, width: length / 2 - gap / 2, height: width)
        let path = NSBezierPath()
        // Ponta redonda só do lado de fora; o corte no meio é reto.
        let radius = width / 2
        if upper {
            path.move(to: NSPoint(x: rect.minX, y: rect.minY))
            path.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY))
            path.appendArc(withCenter: NSPoint(x: rect.maxX - radius, y: 0), radius: radius, startAngle: -90, endAngle: 90)
            path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: NSPoint(x: rect.maxX, y: rect.maxY))
            path.line(to: NSPoint(x: rect.minX + radius, y: rect.maxY))
            path.appendArc(withCenter: NSPoint(x: rect.minX + radius, y: 0), radius: radius, startAngle: 90, endAngle: 270)
            path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        }
        path.close()
        path.transform(using: rotate)
        path.transform(using: AffineTransform(translationByX: 512, byY: 512))
        return path
    }
    glass(half(false), filled: false)
    glass(half(true), filled: true)
}

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
if CommandLine.arguments.count > 1 {
    try! render(1024).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
print(iconutil.terminationStatus == 0 ? "✓ Resources/AppIcon.icns" : "✗ iconutil falhou")
