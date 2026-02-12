import SwiftUI
import UserNotifications
import DockProgress

@MainActor
@Observable
final class AppState {
	static let shared = AppState()

	var isOnEditScreen: Bool {
		guard case .edit = navigationPath.last else {
			return false
		}

		return true
	}

	var isConverting: Bool {
		guard case .conversion = navigationPath.last else {
			return false
		}

		return true
	}

	var navigationPath = [Route]()
	var isFileImporterPresented = false

	enum Mode {
		case normal
		case editCrop
		case preview
	}

	var mode = Mode.normal

	var shouldShowPreview: Bool {
		mode == .preview
	}

	var isCropActive: Bool {
		mode == .editCrop
	}

	var onExportAsVideo: (() -> Void)?

	/**
	Provides a binding for a toggle button to access a certain mode.

	The getter returns true if in that mode. Setter will toggle the mode on, but return to initial mode if set to off (if we are in the specified mode).
	*/
	func toggleMode(mode: Mode) -> Binding<Bool> {
		.init(
			get: {
				self.mode == mode
			},
			set: { newValue in
				if newValue {
					self.mode = mode
					return
				}

				guard self.mode == mode else {
					return
				}

				self.mode = .normal
			}
		)
	}

	var error: Error?

	init() {
		DockProgress.style = .squircle(color: .white.opacity(0.7))

		DispatchQueue.main.async { [self] in
			didLaunch()
		}
	}

	private func didLaunch() {
		NSApp.servicesProvider = self

		// We have to include `.badge` otherwise system settings does not show the checkbox to turn off sounds. (macOS 12.4)
		UNUserNotificationCenter.current().requestAuthorization(options: [.sound, .badge]) { _, _ in }

		delay(.seconds(1)) {
			SSApp.runOnce(identifier: "firstLaunch-3-0-0") {
				guard !SSApp.isFirstLaunch else {
					return
				}

				NSAlert.showModal(
					for: NSApp.mainWindow,
					title: "Welcome to Gifski 3",
					message: "Gifski now supports cropping and preview.\n\nNote: Quick Look is no longer available after conversion. It was unreliable, and the preview window is now large enough on its own.\n\nKnown issue: Dragging from a Dock folder into the window may fail due to a macOS bug."
				)
			}
		}
	}

	func start(_ url: URL) {
		// We intentionally do not call `stop` on this one later for simplicity since we will never get a lot of files.
		_ = url.startAccessingSecurityScopedResource()

		// We have to nil it out first and dispatch, otherwise it shows the old video. (macOS 14.3)
		navigationPath = []

		// Reset mode to prevent the new EditScreen from inheriting preview/crop state.
		mode = .normal

		Task { [self] in
			do {
				// TODO: Simplify the validator.
				let (asset, metadata) = try await VideoValidator.validate(url)
				navigationPath = [.edit(url, asset, metadata)]
			} catch {
				self.error = error
			}
		}
	}

	/**
	Returns `nil` if it should not continue.
	*/
	fileprivate func extractSharedVideoUrlIfAny(from url: URL) -> URL? {
		guard url.host == "shareExtension" else {
			return url
		}

		guard
			let path = url.queryDictionary["path"],
			let appGroupShareVideoUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Shared.appGroupIdentifier)?.appendingPathComponent(path, isDirectory: false)
		else {
			NSAlert.showModal(
				for: SSApp.swiftUIMainWindow,
				title: "Could not retrieve the shared video."
			)
			return nil
		}

		return appGroupShareVideoUrl
	}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
	func applicationDidFinishLaunching(_ notification: Notification) {
		// Set launch completions option if the notification center could not be set up already.
		LaunchCompletions.applicationDidLaunch()
	}

	// Using AppDelegate instead of `.onOpenURL` because we need to handle multiple URLs at once to reject multi-file drops with a user-friendly error.
	func application(_ application: NSApplication, open urls: [URL]) {
		guard
			urls.count == 1,
			let videoUrl = urls.first
		else {
			NSAlert.showModal(
				for: SSApp.swiftUIMainWindow,
				title: "Gifski can only convert a single file at a time."
			)

			return
		}

		guard let videoUrl2 = AppState.shared.extractSharedVideoUrlIfAny(from: videoUrl) else {
			return
		}

		// Start video conversion on launch
		LaunchCompletions.add {
			AppState.shared.start(videoUrl2)
		}
	}

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		if AppState.shared.isConverting {
			let response = NSAlert.showModal(
				for: SSApp.swiftUIMainWindow,
				title: "Do you want to continue converting?",
				message: "Gifski is currently converting a video. If you quit, the conversion will be cancelled.",
				buttonTitles: [
					"Continue",
					"Quit"
				]
			)

			if response == .alertFirstButtonReturn {
				return .terminateCancel
			}
		}

		return .terminateNow
	}

	func applicationWillTerminate(_ notification: Notification) {
		UNUserNotificationCenter.current().removeAllDeliveredNotifications()
	}
}

extension AppState {
	/**
	This is called from NSApp as a service resolver.
	*/
	@objc
	func convertToGIF(_ pasteboard: NSPasteboard, userData: String, error: NSErrorPointer) {
		guard let url = pasteboard.fileURLs().first else {
			return
		}

		start(url)
	}
}
