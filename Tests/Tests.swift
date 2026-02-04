import CoreGraphics
import Testing
import UniformTypeIdentifiers
@testable import Gifski

struct Tests {
	private func instant(afterSeconds seconds: Double, from startInstant: ContinuousClock.Instant) -> ContinuousClock.Instant {
		startInstant.advanced(by: .seconds(seconds))
	}

	private func seconds(_ duration: Duration) -> Double {
		Double(duration.nanoseconds) / 1_000_000_000
	}

	private func updateAndRequire(
		_ estimator: inout TimeRemainingEstimator,
		progress: Double,
		instant: ContinuousClock.Instant
	) throws -> Duration {
		let timeRemaining = estimator.update(progress: progress, instant: instant)
		return try #require(timeRemaining)
	}

	@Test
	func timeRemainingEstimatorReturnsNilUntilProgressAdvances() async throws {
		var estimator = TimeRemainingEstimator(smoothingFactor: 0.5)
		let startInstant = ContinuousClock().now

		#expect(estimator.update(progress: 0.1, instant: instant(afterSeconds: 0, from: startInstant)) == nil)
		#expect(estimator.update(progress: 0.1, instant: instant(afterSeconds: 1, from: startInstant)) == nil)

		let timeRemaining = try updateAndRequire(&estimator, progress: 0.2, instant: instant(afterSeconds: 2, from: startInstant))
		#expect(timeRemaining > .zero)
	}

	@Test
	func timeRemainingEstimatorUsesExponentialSmoothing() async throws {
		var estimator = TimeRemainingEstimator(smoothingFactor: 0.5)
		let startInstant = ContinuousClock().now

		_ = estimator.update(progress: 0.1, instant: instant(afterSeconds: 0, from: startInstant))
		_ = estimator.update(progress: 0.3, instant: instant(afterSeconds: 2, from: startInstant))

		let timeRemaining = try updateAndRequire(&estimator, progress: 0.4, instant: instant(afterSeconds: 4, from: startInstant))

		let expectedTimeRemaining = 8.0
		let difference = abs(seconds(timeRemaining) - expectedTimeRemaining)
		#expect(difference < 0.0001)
	}

	@Test
	func timeRemainingEstimatorIgnoresZeroTimeDeltaForSpeedUpdates() async throws {
		var estimator = TimeRemainingEstimator(smoothingFactor: 1)
		let startInstant = ContinuousClock().now

		_ = estimator.update(progress: 0.1, instant: instant(afterSeconds: 0, from: startInstant))
		let baselineRemaining = try updateAndRequire(&estimator, progress: 0.2, instant: instant(afterSeconds: 2, from: startInstant))

		let unchangedTimeRemaining = try updateAndRequire(&estimator, progress: 0.3, instant: instant(afterSeconds: 2, from: startInstant))
		let unchangedDifference = abs(seconds(unchangedTimeRemaining) - 14.0)
		#expect(unchangedDifference < 0.0001)

		let laterTimeRemaining = try updateAndRequire(&estimator, progress: 0.4, instant: instant(afterSeconds: 4, from: startInstant))
		#expect(laterTimeRemaining < baselineRemaining)
	}

	@Test
	func timeRemainingEstimatorUsesInstantaneousSpeedWhenSmoothingFactorIsOne() async throws {
		var estimator = TimeRemainingEstimator(smoothingFactor: 1)
		let startInstant = ContinuousClock().now

		_ = estimator.update(progress: 0.1, instant: instant(afterSeconds: 0, from: startInstant))
		_ = estimator.update(progress: 0.2, instant: instant(afterSeconds: 2, from: startInstant))

		let timeRemaining = try updateAndRequire(&estimator, progress: 0.4, instant: instant(afterSeconds: 3, from: startInstant))

		let expectedTimeRemaining = 3.0
		let difference = abs(seconds(timeRemaining) - expectedTimeRemaining)
		#expect(difference < 0.0001)
	}

