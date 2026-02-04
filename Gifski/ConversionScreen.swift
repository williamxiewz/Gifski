import SwiftUI
import AVFoundation
import DockProgress

struct ConversionScreen: View {
	@Environment(\.dismiss) private var dismiss
	@Environment(AppState.self) private var appState
	@Default(.autoSaveToDownloads) private var isAutoSaveToDownloadsEnabled
	@State private var progress = 0.0
	@State private var timeRemaining: String?
	@State private var startInstant: ContinuousClock.Instant?
	@State private var timeRemainingEstimator = TimeRemainingEstimator()
	private let clock = ContinuousClock()

	let conversion: GIFGenerator.Conversion

	var body: some View {
		VStack {
			ProgressView(value: progress)
				.progressViewStyle(
					.ssCircular(
						fill: LinearGradient(
							gradient: .init(
								colors: [
									.purple,
									.pink,
									.orange
								]
							),
							startPoint: .top,
							endPoint: .bottom
						),
						lineWidth: 30,
						text: "Converting"
					)
				)
				.frame(width: 300, height: 300)
				.overlay {
					Group {
						if let timeRemaining {
							Text(timeRemaining)
								.font(.subheadline)
								.monospacedDigit()
								.opacity(timeRemainingOpacity)
								.offset(y: 24)
								.animation(.easeOut(duration: 0.2), value: timeRemainingOpacity)
						}
					}
					.animation(.default, value: timeRemaining == nil)
				}
				.offset(y: -16) // Makes it centered (needed because of toolbar).
		}
		.fillFrame()
		.onKeyboardShortcut(.escape, modifiers: []) {
			dismiss()
		}
		.navigationTitle("")
		.task(priority: .utility) {
			do {
				try await convert()
			} catch {
				guard !error.isCancelled else {
					return
				}

				print("Conversion error:", error)
				appState.error = error
				dismiss()
			}
		}
		.activity(options: .userInitiated, reason: "Converting")
	}

	func convert() async throws {
		await MainActor.run {
			startInstant = clock.now
			timeRemainingEstimator = .init()
			timeRemaining = nil
		}

		defer {
			Task { @MainActor in
				timeRemaining = nil
				DockProgress.resetProgress()
			}
		}

		let data = try await GIFGenerator.run(conversion) { progress in
			Task { @MainActor in
				self.progress = progress
				updateEstimatedTimeRemaining(for: progress)
				DockProgress.progress = progress
			}
		}

		try Task.checkCancellation()

		let filename = conversion.sourceURL.filenameWithoutExtension
		let url = try data.writeToUniqueTemporaryFile(filename: filename, contentType: .gif)
		autoSaveToDownloadsIfNeeded(data, filename: filename)
		try? url.setAppAsItemCreator()

		try await Task.sleep(for: .seconds(1)) // Let the progress circle finish.

		// TODO: Support task cancellation.
		// TODO: Make sure it deinits too.

//		appState.navigationPath.removeLast()
//		appState.navigationPath.append(.completed(data))

		// This works around some race issue where it would sometimes end up with edit screen after conversion.
		var path = appState.navigationPath
		path.removeLast()
		path.append(.completed(data, url))
		appState.navigationPath = path
	}

	private func autoSaveToDownloadsIfNeeded(_ data: Data, filename: String) {
		guard isAutoSaveToDownloadsEnabled else {
			return
		}

		do {
			_ = try data.writeToUniqueFile(in: .downloadsDirectory, filename: filename, contentType: .gif)
		} catch {
			appState.error = error
		}
	}

	@MainActor
	private func updateEstimatedTimeRemaining(for progress: Double) {
		guard
			let startInstant
		else {
			timeRemaining = nil
			return
		}

		let now = clock.now
		let update = timeRemainingEstimator.updateDisplay(
			progress: progress,
			startInstant: startInstant,
			now: now
		)

		switch update {
		case .hide:
			timeRemaining = nil
		case .show(let remaining):
			let usesSeconds = timeRemainingEstimator.usesSeconds(for: remaining)
			let allowedUnits: Set<Duration.UnitsFormatStyle.Unit> = usesSeconds ? [.seconds] : [.hours, .minutes]
			let maximumUnitCount = usesSeconds ? 1 : 2
			let formatStyle: Duration.UnitsFormatStyle = .units(
				allowed: allowedUnits,
				width: .wide,
				maximumUnitCount: maximumUnitCount
			)
			let formatted = remaining.formatted(formatStyle)
			timeRemaining = "About \(formatted) remaining"
		case .noChange:
			break
		}
	}

	private var timeRemainingOpacity: Double {
		// Fade out the estimate near completion to avoid abrupt disappearance.
		let fadeStart = 0.95
		let fadeProgress = ((progress - fadeStart) / (1 - fadeStart)).clamped(to: 0...1)
		return 1 - fadeProgress
	}
}

struct TimeRemainingEstimator {
	enum Update {
		case hide
		case show(Duration)
		case noChange
	}

	private let smoothingFactor: Double
	private let minimumSampleInterval: Duration
	private let minimumUpdateInterval: Duration
	private let secondsStep: Duration
	private let secondsDisplayThreshold: Duration
	private let bufferDuration: Duration
	private let skipThreshold: Duration
	private var lastSample: (progress: Double, instant: ContinuousClock.Instant)?
	private var smoothedSpeed: Double?
	private var lastPresentation: (remaining: Duration, instant: ContinuousClock.Instant)?

