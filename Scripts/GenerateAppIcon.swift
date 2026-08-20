#!/usr/bin/env swift
//
//  Draws Wattson's app icon at every size the App Store needs and writes the PNGs
//  straight into the asset catalog. Run it on a Mac with the Xcode command line
//  tools installed:
//
//      swift Scripts/GenerateAppIcon.swift
//
//  Keeping the icon as code rather than a binary asset means it is reviewable in a
//  diff and regenerates identically on any machine.
//
import AppKit
import CoreGraphics
import Foundation

let sizes: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)
]

let outputDirectory = URL(fileURLWithPath: "App/Resources/Assets.xcassets/AppIcon.appiconset")

func draw(into context: CGContext, side: CGFloat) {
    let unit = side / 1024.0
    func s(_ value: CGFloat) -> CGFloat { value * unit }

    // Rounded-square backdrop with the app's green-to-blue gradient.
    let inset = s(60)
    let squircle = CGPath(
        roundedRect: CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2),
        cornerWidth: s(200),
        cornerHeight: s(200),
        transform: nil
    )
    context.saveGState()
    context.addPath(squircle)
    context.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.16, green: 0.74, blue: 0.55, alpha: 1),
            CGColor(red: 0.20, green: 0.52, blue: 0.92, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: side),
            end: CGPoint(x: side, y: 0),
            options: []
        )
    }
    context.restoreGState()

    // The battery body.
    let body = CGRect(x: s(300), y: s(230), width: s(424), height: s(500))
    let bodyPath = CGPath(roundedRect: body, cornerWidth: s(90), cornerHeight: s(90), transform: nil)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.97))
    context.addPath(bodyPath)
    context.fillPath()

    // Terminal nub.
    context.setFillColor(CGColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1))
    context.addPath(CGPath(
        roundedRect: CGRect(x: s(452), y: s(730), width: s(120), height: s(66)),
        cornerWidth: s(24), cornerHeight: s(24), transform: nil
    ))
    context.fillPath()

    // Charge fill.
    context.saveGState()
    context.addPath(CGPath(
        roundedRect: body.insetBy(dx: s(40), dy: s(40)),
        cornerWidth: s(56), cornerHeight: s(56), transform: nil
    ))
    context.clip()
    context.setFillColor(CGColor(red: 0.24, green: 0.82, blue: 0.48, alpha: 1))
    context.fill(CGRect(x: body.minX, y: body.minY, width: body.width, height: body.height * 0.62))
    context.restoreGState()

    // Eyes.
    context.setFillColor(CGColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1))
    for x in [s(410), s(560)] {
        context.fillEllipse(in: CGRect(x: x, y: s(520), width: s(56), height: s(66)))
    }

    // Smile.
    context.setStrokeColor(CGColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1))
    context.setLineWidth(s(26))
    context.setLineCap(.round)
    context.move(to: CGPoint(x: s(420), y: s(430)))
    context.addQuadCurve(to: CGPoint(x: s(604), y: s(430)), control: CGPoint(x: s(512), y: s(340)))
    context.strokePath()

    // Lightning bolt badge.
    context.setFillColor(CGColor(red: 1.0, green: 0.84, blue: 0.25, alpha: 1))
    let bolt = CGMutablePath()
    bolt.move(to: CGPoint(x: s(700), y: s(700)))
    bolt.addLine(to: CGPoint(x: s(560), y: s(480)))
    bolt.addLine(to: CGPoint(x: s(660), y: s(480)))
    bolt.addLine(to: CGPoint(x: s(620), y: s(280)))
    bolt.addLine(to: CGPoint(x: s(770), y: s(520)))
    bolt.addLine(to: CGPoint(x: s(670), y: s(520)))
    bolt.closeSubpath()
    context.addPath(bolt)
    context.fillPath()
}

for (points, scale) in sizes {
    let side = CGFloat(points * scale)
    guard let context = CGContext(
        data: nil,
        width: Int(side),
        height: Int(side),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        print("Could not create a bitmap context for \(points)@\(scale)x")
        exit(1)
    }

    draw(into: context, side: side)

    guard
        let image = context.makeImage(),
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else {
        print("Could not encode \(points)@\(scale)x")
        exit(1)
    }

    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    let url = outputDirectory.appendingPathComponent(name)
    do {
        try data.write(to: url)
        print("Wrote \(name)")
    } catch {
        print("Could not write \(name): \(error.localizedDescription)")
        exit(1)
    }
}

print("App icon regenerated.")
