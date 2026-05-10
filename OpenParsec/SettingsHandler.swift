import Foundation
import SwiftUI

final class SettingsHandler: ObservableObject {
	// 全局配置中軀

	@AppStorage("renderer") public static var renderer: RendererType = .opengl

	@AppStorage("resolution") public static var resolution: ParsecResolution = .client
	@AppStorage("bitrate") public static var bitrate: Int = 0
	@AppStorage("decoder") public static var decoder: DecoderPref = .h264
	@AppStorage("decoder444") public static var decoder444: Bool = true

	@AppStorage("decoderCompatibility") public static var decoderCompatibility: Bool = false // Enable for stutter issues on some devices
	@AppStorage("preferredFramesPerSecond") public static var preferredFramesPerSecond: Int = 60 // 0 = use device max (ProMotion)
	
	@AppStorage("cursorMode") public static var cursorMode: CursorMode = .touchpad
	@AppStorage("cursorScale") public static var cursorScale: Double = 0.5
	@AppStorage("rightClickPosition") public static var rightClickPosition: RightClickPosition = .firstFinger
	
	@AppStorage("hideStatusBar") public static var hideStatusBar: Bool = true
	

	@AppStorage("mouseSensitivity") public static var mouseSensitivity: Double = 1.0
	@AppStorage("noOverlay") public static var noOverlay: Bool = false


	@AppStorage("showKeyboardButton") public static var showKeyboardButton: Bool = true

}