	init(
		smoothingFactor: Double = 0.3,
		minimumSampleInterval: Duration = .seconds(0.2),
		minimumUpdateInterval: Duration = .seconds(5),
		secondsStep: Duration = .seconds(10),
		secondsDisplayThreshold: Duration = .seconds(60),
		bufferDuration: Duration = .seconds(3),
		skipThreshold: Duration = .seconds(10)
	) {
		self.smoothingFactor = smoothingFactor.clamped(to: 0...1)
		self.minimumSampleInterval = max(.zero, minimumSampleInterval)
		self.minimumUpdateInterval = max(.zero, minimumUpdateInterval)
		self.secondsStep = max(.seconds(1), secondsStep)
		self.secondsDisplayThreshold = max(.seconds(60), secondsDisplayThreshold)
		self.bufferDuration = max(.zero, bufferDuration)
		self.skipThreshold = max(.zero, skipThreshold)
	}

	/**
	Updates the estimator with a progress sample and returns the raw remaining duration.
	*/
	mutating func update(progress: Double, instant: ContinuousClock.Instant) -> Duration? {
		if let lastSample {
			let progressDelta = progress - lastSample.progress
			let timeDelta = lastSample.instant.duration(to: instant)

			if progressDelta > 0, timeDelta >= minimumSampleInterval {
				let instantaneousSpeed = progressDelta / Self.seconds(from: timeDelta)
				smoothedSpeed = smoothedSpeed.map {
					(smoothingFactor * instantaneousSpeed) + ((1 - smoothingFactor) * $0)
				} ?? instantaneousSpeed

				self.lastSample = (progress, instant)
			} else if progressDelta <= 0 || timeDelta <= .zero {
				self.lastSample = (progress, instant)
			}
		} else {
			lastSample = (progress, instant)
		}

		guard
			let smoothedSpeed,
			smoothedSpeed > 0
		else {
			return nil
		}

		let remainingProgress = 1 - progress
		guard remainingProgress > 0 else {
			return .zero
		}

		return .seconds(remainingProgress / smoothedSpeed)
	}

	/**
	Returns the next display update decision for the current progress sample.
	*/
	mutating func updateDisplay(
		progress: Double,
		startInstant: ContinuousClock.Instant,
		now: ContinuousClock.Instant
	) -> Update {
		if progress >= 1 {
			resetPresentation()
			return .hide
		}

		guard let remaining = update(progress: progress, instant: now) else {
			return lastPresentation == nil ? .hide : .noChange
		}

		guard remaining > .zero else {
			return lastPresentation == nil ? .hide : .noChange
		}

		if lastPresentation == nil {
			let elapsed = max(.zero, startInstant.duration(to: now))
			let total = elapsed + remaining

			guard
				elapsed > bufferDuration,
				total > skipThreshold
			else {
				return .hide
			}
		}

		guard let presentedRemaining = updatePresentation(remaining: remaining, now: now) else {
			return .noChange
		}

		return .show(presentedRemaining)
	}

	/**
	Quantizes and throttles display updates for a remaining duration.
	*/
	mutating func updatePresentation(
		remaining: Duration,
		now: ContinuousClock.Instant
	) -> Duration? {
		let quantizedRemaining = Self.quantizedRemaining(
			remaining: remaining,
			secondsStep: secondsStep,
			secondsDisplayThreshold: secondsDisplayThreshold
		)

		if let lastPresentation, quantizedRemaining > lastPresentation.remaining {
			return nil
		}

		if let lastPresentation {
			let wasSeconds = lastPresentation.remaining < secondsDisplayThreshold
			let isSeconds = quantizedRemaining < secondsDisplayThreshold
			let styleChanged = wasSeconds != isSeconds
			if !styleChanged, lastPresentation.instant.duration(to: now) < minimumUpdateInterval {
				return nil
			}

			guard styleChanged || quantizedRemaining != lastPresentation.remaining else {
				return nil
			}
		}

		lastPresentation = (quantizedRemaining, now)

		return quantizedRemaining
	}

	/**
	Returns whether the remaining duration should be displayed using seconds.
	*/
	func usesSeconds(for remaining: Duration) -> Bool {
		remaining < secondsDisplayThreshold
	}

	/**
	Quantizes a remaining duration into a stable display value.
	*/
	static func quantizedRemaining(
		remaining: Duration,
		secondsStep: Duration,
		secondsDisplayThreshold: Duration
	) -> Duration {
		let remainingSeconds = max(0, Self.seconds(from: remaining))
		let thresholdSeconds = max(1, Self.seconds(from: secondsDisplayThreshold))

		if remainingSeconds >= thresholdSeconds {
			let minutes = max(1, Int(remainingSeconds / 60))
			return .seconds(Double(minutes * 60))
		}

		let stepSeconds = max(1, Self.seconds(from: secondsStep))
		let quantizedSeconds = (remainingSeconds / stepSeconds).rounded(.down) * stepSeconds
		let clampedSeconds = max(stepSeconds, quantizedSeconds)
		let cappedSeconds = min(clampedSeconds, thresholdSeconds - 1)
		return .seconds(cappedSeconds)
	}

	private static func seconds(from duration: Duration) -> Double {
		Double(duration.nanoseconds) / 1_000_000_000
	}

	private mutating func resetPresentation() {
		lastPresentation = nil
	}
}
