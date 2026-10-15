import AppKit

/// Only the drawing changes. NSSlider retains its native mouse, keyboard,
/// focus, and accessibility behaviour. No animation or additional timer is used.
final class EffectSlider: NSSlider {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = EffectSliderCell()
        sliderType = .linear
        isVertical = false
        minValue = 0
        maxValue = 1
        isContinuous = true
        focusRingType = .exterior
    }
    convenience init(initialValue: Double) {
        self.init(frame: .zero)
        doubleValue = initialValue
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { NSSize(width: super.intrinsicContentSize.width, height: 26) }
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
}

final class EffectSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        guard Palette.sliderEffect != .none else { super.drawBar(inside: rect, flipped: flipped); return }
        let style = Palette.sliderEffect
        let centerY = rect.midY
        let track = NSRect(x: rect.minX, y: centerY - 1.5, width: rect.width, height: 3)
        let markerX = min(track.maxX, max(track.minX, knobRect(flipped: flipped).midX))
        let fraction = maxValue > minValue ? (doubleValue - minValue) / (maxValue - minValue) : 0
        let width = fraction <= 0 ? 0 : (fraction >= 1 ? track.width : markerX - track.minX)
        let filled = NSRect(x: track.minX, y: track.minY, width: max(0, width), height: track.height)
        let accent = Palette.accent

        Palette.line.withAlphaComponent(isEnabled ? 1 : 0.55).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
        guard isEnabled, filled.width > 0 else { return }

        switch style {
        case .none: break
        case .neon:
            glow(filled, colour: accent, radius: 3, opacity: Palette.isDark ? 0.55 : 0.22)
            fill(filled, colour: accent)
            fill(NSRect(x: filled.minX, y: centerY - 0.5, width: filled.width, height: 1),
                 colour: coreColour(amount: 0.6))
        case .glowy:
            glow(filled.insetBy(dx: 0, dy: -0.5), colour: accent, radius: 7, opacity: Palette.isDark ? 0.9 : 0.35)
            glow(filled, colour: accent, radius: 3, opacity: Palette.isDark ? 0.7 : 0.3)
            fill(filled, colour: accent)
            fill(NSRect(x: filled.minX, y: centerY - 0.65, width: filled.width, height: 1.3),
                 colour: coreColour(amount: 0.3))
        case .laser:
            let beam = NSRect(x: filled.minX, y: centerY - 0.9, width: filled.width, height: 1.8)
            glow(beam, colour: accent, radius: 4, opacity: Palette.isDark ? 0.8 : 0.3)
            fill(beam, colour: accent)
            fill(NSRect(x: beam.minX, y: centerY - 0.35, width: beam.width, height: 0.7),
                 colour: coreColour(amount: 0.85))
        }
    }

    override func drawKnob(_ knobRect: NSRect) {
        guard Palette.sliderEffect != .none else { super.drawKnob(knobRect); return }
        let style = Palette.sliderEffect
        let center = NSPoint(x: knobRect.midX, y: knobRect.midY)
        let accent = isEnabled ? Palette.accent : Palette.secondary.withAlphaComponent(0.6)

        if style == .laser {
            let marker = NSRect(x: center.x - 1.25, y: center.y - 6, width: 2.5, height: 12)
            if isEnabled { glow(marker, colour: accent, radius: 5, opacity: Palette.isDark ? 0.8 : 0.3) }
            fill(marker, colour: accent)
            fill(NSRect(x: center.x - 0.4, y: center.y - 4.5, width: 0.8, height: 9),
                 colour: isEnabled ? coreColour(amount: 0.8) : Palette.background)
            return
        }

        let diameter: CGFloat = style == .glowy ? 10 : 9
        let dot = NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        if isEnabled { glow(dot, colour: accent, radius: style == .glowy ? 6 : 3, opacity: Palette.isDark ? 0.9 : 0.3) }
        fill(dot, colour: accent)
        let core = dot.insetBy(dx: style == .glowy ? 2.6 : 2.3, dy: style == .glowy ? 2.6 : 2.3)
        fill(core, colour: isEnabled ? coreColour(amount: 0.9) : Palette.background)
    }

    private func coreColour(amount: CGFloat) -> NSColor {
        // A dark accent stays legible on a light surface; a white-hot core lights the dark surface.
        Palette.isDark ? (Palette.accent.blended(withFraction: amount, of: .white) ?? .white) : Palette.accent
    }
    private func fill(_ rect: NSRect, colour: NSColor) {
        colour.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
    }
    private func glow(_ rect: NSRect, colour: NSColor, radius: CGFloat, opacity: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = colour.withAlphaComponent(opacity)
        shadow.shadowBlurRadius = radius
        shadow.shadowOffset = .zero
        shadow.set()
        fill(rect, colour: colour.withAlphaComponent(opacity))
        NSGraphicsContext.restoreGraphicsState()
    }
}
