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

	}

	deinit
	{
		glkView.delegate = nil
		glkViewController.delegate = nil
	}

	func glkView(_ view:GLKView, drawIn rect:CGRect)
	{

		// 用 drawableWidth/Height 而不是 bounds
		let width = CGFloat(view.drawableWidth)
		let height = CGFloat(view.drawableHeight)
		let scale = view.contentScaleFactor


		let deltaWidth = abs(width - lastWidth)
		let deltaHeight = abs(height - lastHeight)
		let deltaScale = abs(scale - lastScale)

		if deltaWidth > 0.1 || deltaHeight > 0.1 || deltaScale > 0.001
		{
		    CParsec.setFrame(width, height, scale)

			// 確保 OpenGL viewport 和 GLKView 對齊
			glViewport(0, 0, GLsizei(width), GLsizei(height))
			
	        lastWidth = width
			lastHeight = height
			lastScale = scale
			print("SCALE", scale)
			print("Width:\(width)x\(height)")
		}

		// Calculate timeout based on configured/device frame rate
		// timeout in ms: 16ms = ~60fps, 8ms = ~120fps
		let fps = SettingsHandler.shared.preferredFramesPerSecond == 0
			? UIScreen.main.maximumFramesPerSecond
			: SettingsHandler.shared.preferredFramesPerSecond
		let timeout = UInt32(max(1000 / fps, 8)) // minimum 8ms for 120Hz

		CParsec.renderGLFrame(timeout: timeout)

		updateImage()

//		glFinish()
		//glFlush()
	}

	func glkViewControllerUpdate(_ controller:GLKViewController) { }


}
