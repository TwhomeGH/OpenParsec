import SwiftUI





struct SettingsView:View
{
	@Binding var visible: Bool

	@EnvironmentObject var settings: SettingsHandler



	let bitrateChoices: [Choice<Int>] = ParsecResolution.bitrates.map { value in

		if value == 0 {
			return Choice("不指定 Not Setting [Auto]", value)
		} else {
			return Choice("\(value) Mbps", value)
		}

	}

	let resolutionChoices: [Choice<ParsecResolution>]

	init(visible: Binding<Bool> ) {
		_visible = visible
		var tmp: [Choice<ParsecResolution>] = []
		for res in ParsecResolution.resolutions {
			tmp.append(Choice(res.desc, res))
		}
		resolutionChoices = tmp
	}
	
	var body: some View
	{
		ZStack()
		{
			if (visible)
			{
				// Background
				Rectangle()
					.fill(Color.init(red:0, green:0, blue:0, opacity:0.67))
					.edgesIgnoringSafeArea(.all)
			}
		}
		.animation(.linear(duration:0.24))

		ZStack()
		{
			if (visible)
			{
				// Main controls
				VStack()
				{
					// Navigation controls
					ZStack()
					{
						Rectangle()
							.fill(Color("BackgroundTab"))
							.frame(height:52)
							.shadow(color:Color("Shading"), radius:4, y:6)
						ZStack()
						{
							HStack()
							{
								Button(action: saveAndExit, label:{ Image(systemName:"xmark").scaleEffect(x:-1) })
								.padding()
								Spacer()
							}
							Text("Settings")
								.multilineTextAlignment(.center)
								.foregroundColor(Color("Foreground"))
								.font(.system(size:20, weight:.medium))
							Spacer()
						}
						.foregroundColor(Color("AccentColor"))
					}
					.zIndex(1)

					ScrollView()
					{
                        CatTitle("Interactivity")
                        CatList()
                        {
                            CatItem("Mouse Movement")
                            {
                                MultiPicker(selection:$settings.cursorMode, options:
								[
									Choice("Touchpad", CursorMode.touchpad),
									Choice("Direct", CursorMode.direct)
								])
                            }
							CatItem("Right Click Position")
							{
								MultiPicker(selection:$settings.rightClickPosition, options:
								[
									Choice("First Finger", RightClickPosition.firstFinger),
									Choice("Middle", RightClickPosition.middle),
									Choice("Second Finger", RightClickPosition.secondFinger)
								])
							}
                            CatItem("Cursor Scale")
                            {
                                Slider(value: $settings.cursorScale, in:0.1...4, step:0.1)
									.frame(width: 200)
								Text(String(format: "%.1f", settings.cursorScale))
                            }
							CatItem("Mouse Sensitivity")
							{
								Slider(value: $settings.mouseSensitivity, in:0.1...4, step:0.1)
									.frame(width: 200)
								Text(String(format: "%.1f", settings.mouseSensitivity))
							}
                        }
                        CatTitle("Graphics")
                        CatList()
                        {
                            CatItem("Renderer")
                            {
								SegmentPicker(selection:$settings.renderer, options:
								[
									Choice("OpenGL", RendererType.opengl),
									Choice("Metal", RendererType.metal)
								])
                                .frame(width:165)

                            }
						
							CatItem("Default Resolution")
							{
								MultiPicker(selection: $settings.resolution, options:resolutionChoices)
							}
							CatItem("BitRate")
							{
								MultiPicker(selection: $settings.bitrate, options:bitrateChoices)
							}

                            CatItem("Decoder")
                            {
								MultiPicker(selection: $settings.decoder, options:
								[
									Choice("H.264", DecoderPref.h264),
									Choice("Prefer H.265", DecoderPref.h265)
								])
                            }

							CatItem("Decoder 444")
							{
								Toggle("", isOn:$settings.decoder444)
									.frame(width:80)
							}
							CatItem("Decoder Compatibility")
							{
								Toggle("", isOn:$settings.decoderCompatibility)
									.frame(width:80)
							}
							
							CatItem("Frame Rate")
							{
								MultiPicker(selection: $settings.preferredFramesPerSecond, options:
								[
									Choice("Auto (Device Max)", 0),
									Choice("120 FPS", 120),
									Choice("90 FPS", 90),
									Choice("60 FPS", 60),
									Choice("30 FPS", 30)
								])
							}
							
							
                        }
                        CatTitle("Misc")
                        CatList()
                        {

							CatItem("Metal 顯示的可見確認用提示文本")
							{
								Toggle("", isOn:$settings.MetalText)
									.frame(width:80)
							}
                            CatItem("Never Show Overlay")
                            {
                                Toggle("", isOn:$settings.noOverlay)
                                    .frame(width:80)
                            }
							CatItem("Hide Status Bar")
							{
								Toggle("", isOn:$settings.hideStatusBar)
									.frame(width:80)
							}
							CatItem("Show Keyboard Button")
							{
								Toggle("", isOn:$settings.showKeyboardButton)
									.frame(width:80)
							}
							CatItem("Enable Logging")
							{
								Toggle("", isOn:$settings.enableLogging)
									.frame(width:80)
									.onChange(of: settings.enableLogging) { newValue in
										set_logging_enabled(newValue)
									}
							}
							CatItem("Enable Audio Logging")
							{
								Toggle("", isOn:$settings.enableAudioLogging)
									.frame(width:80)
									.onChange(of: settings.enableAudioLogging) { newValue in
										set_audio_logging_enabled(newValue)
									}
							}
							CatItem("Remote Text Input")
							{
								MultiPicker(selection: $settings.remoteTextInputMode, options:
								[
									Choice("Keycodes Only", RemoteTextInputMode.keycodeOnly),
									Choice("Linux Ctrl+Shift+U", RemoteTextInputMode.linuxUnicode),
									Choice("macOS Unicode Hex", RemoteTextInputMode.macUnicodeHex),
									Choice("Windows Hex Numpad", RemoteTextInputMode.windowsHexNumpad)
								])
							}
							CatItem("Enable PiP")
							{
								Toggle("", isOn:$settings.enablePiP)
									.frame(width:80)
							}
							CatItem("Status Bar Auto-Hide Timer")
							{
								Slider(value: $settings.statusBarTimer, in:0.1...100, step:0.1)
									.frame(width: 200)
								Text(String(format: "%.1f seconds", settings.statusBarTimer))
							}
						

						}
						Text("More options coming soon.")
							.multilineTextAlignment(.center)
							.opacity(0.5)
							.padding()
					}
                    .foregroundColor(Color("Foreground"))
				}
				.background(Rectangle().fill(Color("BackgroundGray")))
				.cornerRadius(8)
				.padding()
				.animation(.none)
			}
		}
        .preferredColorScheme(appScheme)
		.scaleEffect(visible ? 1 : 0, anchor:.zero)
		.animation(.easeInOut(duration:0.24))
	}
	
	func saveAndExit()
	{
		//settings.renderer = renderer
		visible = false
	}
}

struct SettingsView_Previews:PreviewProvider
{
	@State static var value: Bool = true

	static var previews: some View
	{

		SettingsView(visible:$value)
	}
}
