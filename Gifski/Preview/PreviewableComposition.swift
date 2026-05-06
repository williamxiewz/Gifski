import Foundation
import AVFoundation

/**
Adds `PreviewVideoCompositor` to a `AVComposition`, setting up the instructions and tracks.
*/
final class PreviewableComposition: AVMutableComposition {
	enum Error: Swift.Error {
		case assetHasNoTracks
		case couldNotCreateTracks
	}

	private(set) var videoComposition: AVVideoComposition!

	init(extractPreviewableCompositionFrom asset: AVAsset) async throws {
		super.init()

		guard let assetTrack = try await asset.firstVideoTrack else {
			throw Error.assetHasNoTracks
		}

		let (trackSize, frameDuration, preferredTransform, timeRange) = try await assetTrack.load(.naturalSize, .minFrameDuration, .preferredTransform, .timeRange)

		guard
			let compositionOriginalTrack = addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
		else {
			throw Error.couldNotCreateTracks
		}
		compositionOriginalTrack.preferredTransform = preferredTransform

		// Insert the source track range at zero so preview playback, trimming, and full-preview indexing all use the same normalized timeline.
		try compositionOriginalTrack.insertTimeRange(
			timeRange,
			of: assetTrack,
			at: .videoZero
		)

		// Render size in preferred space (rotated) so preview displays correctly.
		let rotatedRect = CGRect(origin: .zero, size: trackSize).applying(preferredTransform)
		let renderSize = CGSize(width: abs(rotatedRect.width), height: abs(rotatedRect.height))
		let instructionTimeRange = CMTimeRange(start: .videoZero, duration: timeRange.duration)

		let layerConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: compositionOriginalTrack)
		let instructionConfig = AVVideoCompositionInstruction.Configuration(
			layerInstructions: [AVVideoCompositionLayerInstruction(configuration: layerConfig)],
			timeRange: instructionTimeRange
		)
		let config = AVVideoComposition.Configuration(
			customVideoCompositorClass: PreviewVideoCompositor.self,
			frameDuration: frameDuration,
			instructions: [AVVideoCompositionInstruction(configuration: instructionConfig)],
			renderSize: renderSize
		)
		videoComposition = AVVideoComposition(configuration: config)
	}
}