	@Test
	func timeRemainingEstimatorReturnsZeroAtCompletion() async throws {
		var estimator = TimeRemainingEstimator(smoothingFactor: 0.5)
		let startInstant = ContinuousClock().now

		_ = estimator.update(progress: 0.1, instant: instant(afterSeconds: 0, from: startInstant))
		_ = estimator.update(progress: 0.2, instant: instant(afterSeconds: 2, from: startInstant))

		let timeRemaining = try updateAndRequire(&estimator, progress: 1, instant: instant(afterSeconds: 4, from: startInstant))
		#expect(timeRemaining == .zero)
	}

	@Test
	func timeRemainingEstimatorHandlesRegressingProgress() async throws {
		var estimator = TimeRemainingEstimator(smoothingFactor: 1)
		let startInstant = ContinuousClock().now

		_ = estimator.update(progress: 0.1, instant: instant(afterSeconds: 0, from: startInstant))
		let baselineRemaining = try updateAndRequire(&estimator, progress: 0.2, instant: instant(afterSeconds: 2, from: startInstant))

		let regressedRemaining = try updateAndRequire(&estimator, progress: 0.15, instant: instant(afterSeconds: 3, from: startInstant))
		#expect(regressedRemaining > baselineRemaining)
	}

	@Test
	func timeRemainingEstimatorDecreasesWithConstantSpeed() async throws {
		var estimator = TimeRemainingEstimator(smoothingFactor: 1)
		let startInstant = ContinuousClock().now

		_ = estimator.update(progress: 0.1, instant: instant(afterSeconds: 0, from: startInstant))
		let firstRemaining = try updateAndRequire(&estimator, progress: 0.2, instant: instant(afterSeconds: 2, from: startInstant))
		let secondRemaining = try updateAndRequire(&estimator, progress: 0.3, instant: instant(afterSeconds: 4, from: startInstant))
		let thirdRemaining = try updateAndRequire(&estimator, progress: 0.4, instant: instant(afterSeconds: 6, from: startInstant))

		#expect(secondRemaining < firstRemaining)
		#expect(thirdRemaining < secondRemaining)
	}

	@Test
	func timeRemainingEstimatorIgnoresSamplesBelowMinimumInterval() async throws {
		var estimator = TimeRemainingEstimator(
			smoothingFactor: 1,
			minimumSampleInterval: .seconds(1)
		)
		let startInstant = ContinuousClock().now

		_ = estimator.update(progress: 0.1, instant: instant(afterSeconds: 0, from: startInstant))
		#expect(estimator.update(progress: 0.2, instant: instant(afterSeconds: 0.5, from: startInstant)) == nil)

		let timeRemaining = try updateAndRequire(&estimator, progress: 0.3, instant: instant(afterSeconds: 1.5, from: startInstant))

		let expectedTimeRemaining = 5.25
		let difference = abs(seconds(timeRemaining) - expectedTimeRemaining)
		#expect(difference < 0.0001)
	}

	@Test
	func timeRemainingEstimatorQuantizesSeconds() async throws {
		let quantizedRemaining = TimeRemainingEstimator.quantizedRemaining(
			remaining: .seconds(41),
			secondsStep: .seconds(10),
			secondsDisplayThreshold: .seconds(60)
		)

		#expect(quantizedRemaining == .seconds(40))
	}

	@Test
	func timeRemainingEstimatorClampsSubStepSeconds() async throws {
		let quantizedRemaining = TimeRemainingEstimator.quantizedRemaining(
			remaining: .seconds(7),
			secondsStep: .seconds(10),
			secondsDisplayThreshold: .seconds(60)
		)

		#expect(quantizedRemaining == .seconds(10))
	}

	@Test
	func timeRemainingEstimatorQuantizesMinutesAboveThreshold() async throws {
		let quantizedRemaining = TimeRemainingEstimator.quantizedRemaining(
			remaining: .seconds(80),
			secondsStep: .seconds(10),
			secondsDisplayThreshold: .seconds(60)
		)

		#expect(quantizedRemaining == .seconds(60))
	}

