import AppKit
import QuartzCore
import SwiftUI

@MainActor
struct NativePlayerPositionSlider: NSViewRepresentable {
    let timeMs: Double
    let receivedAtUptime: TimeInterval
    let durationMs: Double
    let isPlaying: Bool
    let canSeek: Bool
    let isScrubbing: Bool
    let scrubRatio: Double
    let resetRevision: Int
    var loopStartRatio: Double? = nil
    var loopEndRatio: Double? = nil
    var pointARatio: Double? = nil
    let help: String
    let onEditingChanged: (Bool) -> Void
    let onScrubChanged: (Double) -> Void
    let onSeek: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NativePositionSlider {
        let slider = NativePositionSlider(frame: .zero)
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.valueChanged(_:))
        slider.onEditingChanged = { [weak coordinator = context.coordinator] editing in
            coordinator?.onEditingChanged?(editing)
        }
        slider.onValueChanged = { [weak coordinator = context.coordinator] value, isTracking in
            if isTracking {
                coordinator?.onScrubChanged?(value)
            } else {
                coordinator?.onSeek?(value)
            }
        }
        return slider
    }

    func updateNSView(_ slider: NativePositionSlider, context: Context) {
        let coordinator = context.coordinator
        coordinator.onEditingChanged = onEditingChanged
        coordinator.onScrubChanged = onScrubChanged
        coordinator.onSeek = onSeek

        slider.isEnabled = canSeek
        slider.toolTip = help
        slider.setAccessibilityLabel("播放进度")
        slider.setAccessibilityHelp(help)
        slider.identifier = NSUserInterfaceItemIdentifier("MIMI.Player.Progress")

        slider.updatePlaybackPosition(
            timeMs: timeMs,
            receivedAtUptime: receivedAtUptime,
            durationMs: durationMs,
            isPlaying: isPlaying,
            isScrubbing: isScrubbing,
            scrubRatio: scrubRatio,
            resetRevision: resetRevision,
            loopStartRatio: loopStartRatio,
            loopEndRatio: loopEndRatio,
            pointARatio: pointARatio
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        var onEditingChanged: ((Bool) -> Void)?
        var onScrubChanged: ((Double) -> Void)?
        var onSeek: ((Double) -> Void)?

        @objc func valueChanged(_ sender: NativePositionSlider) {
            sender.updateVisualsForUserValue()
            sender.onValueChanged?(sender.normalizedValue, sender.isPositionTracking)
        }
    }
}

@MainActor
private final class NativePositionSliderCell: NSSliderCell {
    override func drawBar(inside aRect: NSRect, flipped: Bool) {}
    override func drawKnob(_ knobRect: NSRect) {}
}

@MainActor
final class NativePositionSlider: NSSlider {
    var onEditingChanged: ((Bool) -> Void)?
    var onValueChanged: ((Double, Bool) -> Void)?
    private(set) var isPositionTracking = false

    private let trackLayer = CAShapeLayer()
    private let loopRangeLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let markerALayer: CALayer
    private let markerBLayer: CALayer
    private let knobLayer = CALayer()

    private var currentLoopStartRatio: Double?
    private var currentLoopEndRatio: Double?
    private var currentPointARatio: Double?

    private var anchorTimeMs = 0.0
    private var anchorUptime: TimeInterval = 0
    private var positionDurationMs = 0.0
    private var positionIsPlaying = false
    private var currentScrubRatio = 0.0
    private var lastResetRevision: Int?
    private var lastLaidOutBounds: NSRect = .zero
    private var trackStartX: CGFloat = 0
    private var trackEndX: CGFloat = 0
    private var trackCenterY: CGFloat = 0
    private var trackIsReady = false

    override init(frame frameRect: NSRect) {
        markerALayer = Self.makeMarkerLayer(label: "A", color: NSColor(red: 0.88, green: 0.35, blue: 0.22, alpha: 1.0))
        markerBLayer = Self.makeMarkerLayer(label: "B", color: NSColor(red: 0.88, green: 0.35, blue: 0.22, alpha: 1.0))
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        markerALayer = Self.makeMarkerLayer(label: "A", color: NSColor(red: 0.88, green: 0.35, blue: 0.22, alpha: 1.0))
        markerBLayer = Self.makeMarkerLayer(label: "B", color: NSColor(red: 0.88, green: 0.35, blue: 0.22, alpha: 1.0))
        super.init(coder: coder)
        configure()
    }

