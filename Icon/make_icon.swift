// アプリアイコンを描いて PNG に書き出す: swift Icon/make_icon.swift
// - AppIcon.icon/Assets/Gauge.png : Icon Composer 形式のメーターのレイヤー（背景色は icon.json）
// - AppIcon-preview.png           : 角丸の背景つき完成イメージ（README・記事用）
// アプリへの組み込みは build.sh が actool で AppIcon.icon をコンパイルして行う
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let outDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(_ name: String, draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    let url = outDir.appending(path: name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(url.path)")
}

func drawBackground(_ ctx: CGContext, in rect: CGRect) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [color(0x2B3F7A), color(0x111A38)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.maxY),
                           end: CGPoint(x: rect.midX, y: rect.minY), options: [])
}

/// メーター本体。0%=左下(220°) から 100%=右下(-40°) まで時計回り
func drawGauge(_ ctx: CGContext, value: Double = 0.42) {
    let center = CGPoint(x: size / 2, y: size / 2 - 40)
    let radius = 270.0
    let width = 62.0
    let start = 220.0, sweep = 260.0
    func angle(_ fraction: Double) -> CGFloat { CGFloat((start - sweep * fraction) * .pi / 180) }

    func arc(_ from: Double, _ to: Double, _ stroke: CGColor, cap: CGLineCap = .round) {
        ctx.setLineWidth(width)
        ctx.setLineCap(cap)
        ctx.setStrokeColor(stroke)
        ctx.addArc(center: center, radius: radius, startAngle: angle(from), endAngle: angle(to), clockwise: true)
        ctx.strokePath()
    }

    // 目盛りの帯：〜80% は薄い白、80〜90% は橙、90〜100% は赤（通知の段階）
    // 赤の丸い始点が橙の範囲にはみ出すので、橙を後から描いて境目をくっきりさせる
    arc(0, 1, color(0xFFFFFF, 0.16))
    arc(0.9, 1, color(0xE34948))
    arc(0.8, 0.9, color(0xEB6834), cap: .butt)
    // 使用率
    arc(0, value, color(0x4C9BF0))

    // 目盛りの点
    ctx.setFillColor(color(0xFFFFFF, 0.55))
    for i in 0...10 {
        let a = angle(Double(i) / 10)
        let r = radius - width / 2 - 34
        let p = CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
        let d = i % 5 == 0 ? 18.0 : 11.0
        ctx.fillEllipse(in: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d))
    }

    // 針
    let a = angle(value)
    let tip = CGPoint(x: center.x + cos(a) * (radius - 70), y: center.y + sin(a) * (radius - 70))
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: color(0x000000, 0.35))
    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.setLineWidth(30)
    ctx.setLineCap(.round)
    ctx.move(to: center)
    ctx.addLine(to: tip)
    ctx.strokePath()
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: center.x - 48, y: center.y - 48, width: 96, height: 96))
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.setFillColor(color(0x1A2650))
    ctx.fillEllipse(in: CGRect(x: center.x - 18, y: center.y - 18, width: 36, height: 36))
}

// 完成イメージ：macOS のアイコン枠（1024 中 824 の角丸四角）に合わせる
render("AppIcon-preview.png") { ctx in
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.3))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x111A38))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    drawBackground(ctx, in: rect)
    ctx.translateBy(x: rect.midX, y: rect.midY)
    ctx.scaleBy(x: 0.8, y: 0.8)
    ctx.translateBy(x: -size / 2, y: -size / 2)
    drawGauge(ctx)
    ctx.restoreGState()
}

// Icon Composer 用のレイヤー（背景・角丸・ガラス効果は macOS 側が付ける）
render("AppIcon.icon/Assets/Gauge.png") { ctx in drawGauge(ctx) }