	@Test
	func timeRemainingEstimatorThrottlesUpdates() async throws {
		var estimator = TimeRemainingEstimator(
			minimumUpdateInterval: .seconds(5),
			secondsStep: .seconds(10),
			secondsDisplayThreshold: .seconds(60)
		)
		let startInstant = ContinuousClock().now

		let firstUpdate = estimator.updatePresentation(
			remaining: .seconds(50),
			now: instant(afterSeconds: 0, from: startInstant)
		)
		#expect(firstUpdate == .seconds(50))

		let secondUpdate = estimator.updatePresentation(
			remaining: .seconds(40),
			now: instant(afterSeconds: 2, from: startInstant)
		)
		#expect(secondUpdate == nil)

		let thirdUpdate = estimator.updatePresentation(
			remaining: .seconds(40),
			now: instant(afterSeconds: 6, from: startInstant)
		)
		#expect(thirdUpdate == .seconds(40))
	}

	@Test
	func timeRemainingEstimatorDoesNotIncreasePresentedRemaining() async throws {
		var estimator = TimeRemainingEstimator(
			minimumUpdateInterval: .zero,
			secondsStep: .seconds(10),
			secondsDisplayThreshold: .seconds(60)
		)
		let startInstant = ContinuousClock().now

		let firstUpdate = estimator.updatePresentation(
			remaining: .seconds(40),
			now: instant(afterSeconds: 0, from: startInstant)
		)
		#expect(firstUpdate == .seconds(40))

		let increasedUpdate = estimator.updatePresentation(
			remaining: .seconds(50),
			now: instant(afterSeconds: 1, from: startInstant)
		)
		#expect(increasedUpdate == nil)

		let decreasedUpdate = estimator.updatePresentation(
			remaining: .seconds(30),
			now: instant(afterSeconds: 2, from: startInstant)
		)
		#expect(decreasedUpdate == .seconds(30))
	}

	@Test
	func timeRemainingEstimatorUpdatesWhenSecondsStyleChanges() async throws {
		var estimator = TimeRemainingEstimator(
			minimumUpdateInterval: .seconds(5),
			secondsStep: .seconds(10),
			secondsDisplayThreshold: .seconds(60)
		)
		let startInstant = ContinuousClock().now

		let firstUpdate = estimator.updatePresentation(
			remaining: .seconds(61),
			now: instant(afterSeconds: 0, from: startInstant)
		)
		#expect(firstUpdate == .seconds(60))

		let secondUpdate = estimator.updatePresentation(
			remaining: .seconds(49),
			now: instant(afterSeconds: 1, from: startInstant)
		)
		#expect(secondUpdate == .seconds(40))
	}

	@Test
	func timeRemainingEstimatorShowsMinutesAtThreshold() async throws {
		var estimator = TimeRemainingEstimator(
			minimumUpdateInterval: .zero,
			secondsStep: .seconds(10),
			secondsDisplayThreshold: .seconds(60)
		)
		let startInstant = ContinuousClock().now

		let update = estimator.updatePresentation(
			remaining: .seconds(59),
			now: instant(afterSeconds: 0, from: startInstant)
		)

		#expect(update == .seconds(50))
	}

	@Test
	func percentFormattedMarksPixelDimensionsAsApproximate() async throws {
		let originalSize = CGSize(width: 1920, height: 1080)
		let pixelDimensions = Dimensions.pixels(CGSize(width: 800, height: 450), originalSize: originalSize)
		#expect(pixelDimensions.percentFormatted.hasPrefix("~"))

		let percentDimensions = Dimensions.percent(0.5, originalSize: originalSize)
		#expect(!percentDimensions.percentFormatted.hasPrefix("~"))
	}

	@Test
	func writeToUniqueFileAddsIncrementingSuffixes() async throws {
		let directory = try URL.uniqueTemporaryDirectory()
		defer {
			try? FileManager.default.removeItem(at: directory)
		}

		let data = Data("Test".utf8)
		let firstUrl = try data.writeToUniqueFile(in: directory, filename: "Sample", contentType: .gif)
		let secondUrl = try data.writeToUniqueFile(in: directory, filename: "Sample", contentType: .gif)

		#expect(firstUrl.lastPathComponent == "Sample.gif")
		#expect(secondUrl.lastPathComponent == "Sample 2.gif")
		#expect(firstUrl.exists)
		#expect(secondUrl.exists)
	}
}
