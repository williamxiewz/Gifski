import SwiftUI

struct SettingsScreen: View {
	@Default(.autoSaveToDownloads) private var isAutoSaveToDownloadsEnabled

	var body: some View {
		Form {
			Section {
				Toggle("Automatically save GIFs to Downloads", isOn: $isAutoSaveToDownloadsEnabled)
			}
		}
		.padding(20)
		.frame(width: 420)
	}
}
