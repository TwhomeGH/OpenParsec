
import SwiftUI
import MetalKit
import UIKit
import ParsecSDK

typealias ParsecRenderer =
ParsecPlayground & ParsecRenderController


final class ParsecMetalTarget {
	static let shared = ParsecMetalTarget()

	var cqQueue:MTLCommandQueue?

	var texture: MTLTexture? = nil

	// ⚠️ 給 C SDK 用的 **指標位址**
	let texturePtr: UnsafeMutablePointer<UnsafeMutableRawPointer?> = {
		let p = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 1)
		p.initialize(to: nil)
		return p
	}()
}




class ParsecMetalViewControllerWrapper: NSObject, ParsecPlayground, ParsecRenderController, MTKViewDelegate {

	// MARK: - Properties
	let viewController: UIViewController
	var mtkView: MTKView!
	var preferredFPS: Int = 60 {
		didSet { mtkView?.preferredFramesPerSecond = preferredFPS }
	}
	var updateImage: () -> Void
	private var framesDisplayedCounter = 0

	private var commandQueue: MTLCommandQueue?

	private var metalDevice: MTLDevice!

	// 自己持有的 Parsec target texture
	private var metalTexture: MTLTexture?

	private var lastWidth: CGFloat = 1.0
	private var lastHeight: CGFloat = 1.0

	func createParsecTexture(
		device: MTLDevice,
		width: Int,
		height: Int
	) {
		let desc = MTLTextureDescriptor.texture2DDescriptor(
			pixelFormat: .bgra8Unorm,
			width: width,
			height: height,
			mipmapped: false
		)

		desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
		desc.storageMode = .shared

		let tex = device.makeTexture(descriptor: desc)!

		// Swift 強引用
		ParsecMetalTarget.shared.texture = tex

		// ⚠️ C SDK 用的指標
		ParsecMetalTarget.shared.texturePtr.pointee =
			Unmanaged.passUnretained(tex).toOpaque()
	}


	// MARK: - Init
	required init(viewController: UIViewController, updateImage: @escaping () -> Void) {
		self.viewController = viewController
		self.updateImage = updateImage

		super.init()


		metalDevice = MTLCreateSystemDefaultDevice()


		ParsecMetalTarget.shared.cqQueue = metalDevice.makeCommandQueue()

		self.createParsecTexture(
			device: metalDevice,
			width: Int(viewController.view.frame.width + 4),
			height: Int(viewController.view.frame.height + 4)
		)







	}


	

	var renderView: UIView { mtkView }

	// MARK: - Setup
	func loadViewIfNeeded() {
		mtkView = MTKView(frame: viewController.view.bounds)

		mtkView.colorPixelFormat = .bgra8Unorm
		mtkView.device = metalDevice
		mtkView.isPaused = false
		mtkView.enableSetNeedsDisplay = false
		mtkView.framebufferOnly = false
		mtkView.isHidden = false
		mtkView.backgroundColor = .red
		mtkView.preferredFramesPerSecond = preferredFPS
		mtkView.delegate = self


		viewController.view.addSubview(mtkView)

		DispatchQueue.main.async { [weak self] in
			guard let self = self else { return }
			self.mtkView.contentScaleFactor = self.viewController.view.window?.screen.nativeScale ?? UIScreen.main.nativeScale
		}


		ParsecMetalViewControllerWrapper.sharedWrapper = self
	}

	private func aligned(_ x: Int) -> Int { return (x + 1) & ~1 } // 對齊到偶數

	func updateSize(width: CGFloat, height: CGFloat) {
		guard let view = mtkView else { return }

		let deltaW = abs(width - lastWidth)
		let deltaH = abs(height - lastHeight)
		if deltaW > 1 || deltaH > 1 {
			lastWidth = width
			lastHeight = height

			DispatchQueue.main.async { [weak self] in
				guard self != nil else { return }


				CParsec.setFrame(width, height, view.contentScaleFactor)

				print("SCALE",view.contentScaleFactor)
				print("Width:\(width)x\(height)")

			}
		}
	}

