import ParsecSDK
import MetalKit
import UIKit
import OSLog


import Metal


enum RendererType: Int
{
	case opengl
    case metal
}

enum DecoderPref: Int
{
    case h264
    case h265
}

enum CursorMode: Int
{
    case touchpad
    case direct
}

enum RightClickPosition: Int
{
	case firstFinger
	case middle
	case secondFinger
}

struct KeyBoardKeyEvent {
	var input: UIKey?
	var isPressBegin: Bool
}




// 包裝 closure 的 class
final class FrameHandler {
	let onFrame: (ParsecFrame, UnsafeRawPointer) -> Void
	init(onFrame: @escaping (ParsecFrame, UnsafeRawPointer) -> Void) {
		self.onFrame = onFrame
	}
}



func parsecFrameCallback(
	framePtr: UnsafePointer<ParsecFrame>?,
	imagePtr: UnsafeRawPointer?,
	opaque: UnsafeMutableRawPointer?
) {
	guard let frame = framePtr?.pointee, let image = imagePtr else { return }
	let handler = Unmanaged<FrameHandler>.fromOpaque(opaque!).takeUnretainedValue()
	handler.onFrame(frame, image)
}




class ParsecSDKBridge: ParsecService
{
	var hostWidth: Float = 1920
	
	var hostHeight: Float = 1080


	static let PARSEC_VER: UInt32 = UInt32((PARSEC_VER_MAJOR << 16) | PARSEC_VER_MINOR)
	
	private var _parsec: OpaquePointer!
	private var _audio: OpaquePointer!
	private let _audioPtr: UnsafeRawPointer
	
	private var isVirtualShiftOn = false
	private let keyboardQueue = DispatchQueue(label: "openparsec.keyboard.input")
	
	public var clientWidth: Float = 1920
	public var clientHeight: Float = 1080
	
	public var netProtocol: Int32 = 1
	public var mediaContainer: Int32 = 0
	public var pngCursor: Bool = false

	// 觀察全局設定變更
	@ObservedObject private var settings = SettingsHandler.shared
    

	private var audioWorkItem: DispatchWorkItem?
	private var eventWorkItem: DispatchWorkItem?


	var didSetResolution = false
	
	public var mouseInfo = MouseInfo()
	
	init() {
		print("Parsec SDK Version: " + String(ParsecSDKBridge.PARSEC_VER))
		
		ParsecSetLogCallback(
			{ (level, msg, opaque) in
				print("[\(level == LOG_DEBUG ? "D" : "I")] \(String(cString:msg!))")
			}, nil)
		
		audio_init(&_audio)
		
		self._audioPtr = UnsafeRawPointer(_audio)
		
		do {
			let reservedCfg = ["ssHost": "kessel-ws.parsec.app"]
			let json = JSONEncoder()
			try json.encode(reservedCfg).withUnsafeBytes { (jsonStrBPtr: UnsafeRawBufferPointer) in
				guard let jsonStrPtr = jsonStrBPtr.baseAddress else {
					return
				}
				ParsecInit(ParsecSDKBridge.PARSEC_VER, nil, jsonStrPtr, &_parsec)
			}

		} catch {
			print("error: \(error)")
		}

	}
	
	deinit {
		ParsecDestroy(_parsec)
		audio_destroy(&_audio)
	}

	func destroy() {
		ParsecDestroy(_parsec)
		audio_destroy(&_audio)
		print("清理Parsec 與Audio管線")
		write_log_from_swift("清理Parsec 與Audio管線")

	}


	func connect(_ peerID: String) -> ParsecStatus {

		self.applyConfig()

		var cfg = buildConfig()


		let status = ParsecClientConnect(_parsec, &cfg, NetworkHandler.clinfo?.session_id, peerID)

		self.startBackgroundTask()

		return status
	}

	// 配置建立
	func buildConfig() -> ParsecClientConfig {
		var parsecClientCfg = ParsecClientConfig()

		parsecClientCfg.video.0.decoderIndex = 1
		parsecClientCfg.video.0.resolutionX = Int32(settings.resolution.width)
		parsecClientCfg.video.0.resolutionY = Int32(settings.resolution.height)

		parsecClientCfg.video.0.decoderCompatibility = settings.decoderCompatibility
		parsecClientCfg.video.0.decoderH265 = settings.decoder == .h265
		parsecClientCfg.video.0.decoder444 = settings.decoder444

		parsecClientCfg.mediaContainer = mediaContainer
		parsecClientCfg.protocol = netProtocol
		parsecClientCfg.pngCursor = pngCursor
		//parsecClientCfg.secret = ""

		return parsecClientCfg
	}


