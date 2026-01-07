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

		let (assetTracks, duration) = try await asset.load(.tracks, .duration)

		guard let assetTrack = assetTracks.first else {
			throw Error.assetHasNoTracks
		}

		let (trackSize, frameDuration, preferredTransform) = try await assetTrack.load(.naturalSize, .minFrameDuration, .preferredTransform)

		guard
			let compositionOriginalTrack = addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
		else {
			throw Error.couldNotCreateTracks
		}
		compositionOriginalTrack.preferredTransform = preferredTransform

		try compositionOriginalTrack.insertTimeRange(
			CMTimeRange(start: .videoZero, duration: duration),
			of: assetTrack,
			at: .videoZero
		)

		// Render size in preferred space (rotated) so preview displays correctly.
		let rotatedRect = CGRect(origin: .zero, size: trackSize).applying(preferredTransform)
		let renderSize = CGSize(width: abs(rotatedRect.width), height: abs(rotatedRect.height))
		let timeRange = CMTimeRange(start: .videoZero, duration: duration)

		let layerConfig = AVVideoCompositionLayerInstruction.Configuration(assetTrack: compositionOriginalTrack)
		let instructionConfig = AVVideoCompositionInstruction.Configuration(
			layerInstructions: [AVVideoCompositionLayerInstruction(configuration: layerConfig)],
			timeRange: timeRange
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
