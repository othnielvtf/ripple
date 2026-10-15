import AppKit

@MainActor
final class SliderActionReceiver: NSObject {
    var receivedValue: Double?
    @objc func changed(_ sender: NSSlider) { receivedValue = sender.doubleValue }
}

@main
@MainActor
struct SliderTests {
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError("FAIL: \(message)") }
            checks += 1
            print("PASS: \(message)")
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 40),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let slider = EffectSlider(initialValue: 0.62)
        slider.frame = NSRect(x: 10, y: 7, width: 640, height: 26)
        slider.controlSize = .small
        window.contentView?.addSubview(slider)
        let receiver = SliderActionReceiver()
        slider.target = receiver
        slider.action = #selector(receiver.changed(_:))
        check(slider.cell is EffectSliderCell, "use custom drawing with a native NSSlider cell")
        slider.doubleValue = 0.4
        slider.sendAction(slider.action, to: slider.target)
        check(receiver.receivedValue == 0.4, "native slider actions deliver the selected value")

        var examples: [(Bool, SliderEffect, Data)] = []
        var renders = 0
        for dark in [true, false] {
            Palette.isDark = dark
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            window.appearance = appearance
            for theme in ColourTheme.allCases {
                Palette.theme = theme
                slider.trackFillColor = Palette.accent
                var styleImages: [Data] = []
                for effect in SliderEffect.allCases {
                    Palette.sliderEffect = effect
                    for width in [92.0, 640.0] {
                        slider.frame.size.width = width
                        for value in [0.0, 0.5, 1.0] {
                            slider.doubleValue = value
                            let data = snapshot(slider, appearance: appearance)
                            guard data.count > 100, slider.doubleValue == value else {
                                fatalError("A slider failed to render or changed its playback value")
                            }
                            renders += 1
                            if width == 640 && value == 0.5 {
                                styleImages.append(data)
                                if theme == .blue { examples.append((dark, effect, data)) }
                            }
                        }
                    }
                }
                check(Set(styleImages).count == SliderEffect.allCases.count,
                      "all styles render distinctly in \(theme.title), \(dark ? "Dark" : "Light")")
            }
        }
        slider.isEnabled = false
        Palette.sliderEffect = .laser
        check(snapshot(slider, appearance: NSAppearance(named: .aqua)!).count > 100, "render an empty, disabled slider")
        check(renders == 288, "render 288 combinations of style, theme, length, and position")

        if let path = ProcessInfo.processInfo.environment["RIPPLE_SLIDER_PREVIEW"] {
            try makeGallery(examples, path: path)
        }
        print("\(checks) slider checks passed.")
    }

    static func snapshot(_ slider: NSSlider, appearance: NSAppearance) -> Data {
        let bitmap = slider.bitmapImageRepForCachingDisplay(in: slider.bounds)!
        appearance.performAsCurrentDrawingAppearance { slider.cacheDisplay(in: slider.bounds, to: bitmap) }
        return bitmap.representation(using: .png, properties: [:])!
    }

    static func makeGallery(_ examples: [(Bool, SliderEffect, Data)], path: String) throws {
        let image = NSImage(size: NSSize(width: 760, height: 720))
        image.lockFocus()
        for (index, example) in examples.enumerated() {
            let (dark, effect, png) = example
            let y = CGFloat(720 - (index + 1) * 90)
            (dark ? NSColor(hex: 0x131B1E) : NSColor(hex: 0xF7F9F8)).setFill()
            NSRect(x: 0, y: y, width: 760, height: 90).fill()
            ("\(effect.title) · \(dark ? "Dark" : "Light")" as NSString).draw(
                at: NSPoint(x: 30, y: y + 55), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                    .foregroundColor: dark ? NSColor.white : NSColor.black
                ])
            NSImage(data: png)!.draw(in: NSRect(x: 30, y: y + 18, width: 640, height: 26))
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
}
