
import SwiftUI
import MetalKit
import UIKit

typealias ParsecRenderer =
	ParsecPlayground & ParsecRenderController


class ParsecMetalViewControllerWrapper: NSObject, ParsecPlayground, ParsecRenderController, MTKViewDelegate {

	// MARK: - Properties
	let viewController: UIViewController
	var mtkView: MTKView!
	var preferredFPS: Int = 60 {
		didSet { mtkView?.preferredFramesPerSecond = preferredFPS }
	}
	var updateImage: () -> Void
	private var framesDisplayedCounter = 0
	private var commandQueue: MTLCommandQueue!


	var lastWidth:CGFloat = 1.0
	var lastHeight:CGFloat = 1.0


	// MARK: - Init
	required init(viewController: UIViewController, updateImage: @escaping () -> Void) {
		self.viewController = viewController
		self.updateImage = updateImage
		super.init()
	}

	// MARK: - ParsecPlayground
	func viewDidLoad() {
		mtkView = MTKView(frame: viewController.view.bounds)
		mtkView.device = MTLCreateSystemDefaultDevice()
		mtkView.isPaused = false
		mtkView.enableSetNeedsDisplay = false
		mtkView.framebufferOnly = false
		mtkView.colorPixelFormat = .bgra8Unorm
		mtkView.preferredFramesPerSecond = preferredFPS
		viewController.view.addSubview(mtkView)

		// 設置 MTKView Delegate
		mtkView.delegate = self

		// 建立 CommandQueue
		commandQueue = mtkView.device!.makeCommandQueue()
	}

	func cleanUp() {
		mtkView?.removeFromSuperview()
		mtkView = nil
	}

	func updateSize(width: CGFloat, height: CGFloat) {
		mtkView.drawableSize = CGSize(width: width, height: height)
		CParsec.setFrame(width, height, mtkView.contentScaleFactor)
	}

	// MARK: - ParsecRenderController
	func drawFrameCompleted() { framesDisplayedCounter += 1 }
	func getFramesDisplayed() -> Int { framesDisplayedCounter }

	// MARK: - MTKViewDelegate
	func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {

		let scale = view.contentScaleFactor
		CParsec.setFrame(size.width, size.height, scale)
		print("Scale:\(scale) \(size.width)x\(size.height)")
	}

	func draw(in view: MTKView) {
		guard let drawable = view.currentDrawable else { return }

		let width = view.drawableSize.width / view.contentScaleFactor
		let height = view.drawableSize.height / view.contentScaleFactor
		let scale = view.contentScaleFactor


		// 每幀檢查尺寸，如果不同就呼叫 setFrame
		if abs(width - lastWidth) > 0.1 || abs(height - lastHeight) > 0.1 {
			CParsec.setFrame(width, height, scale) // 這裡 scale 用 1.0
			lastWidth = width
			lastHeight = height
			print("SetFrame called: \(width)x\(height) \(scale)")
		}


		
		// 渲染到 drawable.texture
		CParsec.renderMetalFrame(queue: commandQueue, drawable: drawable)

		// 顯示
		drawable.present()

		// 更新計數 & 回調
		drawFrameCompleted()
		updateImage()
	}
}

//
//class ParsecMetalViewControllerWrapper : ParsecPlayground,ParsecRenderController {
//    let viewController: UIViewController
//    var mtkView: MTKView!
//    var renderer: ParsecMetalRenderer!
//    
//    var updateImage: () -> Void
//
//	private var framesDisplayedCounter: Int = 0
//    
//    var preferredFPS: Int {
//        get { mtkView.preferredFramesPerSecond }
//        set { mtkView.preferredFramesPerSecond = newValue }
//    }
//    
//    func drawFrameCompleted() {
//        framesDisplayedCounter += 1
//    }
//    
//    func getFramesDisplayed() -> Int {
//        return framesDisplayedCounter
//    }
//
//    
//	required init(
//		viewController: UIViewController,
//		updateImage: @escaping () -> Void
//	) {
//        self.viewController = viewController
//        self.updateImage = updateImage
//    }
//    
//    func viewDidLoad() {
//        mtkView = MTKView(frame: viewController.view.bounds)
//        mtkView.device = MTLCreateSystemDefaultDevice()
//		mtkView.enableSetNeedsDisplay = false
//		mtkView.isPaused = false
//
//		mtkView.colorPixelFormat = .bgra8Unorm
//
//        mtkView.preferredFramesPerSecond = SettingsHandler.fpsPerFrame
//
//		mtkView.clearColor = MTLClearColor(
//			red: 1.0,
//			green: 0.0,
//			blue: 0.0,
//			alpha: 1.0
//		)
//
//		mtkView.framebufferOnly = false
//
//        renderer = ParsecMetalRenderer(mtkView, updateImage: updateImage)
//        viewController.view.addSubview(mtkView)
//    }
//    
//	func updateSize(width: CGFloat, height: CGFloat) {
//		mtkView.frame.size = CGSize(width: width, height: height)
//		mtkView.drawableSize = CGSize(width: width, height: height) 
//	}
//
//	func cleanUp() {
//		mtkView?.removeFromSuperview()
//		renderer = nil
//	}
//}
//


/*import SwiftUI
import MetalKit

struct ParsecMetalViewController: UIViewRepresentable
{
	let onBeforeRender:() -> Void
	
	func makeCoordinator() -> ParsecMetalRenderer
	{
		ParsecMetalRenderer(self, onBeforeRender)
	}
	
	func makeUIView(context: UIViewRepresentableContext<ParsecMetalViewController>) -> MTKView
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
	
	func updateUIView(_ uiView:MTKView, context: UIViewRepresentableContext<ParsecMetalViewController>) { }
}*/
