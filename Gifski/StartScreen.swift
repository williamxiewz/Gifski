import SwiftUI

struct StartScreen: View {
	@Environment(AppState.self) private var appState

	var body: some View {
		VStack(spacing: 8) {
			Text("Drop Video")
				.fontWeight(.medium)
			Text("or")
				.font(.system(size: 10))
				.italic()
			Button("Open") {
				appState.isFileImporterPresented = true
			}
			.buttonStyle(.glass)
		}
		.font(.title3)
		.controlSize(.extraLarge)
		.foregroundStyle(.secondary)
		.padding()
		.padding()
		.padding()
		.padding()
		.padding()
		.padding()
		.padding(.horizontal)
		.glassEffect(.clear, in: .rect(cornerRadius: 56))
		.fillFrame()
		.background {
			Image(.background)
				.resizable()
				.fillFrame()
				.opacity(0.3)
		}
		.offset(y: -32) // Toolbar height
		.navigationTitle("")
		// TODO: When targeting macOS 15, set `.containerShape()` at the top-level and then use `ContainerRelativeShape()` for the border.
		// TODO: Or do a `.windowBorder()` utility.
	}
}
