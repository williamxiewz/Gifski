import Foundation

final class TimeRemainingEstimator {
	private var progressCancellable: AnyCancellable?
	private var isCancelledCancellable: AnyCancellable?

	/**
	The delay before revealing the estimated time remaining, allowing the estimation to stabilize.
	*/
	let bufferDuration = Duration.seconds(3)

	/**
	Don't show the estimate at all if the total time estimate (after it stabilizes) is less than this amount.
	*/
	let skipThreshold = Duration.seconds(10)

	/**
	Begin fade out when remaining time reaches this amount.
	*/
	let fadeOutThreshold = Duration.seconds(1)

	weak var progress: Progress? {
		didSet {
			progressCancellable = progress?.publisher(for: \.fractionCompleted)
				.sink { [weak self] in
					guard let self else {
						return
					}

					percentComplete = $0
				}

			isCancelledCancellable = progress?.publisher(for: \.isCancelled)
				.sink { [weak self] in
					guard let self else {
						return
					}

					if $0 {
						state = .done
					}
				}
		}
	}

	init(label: Label) {
		self.label = label
	}

	func start() {
		state = .buffering
		startTime = Date()
	}

	// MARK: - Private

	private enum State {
		case buffering
		case running
		case done
	}

	private var state: State = .buffering {
		didSet {
			guard state != oldValue else {
				return
			}

			switch state {
			case .buffering:
				break
			case .running:
				fadeInLabel()
			case .done:
				fadeOutLabel()
			}
		}
	}

	private var nextState: State {
		switch state {
		case .buffering:
			if finishedBuffering {
				return shouldShowEstimation ? .running : .done
			}

			return .buffering
		case .running:
			return remaining < fadeOutThreshold ? .done : .running
		case .done:
			return .done
		}
	}

	private var finishedBuffering: Bool { elapsed > bufferDuration }
	private var shouldShowEstimation: Bool { remaining > skipThreshold }
	private var elapsed: Duration { .seconds(Date.now.timeIntervalSince(startTime)) }

	private var remaining: Duration {
		(elapsed / percentComplete) * (1 - percentComplete)
	}

	private let label: Label
	private var startTime = Date()

	private lazy var elapsedTimeFormatter = with(DateComponentsFormatter()) {
		$0.unitsStyle = .full
		$0.includesApproximationPhrase = true
		$0.includesTimeRemainingPhrase = true
	}

	private var formattedTimeRemaining: String? {
		let seconds = remaining.toTimeInterval.clamped(to: 1...)
		elapsedTimeFormatter.allowedUnits = seconds < 60 ? .second : [.hour, .minute]
		return elapsedTimeFormatter.string(from: seconds)
	}

	@Clamping(0.001...100) private var percentComplete = 0.0 {
		didSet {
			state = nextState
			updateLabel()
		}
	}

	private func fadeInLabel() {
		DispatchQueue.main.async { [self] in
			if label.isHidden {
				label.fadeIn()
			}
		}
	}

	private func fadeOutLabel() {
		DispatchQueue.main.async { [self] in
			if !label.isHidden {
				label.fadeOut()
			}
		}
	}

	private func updateLabel() {
		DispatchQueue.main.async { [self] in
			label.text = formattedTimeRemaining ?? ""
		}
	}
}
