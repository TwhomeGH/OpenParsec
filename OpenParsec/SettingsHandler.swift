import Foundation
import SwiftUI

enum RemoteTextInputMode: Int
{
	case keycodeOnly
	case linuxUnicode
	case macUnicodeHex
	case windowsHexNumpad
}

final class SettingsHandler: ObservableObject {
	// 全局配置中軀
	static let shared = SettingsHandler()   // 單例，全局共用

	private init() {
		// Initialize C logging flag to current setting
		set_logging_enabled(enableLogging)
	}


	@AppStorage("renderer") public var renderer: RendererType = .opengl

	@AppStorage("resolution") public var resolution: ParsecResolution = .client
	@AppStorage("bitrate") public var bitrate: Int = 0
	@AppStorage("decoder") public var decoder: DecoderPref = .h264
	@AppStorage("decoder444") public var decoder444: Bool = true

	@AppStorage("decoderCompatibility") public var decoderCompatibility: Bool = false // Enable for stutter issues on some devices
	@AppStorage("preferredFramesPerSecond") public var preferredFramesPerSecond: Int = 60 // 0 = use device max (ProMotion)
	
	@AppStorage("cursorMode") public var cursorMode: CursorMode = .touchpad
	@AppStorage("cursorScale") public var cursorScale: Double = 0.5
	@AppStorage("rightClickPosition") public var rightClickPosition: RightClickPosition = .firstFinger
	
	@AppStorage("hideStatusBar") public var hideStatusBar: Bool = true
	

	@AppStorage("mouseSensitivity") public var mouseSensitivity: Double = 1.0
	@AppStorage("noOverlay") public var noOverlay: Bool = false

	@AppStorage("showKeyboardButton") public var showKeyboardButton: Bool = true
	@AppStorage("remoteTextInputMode") public var remoteTextInputMode: RemoteTextInputMode = .keycodeOnly
	@AppStorage("enableLogging") public var enableLogging: Bool = true

	// 識別是不是Metal分辨用的文本
	@AppStorage("MetalText") public var MetalText: Bool = false

	@AppStorage("savedConstantFps") public var savedConstantFps: Bool = false
	@AppStorage("savedMuted") public var savedMuted: Bool = false
	@AppStorage("savedZoom") public var savedZoom: Bool = false



}