	// MARK: - ParsecRenderController
	func drawFrameCompleted() { framesDisplayedCounter += 1 }
	func getFramesDisplayed() -> Int { framesDisplayedCounter }

	// MARK: - MTKViewDelegate
	func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
		updateSize(width: size.width, height: size.height)
	}

	func draw(in view: MTKView) {



		let deltaWidth: CGFloat = view.frame.size.width - lastWidth
		if deltaWidth > 0.1 || deltaWidth < -0.1
		{
			CParsec.setFrame(view.frame.size.width, view.frame.size.height, view.contentScaleFactor)
			lastWidth = view.frame.size.width
			print("SCALE",view.contentScaleFactor)
			print("Width:\(view.frame.size.width)x\( view.frame.size.height)")
		}
		

		let cq = ParsecMetalTarget.shared.cqQueue!
		let tex = ParsecMetalTarget.shared.texture!


		print("MTL Device:", metalDevice ?? "none")
		print("CQ Device",String(describing: cq.device))
		print("TEX Device",String(describing: tex.device))




		DispatchQueue.main.async {

			// 渲染 Parsec 到自持有 texture
			let status = CParsec.renderMetalFrame(
				queue: cq ,
				texture: tex,
				timeout: 16
			)

			print("Parsec render status:", status)


		}



		
		drawFrameCompleted()
		updateImage()
	}

	func olddraw(in view: MTKView) {
		guard let drawable = view.currentDrawable,
			  let rpd = view.currentRenderPassDescriptor,
			  let commandQueue = commandQueue else {
			return
		}

		// 🔴 清成紅色
		rpd.colorAttachments[0].clearColor =
			MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1)
		rpd.colorAttachments[0].loadAction = .clear
		rpd.colorAttachments[0].storeAction = .store

		let commandBuffer = commandQueue.makeCommandBuffer()!
		let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd)!
		encoder.endEncoding()

		commandBuffer.present(drawable)
		commandBuffer.commit()

		print("TEX size:", drawable.texture.width, drawable.texture.height )

		print("TEX type:", String(describing: drawable.texture.textureType) )

		print("TEX format:", String(describing: drawable.texture.pixelFormat) )




	}

	// MARK: - Clean
	func cleanUp() {
		mtkView?.removeFromSuperview()
		mtkView = nil
		metalTexture = nil
	}

	// MARK: - Shared
	static var sharedWrapper: ParsecMetalViewControllerWrapper?
}


