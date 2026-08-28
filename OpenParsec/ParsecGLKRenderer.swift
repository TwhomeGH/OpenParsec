import GLKit
import ParsecSDK

class ParsecGLKRenderer:NSObject, GLKViewDelegate, GLKViewControllerDelegate
{
	var glkView:GLKView
	var glkViewController:GLKViewController
	
	var lastWidth:CGFloat = 1.0
	var lastHeight: CGFloat = 1.0
	var lastScale: CGFloat = 0.0

	var lastImg: CGImage?
	let updateImage: () -> Void
	
	init(_ view:GLKView, _ viewController:GLKViewController,_ updateImage: @escaping () -> Void)
	{
		self.updateImage = updateImage
		glkView = view
		glkViewController = viewController

		super.init()

		glkView.delegate = self
		glkViewController.delegate = self

		// 背景時 GLKViewController 的 display link 會被系統停止，PiP 只能靠
		// pump 呼叫這個 closure 自行拉幀＋繪製，才不會凍結。
		if #available(iOS 15.0, *) {
			PictureInPictureManager.shared.captureSourceRenderer = { [weak self] in
				self?.renderPipFrameInBackground()
			}
		}
	}

	deinit
	{
		glkView.delegate = nil
		glkViewController.delegate = nil
		if #available(iOS 15.0, *) {
			PictureInPictureManager.shared.captureSourceRenderer = nil
		}
	}

	func glkView(_ view: GLKView, drawIn rect: CGRect) {
		let width = view.bounds.size.width
		let height = view.bounds.size.height
		let scale = view.contentScaleFactor

		let deltaWidth = abs(width - lastWidth)
		let deltaHeight = abs(height - lastHeight)
		let deltaScale = abs(scale - lastScale)

		if deltaWidth > 0.1 || deltaHeight > 0.1 || deltaScale > 0.001 {
			// 用邏輯大小 + scale 告訴 Parsec
			CParsec.setFrame(width, height, scale)

			// 用像素大小設置 OpenGL viewport
			glViewport(0, 0,
					GLsizei(view.drawableWidth),
					GLsizei(view.drawableHeight))

			lastWidth = width
			lastHeight = height
			lastScale = scale
			print("SCALE", scale)
			print("Width:\(width)x\(height)")
		}

		let fps = SettingsHandler.shared.preferredFramesPerSecond == 0
			? UIScreen.main.maximumFramesPerSecond
			: SettingsHandler.shared.preferredFramesPerSecond
		let timeout = UInt32(max(1000 / fps, 8))

		CParsec.renderGLFrame(timeout: timeout)

		if #available(iOS 15.0, *) {
			updatePipCaptureSize()

			if PictureInPictureManager.shared.beginOpenGLCaptureFrame() {
				CParsec.renderGLFrame(timeout: 0)

				// 翻轉 FBO 內容：AVSampleBufferDisplayLayer 是左上原點，OpenGL 是左下原點
				flipPipCapture()

				PictureInPictureManager.shared.endOpenGLCaptureFrame()
			}
		}

		updateImage()
	}


	// 依實際視訊尺寸重建 PiP 擷取面（比例要對齊影片 16:9，而非螢幕 4:3）
	@available(iOS 15.0, *)
	private func updatePipCaptureSize() {
		guard PictureInPictureManager.shared.isPiPActive || PictureInPictureManager.shared.isStarting else { return }
		var pcs = ParsecClientStatus()
		guard CParsec.getStatusEx(&pcs) == PARSEC_OK else { return }
		PictureInPictureManager.shared.updateVideoSize(width: Int(pcs.decoder.0.width), height: Int(pcs.decoder.0.height))
	}

	@available(iOS 15.0, *)
	private func flipPipCapture() {
		var captureFBO: GLint = 0
		glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &captureFBO)
		guard let size = PictureInPictureManager.shared.captureSize else { return }
		let w = GLint(size.width)
		let h = GLint(size.height)
		glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), GLuint(captureFBO))
		glBindFramebuffer(GLenum(GL_DRAW_FRAMEBUFFER), GLuint(captureFBO))
		glBlitFramebuffer(0, 0, w, h,
						  0, h, w, 0,
						  GLbitfield(GL_COLOR_BUFFER_BIT),
						  GLenum(GL_LINEAR))
	}

	// 背景時由 frame pump 呼叫：直接把最新幀 render 進 PiP 擷取 FBO
	@available(iOS 15.0, *)
	private func renderPipFrameInBackground() {
		EAGLContext.setCurrent(glkView.context)

		guard PictureInPictureManager.shared.beginOpenGLCaptureFrame() else { return }
		CParsec.renderGLFrame(timeout: 0)
		flipPipCapture()
		PictureInPictureManager.shared.endOpenGLCaptureFrame()
	}


	func glkViewControllerUpdate(_ controller:GLKViewController) { }


}