	// 套用配置
	func applyConfig() {

		var cfg = buildConfig()

		print(
			"Debug Compatibility? -> \(cfg.video.0.decoderCompatibility)"
		)

		print("Debug H265? -> \(cfg.video.0.decoderH265)")

		ParsecClientSetConfig(_parsec, &cfg);

		
	}



	func disconnect() {

		mouseInfo.cursorImg = nil
		getFirstCursor = false

		stopBackgroundTask()

		audio_clear(&_audio)

		ParsecClientDisconnect(_parsec)


	}



	func getStatus() -> ParsecStatus {
		
		return ParsecClientGetStatus(_parsec, nil)
	}

	func getOutputs(maxCount: Int = 10) -> [ParsecDecoder] {
		// 1️⃣ 创建一个 C 数组
		var outputs = [ParsecDecoder](
			repeating: ParsecDecoder(),
			count: maxCount
		)

		// 2️⃣ 调用 SDK
		let count = outputs.withUnsafeMutableBufferPointer { buffer -> UInt32 in
			return ParsecGetDecoders(buffer.baseAddress, UInt32(buffer.count))
		}
		// 3️⃣ 返回 Swift 数组
		return Array(outputs.prefix(Int(count)))
		
	}


	func getStatusEx(_ pcs: inout ParsecClientStatus) -> ParsecStatus {

		let status = ParsecClientGetStatus(_parsec, &pcs)
		if status == PARSEC_OK {
			hostWidth  = Float(pcs.decoder.0.width)
			hostHeight = Float(pcs.decoder.0.height)
		}
		return status
	}

	func setFrame(_ width:CGFloat, _ height:CGFloat, _ scale:CGFloat)
	{
		ParsecClientSetDimensions(_parsec, UInt8(DEFAULT_STREAM), UInt32(width), UInt32(height), Float(scale))
		
		clientWidth = Float(width)
		clientHeight = Float(height)
		mouseInfo.mouseX = Int32(width / 2)
		mouseInfo.mouseY = Int32(height / 2)
	}




	// timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	func renderGLFrame(timeout: UInt32 = 16) {
		