    private static func makeMarkerLayer(label: String, color: NSColor) -> CALayer {
        let container = CALayer()
        container.masksToBounds = false
        container.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "hidden": NSNull(),
            "opacity": NSNull()
        ]

        let needle = CALayer()
        needle.backgroundColor = color.cgColor
        needle.frame = CGRect(x: -1, y: -7, width: 2, height: 14)
        needle.cornerRadius = 1
        needle.actions = ["position": NSNull(), "bounds": NSNull()]
        container.addSublayer(needle)

        let badge = CALayer()
        badge.backgroundColor = color.cgColor
        badge.frame = CGRect(x: -7, y: -19, width: 14, height: 12)
        badge.cornerRadius = 3
        badge.masksToBounds = true
        badge.actions = ["position": NSNull(), "bounds": NSNull()]

        let text = CATextLayer()
        text.string = label
        text.font = NSFont.systemFont(ofSize: 8, weight: .bold)
        text.fontSize = 8
        text.foregroundColor = NSColor.white.cgColor
        text.alignmentMode = .center
        text.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        text.frame = CGRect(x: 0, y: 0.5, width: 14, height: 11)
        text.actions = ["contents": NSNull()]
        badge.addSublayer(text)

        container.addSublayer(badge)
        container.isHidden = true
        return container
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 24)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            super.mouseDown(with: event)
            return
        }
        isPositionTracking = true
        onEditingChanged?(true)
        super.mouseDown(with: event)
        isPositionTracking = false
        onEditingChanged?(false)
        onValueChanged?(normalizedValue, false)
    }

    override func layout() {
        super.layout()
        guard lastLaidOutBounds != bounds || !trackIsReady else { return }
        lastLaidOutBounds = bounds
        updateTrackGeometry()
        guard trackIsReady else { return }
        resetVisualsToCurrentAnchor()
        updateLoopVisuals(startRatio: currentLoopStartRatio, endRatio: currentLoopEndRatio, pointARatio: currentPointARatio)
    }

    var normalizedValue: Double {
        guard maxValue > minValue else { return 0 }
        return min(1, max(0, (doubleValue - minValue) / (maxValue - minValue)))
    }

    func updatePlaybackPosition(
        timeMs: Double,
        receivedAtUptime: TimeInterval,
        durationMs: Double,
        isPlaying: Bool,
        isScrubbing: Bool,
        scrubRatio: Double,
        resetRevision: Int,
        loopStartRatio: Double? = nil,
        loopEndRatio: Double? = nil,
        pointARatio: Double? = nil
    ) {
        let nextTime = timeMs.isFinite ? max(0, timeMs) : 0
        let nextDuration = durationMs.isFinite ? max(0, durationMs) : 0
        let nextUptime = receivedAtUptime.isFinite ? receivedAtUptime : ProcessInfo.processInfo.systemUptime
        let anchorChanged = nextUptime != anchorUptime || nextTime != anchorTimeMs
        let resetRequested = lastResetRevision != resetRevision
        let playbackChanged = positionIsPlaying != isPlaying
        let durationChanged = positionDurationMs != nextDuration

        anchorTimeMs = nextTime
        anchorUptime = nextUptime
        positionDurationMs = nextDuration
        positionIsPlaying = isPlaying
        let firstAnchor = lastResetRevision == nil
        lastResetRevision = resetRevision

        guard !isPositionTracking else { return }

        currentScrubRatio = min(1, max(0, scrubRatio.isFinite ? scrubRatio : 0))
        let liveRatio = ratio(at: ProcessInfo.processInfo.systemUptime)
        let value = isScrubbing ? currentScrubRatio : liveRatio
        if abs(normalizedValue - value) > 0.000_001 {
            doubleValue = minValue + (maxValue - minValue) * value
        }

        guard trackIsReady else {
            needsLayout = true
            return
        }

        if isScrubbing {
            setVisuals(to: currentScrubRatio)
        } else if firstAnchor || resetRequested || playbackChanged || durationChanged || !isPlaying {
            resetVisualsToCurrentAnchor()
        } else if anchorChanged {
            animateFromPresentationToEnd()
        }
        updateLoopVisuals(startRatio: loopStartRatio, endRatio: loopEndRatio, pointARatio: pointARatio)
    }

    func updateVisualsForUserValue() {
        let value = normalizedValue
        currentScrubRatio = value
        setVisuals(to: value)
    }

    func updateLoopVisuals(startRatio: Double? = nil, endRatio: Double? = nil, pointARatio: Double? = nil) {
        if startRatio != nil || endRatio != nil || pointARatio != nil || (startRatio == nil && endRatio == nil && pointARatio == nil && (currentLoopStartRatio != nil || currentPointARatio != nil)) {
            currentLoopStartRatio = startRatio
            currentLoopEndRatio = endRatio
            currentPointARatio = pointARatio
        }
        guard trackIsReady else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if let s = currentLoopStartRatio, let e = currentLoopEndRatio, s < e {
            let xA = positionX(for: s)
            let xB = positionX(for: e)

            let loopPath = CGMutablePath()
            loopPath.move(to: CGPoint(x: xA, y: trackCenterY))
            loopPath.addLine(to: CGPoint(x: xB, y: trackCenterY))
            loopRangeLayer.frame = bounds
            loopRangeLayer.path = loopPath
            let barH = (cell as? NSSliderCell)?.barRect(flipped: isFlipped).height ?? 3
            loopRangeLayer.lineWidth = max(4, barH + 1)
            loopRangeLayer.isHidden = false

            markerALayer.position = CGPoint(x: xA, y: trackCenterY)
            markerALayer.isHidden = false

            markerBLayer.position = CGPoint(x: xB, y: trackCenterY)
            markerBLayer.isHidden = false
        } else if let a = currentPointARatio {
            let xA = positionX(for: a)
            loopRangeLayer.isHidden = true

            markerALayer.position = CGPoint(x: xA, y: trackCenterY)
            markerALayer.isHidden = false

            markerBLayer.isHidden = true
        } else {
            loopRangeLayer.isHidden = true
            markerALayer.isHidden = true
            markerBLayer.isHidden = true
        }

        CATransaction.commit()
    }

    private func configure() {
        cell = NativePositionSliderCell()
        minValue = 0
        maxValue = 1
        isContinuous = true
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false

        trackLayer.fillColor = nil
        trackLayer.strokeColor = NSColor(MIMITheme.softBorder).cgColor
        trackLayer.lineCap = .round
        trackLayer.actions = ["path": NSNull(), "strokeEnd": NSNull()]

        loopRangeLayer.fillColor = nil
        loopRangeLayer.strokeColor = NSColor(red: 0.88, green: 0.35, blue: 0.22, alpha: 0.45).cgColor
        loopRangeLayer.lineCap = .round
        loopRangeLayer.actions = ["path": NSNull(), "strokeEnd": NSNull(), "hidden": NSNull()]
        loopRangeLayer.isHidden = true

        progressLayer.fillColor = nil
        progressLayer.strokeColor = NSColor(MIMITheme.terracotta).cgColor
        progressLayer.lineCap = .round
        progressLayer.actions = ["path": NSNull(), "strokeEnd": NSNull()]

        knobLayer.backgroundColor = NSColor.white.cgColor
        knobLayer.borderColor = NSColor(MIMITheme.softBorder).cgColor
        knobLayer.borderWidth = 1
        knobLayer.masksToBounds = true
        knobLayer.actions = ["position": NSNull(), "bounds": NSNull(), "cornerRadius": NSNull()]

        if let layer {
            layer.addSublayer(trackLayer)
            layer.addSublayer(loopRangeLayer)
            layer.addSublayer(progressLayer)
            layer.addSublayer(markerALayer)
            layer.addSublayer(markerBLayer)
            layer.addSublayer(knobLayer)
        }
    }

    private func updateTrackGeometry() {
        guard let sliderCell = cell as? NSSliderCell else { return }
        let currentValue = doubleValue
        doubleValue = minValue
        let minimumKnobRect = sliderCell.knobRect(flipped: isFlipped)
        doubleValue = maxValue
        let maximumKnobRect = sliderCell.knobRect(flipped: isFlipped)
        doubleValue = currentValue

        let barRect = sliderCell.barRect(flipped: isFlipped)
        guard !barRect.isEmpty, !minimumKnobRect.isEmpty, !maximumKnobRect.isEmpty else { return }
        trackStartX = minimumKnobRect.midX
        trackEndX = maximumKnobRect.midX
        trackCenterY = barRect.midY
        let path = CGMutablePath()
        path.move(to: CGPoint(x: trackStartX, y: trackCenterY))
        path.addLine(to: CGPoint(x: trackEndX, y: trackCenterY))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = bounds
        trackLayer.path = path
        trackLayer.lineWidth = max(2, barRect.height)
        progressLayer.frame = bounds
        progressLayer.path = path
        progressLayer.lineWidth = max(2, barRect.height)
        let knobRect = sliderCell.knobRect(flipped: isFlipped)
        knobLayer.bounds = CGRect(origin: .zero, size: knobRect.size)
        knobLayer.cornerRadius = min(knobRect.width, knobRect.height) / 2
        CATransaction.commit()
        trackIsReady = true
    }

    private func resetVisualsToCurrentAnchor() {
        guard trackIsReady else { return }
        let value = ratio(at: ProcessInfo.processInfo.systemUptime)
        removePositionAnimations()
        if positionIsPlaying, positionDurationMs > 0 {
            animate(fromRatio: value, fromKnobX: positionX(for: value), toEndAfter: remainingSeconds(at: ProcessInfo.processInfo.systemUptime))
        } else {
            setVisuals(to: value)
        }
    }

    private func animateFromPresentationToEnd() {
        guard positionIsPlaying, positionDurationMs > 0 else {
            resetVisualsToCurrentAnchor()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        let progress = (progressLayer.presentation()?.strokeEnd as? CGFloat) ?? progressLayer.strokeEnd
        let knobX = knobLayer.presentation()?.position.x ?? knobLayer.position.x
        removePositionAnimations()
        animate(fromRatio: Double(progress), fromKnobX: knobX, toEndAfter: remainingSeconds(at: now))
    }

    private func animate(fromRatio: Double, fromKnobX: CGFloat, toEndAfter duration: TimeInterval) {
        let endRatio = CGFloat(1)
        let endKnobX = positionX(for: 1)
        guard duration.isFinite, duration > 0.001 else {
            setVisuals(to: 1)
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = endRatio
        knobLayer.position = CGPoint(x: endKnobX, y: trackCenterY)
        CATransaction.commit()

        let progressAnimation = CABasicAnimation(keyPath: "strokeEnd")
        progressAnimation.fromValue = min(1, max(0, fromRatio))
        progressAnimation.toValue = endRatio
        progressAnimation.duration = duration
        progressAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
        progressLayer.add(progressAnimation, forKey: "playback-progress")

        let knobAnimation = CABasicAnimation(keyPath: "position.x")
        knobAnimation.fromValue = fromKnobX
        knobAnimation.toValue = endKnobX
        knobAnimation.duration = duration
        knobAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
        knobLayer.add(knobAnimation, forKey: "playback-knob")
    }

    private func setVisuals(to ratio: Double) {
        let value = CGFloat(min(1, max(0, ratio.isFinite ? ratio : 0)))
        removePositionAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = value
        knobLayer.position = CGPoint(x: positionX(for: Double(value)), y: trackCenterY)
        CATransaction.commit()
    }

    private func removePositionAnimations() {
        progressLayer.removeAnimation(forKey: "playback-progress")
        knobLayer.removeAnimation(forKey: "playback-knob")
    }

    private func positionX(for ratio: Double) -> CGFloat {
        trackStartX + (trackEndX - trackStartX) * CGFloat(min(1, max(0, ratio)))
    }

    private func ratio(at uptime: TimeInterval) -> Double {
        guard positionDurationMs > 0 else { return 0 }
        let elapsedMs = positionIsPlaying ? max(0, uptime - anchorUptime) * 1_000 : 0
        return min(1, max(0, (anchorTimeMs + elapsedMs) / positionDurationMs))
    }

    private func remainingSeconds(at uptime: TimeInterval) -> TimeInterval {
        let remainingMs = max(0, positionDurationMs - min(positionDurationMs, anchorTimeMs + (positionIsPlaying ? max(0, uptime - anchorUptime) * 1_000 : 0)))
        return remainingMs / 1_000
    }
}
