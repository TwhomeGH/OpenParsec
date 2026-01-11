
import SwiftUI
import MetalKit
import UIKit

typealias ParsecRenderer =
	ParsecPlayground & ParsecRenderController


class ParsecMetalViewControllerWrapper : ParsecPlayground,ParsecRenderController {
    let viewController: UIViewController
    var mtkView: MTKView!
    var renderer: ParsecMetalRenderer!
    
    let updateImage: () -> Void

	private var framesDisplayedCounter: Int = 0
    
    var preferredFPS: Int {
        get { mtkView.preferredFramesPerSecond }
        set { mtkView.preferredFramesPerSecond = newValue }
    }
    
    func drawFrameCompleted() {
        framesDisplayedCounter += 1
    }
    
    func getFramesDisplayed() -> Int {
        return framesDisplayedCounter
    }

    
	required init(
		viewController: UIViewController,
		updateImage: @escaping () -> Void
	) {
        self.viewController = viewController
        self.updateImage = updateImage
    }
    
    func viewDidLoad() {
        mtkView = MTKView(frame: viewController.view.bounds)
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = false
        mtkView.preferredFramesPerSecond = SettingsHandler.fpsPerFrame
        mtkView.framebufferOnly = false
        
        renderer = ParsecMetalRenderer(mtkView, updateImage: updateImage)
        viewController.view.addSubview(mtkView)
    }
    
    func updateSize(width: CGFloat, height: CGFloat) {
        mtkView.frame.size = CGSize(width: width, height: height)
    }

	func cleanUp() {
		mtkView?.removeFromSuperview()
		renderer = nil
	}
}

/*import SwiftUI
import MetalKit

struct ParsecMetalViewController:UIViewRepresentable
{
	let onBeforeRender:() -> Void
	
	func makeCoordinator() -> ParsecMetalRenderer
	{
		ParsecMetalRenderer(self, onBeforeRender)
	}
	
	func makeUIView(context:UIViewRepresentableContext<ParsecMetalViewController>) -> MTKView
	{
		let metalView = MTKView()
		metalView.delegate = context.coordinator
		metalView.preferredFramesPerSecond = 60
		metalView.enableSetNeedsDisplay = true
		
		if let metalDevice = MTLCreateSystemDefaultDevice()
		{
			metalView.device = metalDevice
		}
		
		metalView.framebufferOnly = false
		metalView.drawableSize = metalView.frame.size
		return metalView
	}
	
	func updateUIView(_ uiView:MTKView, context:UIViewRepresentableContext<ParsecMetalViewController>) { }
}*/
