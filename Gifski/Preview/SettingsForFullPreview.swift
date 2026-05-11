import Foundation
import CoreMedia
import AVFoundation

/**
When creating a full preview, you don't need some settings such as loop or bounce, plus it has additional info like asset duration and speed.
*/
struct SettingsForFullPreview: Equatable, Sendable {
	let conversion: SendableConversion
	let speed: Double
	let assetDuration: Duration
	let frameRate: Int

	init(
		conversion: GIFGenerator.Conversion,
		speed: Double,
		frameRate: Int,
		assetDuration: Duration
	) {
		self.speed = speed
		self.frameRate = frameRate
		self.assetDuration = assetDuration
		self.conversion = SendableConversion(conversion: conversion)
	}

	func areSettingsDifferentEnoughForANewFullPreview(
		newSettings: Self,
		areCurrentlyGenerating: Bool,
		oldRequestID: Int,
		newRequestID: Int
	) -> Bool {
		if self == newSettings {
			newRequestID.p("Skipping - Same as \(oldRequestID)")
			return false
		}

		if
			!areCurrentlyGenerating,
			hasSameReusablePreviewInputs(as: newSettings),
			timeRangeContainsTimeRange(of: newSettings)
		{
			// A completed preview for a wider time range can be reused by indexing into the already generated frame list.
			newRequestID.p("Skipping - Same as ready \(oldRequestID)")
			return false
		}

		newRequestID.p("Different than \(oldRequestID)")

		return true
	}

	/**
	Check if the settings for full preview are the same, ignoring settings that do not affect full preview.
	*/
	private func hasSameReusablePreviewInputs(as other: Self) -> Bool {
		speed == other.speed && conversion.settings == other.conversion.settings && assetDuration == other.assetDuration && frameRate == other.frameRate
	}

	/**
	Check if the time range of the new settings is a subset of the old settings.
	*/
	private func timeRangeContainsTimeRange(of newSettings: Self) -> Bool {
		guard let oldTimeRange = conversion.timeRange else {
			/**
			`nil` means the entire duration, so every trimmed range is a subset of the old preview.
			*/
			return true
		}

		guard let newTimeRange = newSettings.conversion.timeRange else {
			/**
			Old is not full, but new is full, thus it is not a subset.
			*/
			return false
		}

		return oldTimeRange.contains(newTimeRange)
	}

	struct SendableConversion: ReflectiveHashable, Sendable {
		let timeRange: ClosedRange<Double>?
		let settings: ConversionSettings

		var dimensions: (width: Int, height: Int)? {
			settings.dimensions
		}
		var trackPreferredTransform: CGAffineTransform? {
			settings.trackPreferredTransform
		}

		var crop: CropRect? {
			settings.crop
		}

		struct ConversionSettings: ReflectiveHashable, Sendable {
			let sourceURL: URL
			let quality: Double
			let dimensions: (width: Int, height: Int)?
			let crop: CropRect?
			let trackPreferredTransform: CGAffineTransform?

			var loop: Gifski.Loop {
				.never
			}

			var bounce: Bool {
				false
			}
		}

		init(conversion: GIFGenerator.Conversion) {
			self.timeRange = conversion.timeRange

			self.settings = .init(
				sourceURL: conversion.sourceURL,
				quality: conversion.quality,
				dimensions: conversion.dimensions,
				crop: conversion.crop,
				trackPreferredTransform: conversion.trackPreferredTransform
			)
		}

		func toConversion(
			asset: AVAsset,
			frameRate: Int
		) -> GIFGenerator.Conversion {
			.init(
				asset: asset,
				sourceURL: settings.sourceURL,
				timeRange: timeRange,
				quality: settings.quality,
				dimensions: settings.dimensions,
				frameRate: frameRate,
				loop: settings.loop,
				bounce: settings.bounce,
				crop: settings.crop,
				trackPreferredTransform: settings.trackPreferredTransform
			)
		}
	}
}
