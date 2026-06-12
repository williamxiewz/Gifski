import SwiftUI
import CoreTransferable
import AVFoundation

enum Constants {
	static let allowedFrameRate = 3.0...50.0
	static let loopCountRange = 0...100
}

extension Defaults.Keys {
	static let outputQuality = Key<Double>("outputQuality", default: 1)
	static let outputSpeed = Key<Double>("outputSpeed", default: 1)
	static let outputFPS = Key<Int>("outputFPS", default: 10)
	static let loopGIF = Key<Bool>("loopGif", default: true)
	static let bounceGIF = Key<Bool>("bounceGif", default: false)
	static let loopDelay = Key<Double>("loopDelay", default: 0)
	static let suppressKeyframeWarning = Key<Bool>("suppressKeyframeWarning", default: false)
	static let suppressLargeGIFWarning = Key<Bool>("suppressLargeGIFWarning", default: false)
	static let autoSaveToDownloads = Key<Bool>("autoSaveToDownloads", default: false)
}

enum Route: Hashable {
	case edit(URL, AVAsset, AVAsset.VideoMetadata)
	case conversion(GIFGenerator.Conversion)
	case completed(Data, URL, sourceURL: URL)
}

struct ExportableGIF: Transferable {
	let url: URL

	static var transferRepresentation: some TransferRepresentation {
		FileRepresentation(exportedContentType: .gif) { .init($0.url) }
			// TODO: Does not work when using `.fileExporter`. (macOS 14.3)
			.suggestedFileName { $0.url.filename }
	}
}