		ParsecClientGLRenderFrame(_parsec, UInt8(DEFAULT_STREAM), nil, nil, timeout)
	}

	func clearGL(){
		os_log("ClearGL")
		ParsecClientGLDestroy(_parsec,UInt8(DEFAULT_STREAM))

	}

	/*static func renderMetalFrame(_ queue:inout MTLCommandQueue, _ texturePtr: UnsafeMutablePointer<UnsafeMutableRawPointer?>, timeout: UInt32 = 16) // timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	 {
	 ParsecClientMetalRenderFrame(_parsec, UInt8(DEFAULT_STREAM), &queue, texturePtr, nil, nil, timeout)
	 }*/


	
	
	// 在 CParsec 封裝層
	// Swift wrapper


	

	func renderMetalFrame(
    timeout: UInt32 = 16,
    onFrame: @escaping (ParsecFrame, UnsafeRawPointer) -> Void
	) -> ParsecStatus {
		let handler = FrameHandler(onFrame: onFrame)
		let opaque = Unmanaged.passUnretained(handler).toOpaque()

		let status: ParsecStatus = ParsecClientPollFrame(
			_parsec,
			UInt8(DEFAULT_STREAM),
			parsecFrameCallback,
			timeout,
			opaque
		)
		return status
	}


	



	func pollAudio(timeout:UInt32 = 16) // timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	{
		let status: ParsecStatus = ParsecClientPollAudio(_parsec, audio_cb, timeout, _audioPtr)
		// log non-zero status for debugging
		if status != PARSEC_OK {
			let msg = "ParsecClientPollAudio returned \(status)"
			print(msg)
			msg.withCString { cstr in
				write_log_from_swift(cstr)
			}
		}
	}
	
	var getFirstCursor = false
	var mousePositionRelative = false
	
	func pollEvent(timeout: UInt32 = 16) // timeout in ms, 16 == 60 FPS, 8 == 120 FPS, etc.
	{
		var e: ParsecClientEvent!
		var _event = ParsecClientEvent()
		var pollSuccess = false;
		withUnsafeMutablePointer(to: &_event, {(_eventPtr) in
			pollSuccess = ParsecClientPollEvents(_parsec, timeout, _eventPtr)
			e = _eventPtr.pointee
		})
		if !pollSuccess {
			return
		}
		if e.type == CLIENT_EVENT_CURSOR {
			handleCursorEvent(event: e.cursor)
		} else if e.type == CLIENT_EVENT_USER_DATA {
			handleUserDataEvent(event: e.userData)
		}
	}


	func handleUserDataEvent(event: ParsecClientUserDataEvent) {
		
		let pointer = ParsecGetBuffer(_parsec, event.key)
		switch event.id {
		case 11:
			do {
				let decoder = JSONDecoder()
				let config = try decoder.decode(ParsecUserDataVideoConfig.self, from: Data(bytesNoCopy: pointer!, count: strlen(pointer!), deallocator: .none))
				let videoConfig = config.video[0]

				write_log_from_swift("取得Host寬高: \(videoConfig.resolutionX)x\(videoConfig.resolutionY)")
				write_log_from_swift("Bitrate \(videoConfig.encoderMaxBitrate) bps, constantFps: \(videoConfig.fullFPS ? "true" : "false"), output: \(videoConfig.output)")

				DispatchQueue.main.async {
					DataManager.model.resolutionX = videoConfig.resolutionX
					DataManager.model.resolutionY = videoConfig.resolutionY

					
					DataManager.model.bitrate = videoConfig.encoderMaxBitrate
					DataManager.model.constantFps = videoConfig.fullFPS
					DataManager.model.output = videoConfig.output

					if !self.didSetResolution {
						self.didSetResolution = true
						DataManager.model.resolutionX = settings.resolution.width
						DataManager.model.resolutionY = settings.resolution.height

						write_log_from_swift("Applying resolution from settings: \(settings.resolution.width)x\(settings.resolution.height)")

						if settings.bitrate != 0 {
							DataManager.model.bitrate = settings.bitrate

							write_log_from_swift("Applying bitrate from settings: \(settings.bitrate) bps")
						}

						self.updateHostVideoConfig()
					}


				}
				
			} catch {
				print("error while parsing user data: \(error.localizedDescription)")
			}
		case 12:
			do {
				let decoder = JSONDecoder()
				let config = try decoder.decode(Array<ParsecDisplayConfig>.self, from: Data(bytesNoCopy: pointer!, count: strlen(pointer!), deallocator: .none))
				DispatchQueue.main.async {
					DataManager.model.displayConfigs = config
				}
			} catch {
				print("error while parsing user data: \(error.localizedDescription)")
			}
		default:
			break
		}
		
		ParsecFree(pointer)
		
	}

	

	func handleCursorEvent(event: ParsecClientCursorEvent) {

		//let prevHidden = mouseInfo.cursorHidden
		mouseInfo.cursorHidden = event.cursor.hidden
		mouseInfo.mousePositionRelative = event.cursor.relative

		guard event.cursor.imageUpdate || !getFirstCursor else {
			return
		}
		getFirstCursor = true

		guard let pointer = ParsecGetBuffer(_parsec, event.key) else {
			return
		}

		defer {
			ParsecFree(pointer)
		}

		let size = Int(event.cursor.size)
		let width = Int(event.cursor.width)
		let height = Int(event.cursor.height)
		mouseInfo.cursorWidth = width
		mouseInfo.cursorHeight = height
		mouseInfo.cursorHotX = Int(event.cursor.hotX)
		mouseInfo.cursorHotY = Int(event.cursor.hotY)

		let data = Data(bytes: pointer, count: size)   // ✅ Swift 管理

		let provider = CGDataProvider(data: data as CFData)!

		let cgimage = CGImage(
			width: width,
			height: height,
			bitsPerComponent: 8,
			bitsPerPixel: 32,
			bytesPerRow: width * 4,
			space: CGColorSpaceCreateDeviceRGB(),
			bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
			provider: provider,
			decode: nil,
			shouldInterpolate: true,
			intent: .defaultIntent
		)

		if let cgimage {
			mouseInfo.cursorImg = cgimage   // 舊的會被 ARC 釋放
		}
	}
	func setMuted(_ muted: Bool) {
		audio_mute(muted, _audioPtr)
	}
	
	
	
	func sendMouseMessage(_ button:ParsecMouseButton, _ x:Int32, _ y:Int32, _ pressed: Bool)
	{
		// Send the mouse position
		sendMousePosition(x, y)
		
		// Send the mouse button state
		var buttonMessage = ParsecMessage()
		buttonMessage.type = MESSAGE_MOUSE_BUTTON
		buttonMessage.mouseButton.button = button
		buttonMessage.mouseButton.pressed = pressed
		ParsecClientSendMessage(_parsec, &buttonMessage)
	}
	
	func sendMouseClickMessage(_ button:ParsecMouseButton, _ pressed: Bool) {
		var buttonMessage = ParsecMessage()
		buttonMessage.type = MESSAGE_MOUSE_BUTTON
		buttonMessage.mouseButton.button = button
		buttonMessage.mouseButton.pressed = pressed
		ParsecClientSendMessage(_parsec, &buttonMessage)
	}
	
	func sendMouseDelta(_ dx: Int32, _ dy: Int32) {
		if mouseInfo.mousePositionRelative {
			sendMouseRelativeMove(dx, dy)
		} else {
			sendMousePosition(mouseInfo.mouseX + dx, mouseInfo.mouseY + dy)
		}
		
	}
	static func clamp<T>(_ value: T, minValue: T, maxValue: T) -> T where T : Comparable {
		return min(max(value, minValue), maxValue)
	}
	
	func sendMousePosition(_ x:Int32, _ y:Int32)
	{
		let clampedX = ParsecSDKBridge.clamp(x, minValue: 0, maxValue: Int32(self.clientWidth))
		let clampedY = ParsecSDKBridge.clamp(y, minValue: 0, maxValue: Int32(self.clientHeight))
		mouseInfo.mouseX = clampedX
		mouseInfo.mouseY = clampedY
		var motionMessage = ParsecMessage()
		motionMessage.type = MESSAGE_MOUSE_MOTION
		motionMessage.mouseMotion.x = clampedX
		motionMessage.mouseMotion.y = clampedY
		ParsecClientSendMessage(_parsec, &motionMessage)
	}
	
	func sendMouseRelativeMove(_ dx:Int32, _ dy:Int32)
	{
		var motionMessage = ParsecMessage()
		motionMessage.type = MESSAGE_MOUSE_MOTION
		motionMessage.mouseMotion.x = dx
		motionMessage.mouseMotion.y = dy
		motionMessage.mouseMotion.relative = true
		ParsecClientSendMessage(_parsec, &motionMessage)
	}
	
	func getKeyCodeByText(text: String) -> (ParsecKeycode?, Bool) {
		var keyCode : ParsecKeycode?
		var useShift = false


		if text.count == 1 {
			let char = Character(text)
			if char.isLetter || char.isNumber {
				keyCode = KeyCodeTranslators.parsecKeyCodeTranslator(text.uppercased())
				if char.isUppercase {
					useShift = true
				}

			} else if char.isNewline {
				keyCode = ParsecKeycode(40)
			} else if char.isWhitespace{
				keyCode = ParsecKeycode(44)
			} else {
				let (keycodeRaw, keyMod) = KeyCodeTranslators.getParsecKeycode(for: text)
				if keycodeRaw != -1 {
					keyCode = ParsecKeycode(UInt32(keycodeRaw))
					if keyMod {
						useShift = true
					}
				}
			}
		} else {
			keyCode = KeyCodeTranslators.parsecKeyCodeTranslator(text)
		}

		if let key = keyCode {
			os_log("KeyCode:\(key.rawValue)-\(text)")
		}

		return (keyCode, useShift)
	}
	
	private func sendKeyboardCode(_ code: ParsecKeycode, pressed: Bool) {
		var keyboardMessage = ParsecMessage()
		keyboardMessage.type = MESSAGE_KEYBOARD
		keyboardMessage.keyboard.code = code
		keyboardMessage.keyboard.pressed = pressed
		ParsecClientSendMessage(_parsec, &keyboardMessage)
	}

	private func tapKeyboardCode(_ code: ParsecKeycode, useShift: Bool = false, holdFor delay: TimeInterval = 0.02) {
		if !isVirtualShiftOn && useShift {
			sendKeyboardCode(ParsecKeycode(rawValue: 225), pressed: true)
		}

		sendKeyboardCode(code, pressed: true)
		Thread.sleep(forTimeInterval: delay)
		sendKeyboardCode(code, pressed: false)

		if useShift && !isVirtualShiftOn {
			sendKeyboardCode(ParsecKeycode(rawValue: 225), pressed: false)
		}
	}

	private func tapTextKey(_ text: String) -> Bool {
		let (keyCode, useShift) = getKeyCodeByText(text: text)

		guard let keyCode else {
			return false
		}

		os_log("KeyCode:\(keyCode.rawValue)-\(text)")
		tapKeyboardCode(keyCode, useShift: useShift, holdFor: 0.05)
		return true
	}

	private func tapHexDigit(_ digit: Character) {
		_ = tapTextKey(String(digit))
	}

	private func sendLinuxUnicodeScalar(_ scalar: UnicodeScalar) {
		let hex = String(scalar.value, radix: 16, uppercase: false)

		sendKeyboardCode(ParsecKeycode(rawValue: 224), pressed: true)
		sendKeyboardCode(ParsecKeycode(rawValue: 225), pressed: true)
		tapKeyboardCode(ParsecKeycode(rawValue: 24))
		sendKeyboardCode(ParsecKeycode(rawValue: 225), pressed: false)
		sendKeyboardCode(ParsecKeycode(rawValue: 224), pressed: false)

		Thread.sleep(forTimeInterval: 0.02)
		for digit in hex {
			tapHexDigit(digit)
		}
		tapKeyboardCode(ParsecKeycode(rawValue: 40))
	}

	private func sendMacUnicodeHexCodeUnit(_ codeUnit: UInt16) {
		let hex = String(format: "%04x", codeUnit)

		sendKeyboardCode(ParsecKeycode(rawValue: 226), pressed: true)
		for digit in hex {
			tapHexDigit(digit)
		}
		sendKeyboardCode(ParsecKeycode(rawValue: 226), pressed: false)
	}

	private func sendWindowsHexNumpadScalar(_ scalar: UnicodeScalar) {
		let hex = String(scalar.value, radix: 16, uppercase: false)

		sendKeyboardCode(ParsecKeycode(rawValue: 226), pressed: true)
		tapKeyboardCode(ParsecKeycode(rawValue: 87))
		for digit in hex {
			tapHexDigit(digit)
		}
		sendKeyboardCode(ParsecKeycode(rawValue: 226), pressed: false)
	}

	private func sendUnicodeScalar(_ scalar: UnicodeScalar) {
		switch settings.remoteTextInputMode {
		case .keycodeOnly:
			os_log("Unsupported virtual keyboard text without unicode input mode: \(String(scalar))")
		case .linuxUnicode:
			sendLinuxUnicodeScalar(scalar)
		case .macUnicodeHex:
			for codeUnit in String(scalar).utf16 {
				sendMacUnicodeHexCodeUnit(codeUnit)
			}
		case .windowsHexNumpad:
			sendWindowsHexNumpadScalar(scalar)
		}
	}

	private func sendVirtualKeyboardText(_ text: String) {
		if tapTextKey(text) {
			return
		}

		for character in text {
			let characterText = String(character)
			if tapTextKey(characterText) {
				continue
			}

			for scalar in characterText.unicodeScalars {
				sendUnicodeScalar(scalar)
			}
		}
	}

	func sendVirtualKeyboardInput(text: String) {
		keyboardQueue.async { [weak self] in
			self?.sendVirtualKeyboardText(text)
		}
	}


	func sendVirtualKeyboardInput(text: String, isOn: Bool) {
		let (keyCode, _) = getKeyCodeByText(text: text)
		
		guard let keyCode else {
			return
		}
		
		if keyCode.rawValue == 225 {
			isVirtualShiftOn = isOn
		}



		var keyboardMessagePress = ParsecMessage()
		keyboardMessagePress.type = MESSAGE_KEYBOARD
		keyboardMessagePress.keyboard.pressed = isOn
		keyboardMessagePress.keyboard.code = keyCode
		ParsecClientSendMessage(_parsec, &keyboardMessagePress)
		
	}

	func sendKeyboardMessage(event:KeyBoardKeyEvent)
	{

		if event.input == nil {
			return
		}

		os_log("")

		var keyboardMessagePress = ParsecMessage()
		keyboardMessagePress.type = MESSAGE_KEYBOARD
		keyboardMessagePress.keyboard.code = ParsecKeycode(UInt32(KeyCodeTranslators.uiKeyCodeToInt(key: event.input?.keyCode ?? UIKeyboardHIDUsage.keyboardErrorUndefined)))

		keyboardMessagePress.keyboard.pressed = event.isPressBegin

		ParsecClientSendMessage(_parsec, &keyboardMessagePress)

	}
	
	func sendGameControllerButtonMessage(controllerId: UInt32, _ button:ParsecGamepadButton, pressed: Bool)
	{
		var pmsg = ParsecMessage()
		pmsg.type = MESSAGE_GAMEPAD_BUTTON
		pmsg.gamepadButton.id = controllerId
		pmsg.gamepadButton.button = button
		pmsg.gamepadButton.pressed = pressed
		ParsecClientSendMessage(_parsec, &pmsg)
	}
	
	/*static func sendGameControllerTriggerButtonMessage(controllerId: UInt32, _ button:ParsecGamepadAxis, pressed: Bool)
	{
	    var pmsg = ParsecMessage()
		pmsg.type = MESSAGE_GAMEPAD_AXIS
		pmsg.gamepadAxis.id = controllerId
		pmsg.gamepadAxis.button = button
		pmsg.gamepadAxis.pressed = pressed
		ParsecClientSendMessage(_parsec, &pmsg)
	}*/
	
	func sendGameControllerAxisMessage(controllerId: UInt32, _ button:ParsecGamepadAxis, _ value: Int16)
	{
	    var pmsg = ParsecMessage()
		pmsg.type = MESSAGE_GAMEPAD_AXIS
		pmsg.gamepadAxis.id = controllerId
		pmsg.gamepadAxis.axis = button
		pmsg.gamepadAxis.value = value
		ParsecClientSendMessage(_parsec, &pmsg)
	}
	
	func sendGameControllerUnplugMessage(controllerId: UInt32)
	{
	    var pmsg = ParsecMessage()
		pmsg.type = MESSAGE_GAMEPAD_UNPLUG;
		pmsg.gamepadUnplug.id = controllerId;
		ParsecClientSendMessage(_parsec, &pmsg)
	}
	
	func sendWheelMsg(x: Int32, y: Int32) {
		var pmsg = ParsecMessage()
		pmsg.type = MESSAGE_MOUSE_WHEEL;
		pmsg.mouseWheel.x = x
		pmsg.mouseWheel.y = y
		ParsecClientSendMessage(_parsec, &pmsg)
	}
	


	private var audioTimer: DispatchSourceTimer?
	private var eventTimer: DispatchSourceTimer?


	let audioQueue = DispatchQueue(label: "audio.background.queue", qos: .userInitiated)
	let eventQueue = DispatchQueue(label: "event.background.queue", qos: .userInitiated)



	func startBackgroundTask() {
		guard audioTimer == nil, eventTimer == nil else { return }

		// audio timer
		let aTimer = DispatchSource.makeTimerSource(queue: audioQueue)
		aTimer.schedule(deadline: .now(), repeating: .milliseconds(10)) // 每 10ms
		aTimer.setEventHandler { [weak self] in
			self?.pollAudio()
		}
		aTimer.resume()
		audioTimer = aTimer

		// event timer
		let eTimer = DispatchSource.makeTimerSource(queue: eventQueue)
		eTimer.schedule(deadline: .now(), repeating: .milliseconds(10))
		eTimer.setEventHandler { [weak self] in
			self?.pollEvent()
		}
		eTimer.resume()
		eventTimer = eTimer
	}

	func stopBackgroundTask() {
		audioTimer?.cancel()
		audioTimer = nil

		eventTimer?.cancel()
		eventTimer = nil
	}



	func sendUserData(type: ParsecUserDataType, message: Data) {
        var nullTerminatedMessage = message
        nullTerminatedMessage.append(0)
		nullTerminatedMessage.withUnsafeBytes { ptr in
			let ptr2 = ptr.baseAddress?.assumingMemoryBound(to: CChar.self)
			ParsecClientSendUserData(_parsec, type.rawValue, ptr2)
		}
	}
	
	func updateHostVideoConfig() {
		var videoConfig = ParsecUserDataVideoConfig()
		videoConfig.video[0].resolutionX = DataManager.model.resolutionX
		videoConfig.video[0].resolutionY = DataManager.model.resolutionY
		videoConfig.video[0].encoderMaxBitrate = DataManager.model.bitrate
		videoConfig.video[0].fullFPS = DataManager.model.constantFps
		videoConfig.video[0].output = DataManager.model.output
		let encoder = JSONEncoder()
		let data = try! encoder.encode(videoConfig)
		CParsec.sendUserData(type: .setVideoConfig, message: data)
	}
}