//
//class ParsecMetalViewControllerWrapper: NSObject, ParsecPlayground, ParsecRenderController, MTKViewDelegate {
//
//	// MARK: - Properties
//	let viewController: UIViewController
//	var mtkView: MTKView!
//	var preferredFPS: Int = 60 {
//		didSet { mtkView?.preferredFramesPerSecond = preferredFPS }
//	}
//	var updateImage: () -> Void
//	private var framesDisplayedCounter = 0
//
//
//
//	private var commandQueue: MTLCommandQueue!
//
//
//	var renderView: UIView {
//			mtkView
//	}
//
//
//
//	var lastWidth:CGFloat = 1.0
//	var lastHeight:CGFloat = 1.0
//
//	func setupParsecHolder(queue: MTLCommandQueue?, texture: MTLTexture?) {
//		guard let queue = queue, let texture = texture else {
//			print("❌ queue or texture is nil")
//			return
//		}
//
//		// 強引用
//		ParsecMetalHolder.commandQueue = queue
//		ParsecMetalHolder.texture = texture
//
//		ParsecMetalHolder.commandQueuePtr = Unmanaged.passUnretained(queue).toOpaque()
//
//
//		// ⚡ 這裡必須 cast 成 ParsecMetalTexture
//		ParsecMetalHolder.texPtrHolder.pointee = Unmanaged.passUnretained(texture).toOpaque()
//	}
//
//	
//
//	// MARK: - Init
//	required init(viewController: UIViewController, updateImage: @escaping () -> Void) {
//		self.viewController = viewController
//		self.updateImage = updateImage
//		super.init()
//	}
//
////	private func createParsecTargetTexture(size: CGSize) {
////		let desc = MTLTextureDescriptor.texture2DDescriptor(
////			pixelFormat: .bgra8Unorm,
////			width: Int(size.width),
////			height: Int(size.height),
////			mipmapped: false
////		)
////		desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
////		desc.storageMode = .private
////
////		renderTargetTexture = mtkView.device!.makeTexture(descriptor: desc)
////
////	}
//
//
//	// MARK: - ParsecPlayground
//	func loadViewIfNeeded() {
//		mtkView = MTKView(frame: viewController.view.bounds)
//
//		mtkView.device = MTLCreateSystemDefaultDevice()
//
//		guard let device = mtkView.device else {
//			fatalError("❌ Metal device not available!")
//		}
//		print("✅ Metal device available:", device)
//
//
//		mtkView.isPaused = false
//		mtkView.enableSetNeedsDisplay = false
//		mtkView.framebufferOnly = false
//
//		mtkView.isHidden = false
//		mtkView.backgroundColor = .red // 先給個底色確認有沒有被加到視圖層
//
//		mtkView.preferredFramesPerSecond = preferredFPS
//
//
//		// 設置 MTKView Delegate
//		mtkView.delegate = self
//
//
//		// 建立 CommandQueue
//		commandQueue = mtkView.device!.makeCommandQueue()
//
//		// 4. 加入父 view
//
//		viewController.view.addSubview(mtkView)
//
//
//		
//
//		DispatchQueue.main.async { [weak self] in
//			guard let self = self else { return }
//			self.mtkView.contentScaleFactor = self.viewController.view.window?.screen.nativeScale ?? UIScreen.main.nativeScale
//			print("✅ MTKView scale set to", self.mtkView.contentScaleFactor)
//		}
//
//		// ⚡ 設定靜態 sharedWrapper
//		ParsecMetalViewControllerWrapper.sharedWrapper = self
//
//
//
//
//
//	}
//
//
//
//	func cleanUp() {
//		mtkView?.removeFromSuperview()
//		mtkView = nil
//	}
//
//	func updateSize(width: CGFloat, height: CGFloat) {
//
//		guard let mtkView = mtkView else {
//			// renderer 還沒 load view，不要動
//			return
//		}
//		mtkView.drawableSize = CGSize(width: width, height: height)
//
//
//		CParsec.setFrame(width, height, mtkView.contentScaleFactor)
//	}
//
//	// MARK: - ParsecRenderController
//	func drawFrameCompleted() { framesDisplayedCounter += 1 }
//	func getFramesDisplayed() -> Int { framesDisplayedCounter }
//
//	// MARK: - MTKViewDelegate
//	func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
//
//		let scale = view.contentScaleFactor
//
//		let w = size.width  / view.contentScaleFactor
//		let h = size.height / view.contentScaleFactor
//
//		CParsec.setFrame(w, h, scale)
//		print("Scale:\(scale) \(w)x\(h)")
//
//	}
//
//
//
//	// 靜態共享 instance
//	static var sharedWrapper: ParsecMetalViewControllerWrapper?
//
//
//
//	func draw(in view: MTKView) {
//
//		guard
//			let drawable = view.currentDrawable,
//			let commandQueue = commandQueue
//		else { return }
//
//		let texture = drawable.texture
//
//		// 更新 Parsec holder（指標必須長生命週期，你已經做對）
//		setupParsecHolder(queue: commandQueue, texture: texture)
//
//		// ⚡ Parsec 會直接 render 到 drawable.texture
//		let status = CParsec.renderMetalFrame(
//			queue: commandQueue,
//			texture: texture,
//			preRender: nil,
//			opaque: nil,
//			timeout: 16
//		)
//
//		print("Parsec render status:", status)
//
//		// ⚠️ 不要自己再畫、不要 present
//		// MTKView 會在內部 display link 幫你處理
//
//		drawFrameCompleted()
//		updateImage()
//	}
//}

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
