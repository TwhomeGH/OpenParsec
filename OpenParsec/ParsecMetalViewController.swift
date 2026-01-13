
import SwiftUI
import MetalKit
import UIKit
import ParsecSDK

typealias ParsecRenderer =
ParsecPlayground & ParsecRenderController



// ParsecMetalHolder.swift
class ParsecMetalHolder {
	static var commandQueue: MTLCommandQueue?
	static var texture: MTLTexture?

	static var commandQueuePtr: UnsafeMutableRawPointer?

	// 真正給 C SDK 用的 pointer, 永久持有
	static let texPtrHolder: UnsafeMutablePointer<UnsafeMutableRawPointer?> = {
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



	private var commandQueue: MTLCommandQueue!
	// 自己提供的 target texture
	private var renderTargetTexture: MTLTexture!


	private var myPipelineState: MTLRenderPipelineState!



	var renderView: UIView {
			mtkView
	}



	var lastWidth:CGFloat = 1.0
	var lastHeight:CGFloat = 1.0

	func setupParsecHolder(queue: MTLCommandQueue?, texture: MTLTexture?) {
		guard let queue = queue, let texture = texture else {
			print("❌ queue or texture is nil")
			return
		}

		// 強引用
		ParsecMetalHolder.commandQueue = queue
		ParsecMetalHolder.texture = texture

		ParsecMetalHolder.commandQueuePtr = Unmanaged.passUnretained(queue).toOpaque()


		// ⚡ 這裡必須 cast 成 ParsecMetalTexture
		ParsecMetalHolder.texPtrHolder.pointee = Unmanaged.passUnretained(texture).toOpaque()
	}

	

	// MARK: - Init
	required init(viewController: UIViewController, updateImage: @escaping () -> Void) {
		self.viewController = viewController
		self.updateImage = updateImage
		super.init()
	}

//	private func createParsecTargetTexture(size: CGSize) {
//		let desc = MTLTextureDescriptor.texture2DDescriptor(
//			pixelFormat: .bgra8Unorm,
//			width: Int(size.width),
//			height: Int(size.height),
//			mipmapped: false
//		)
//		desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
//		desc.storageMode = .private
//
//		renderTargetTexture = mtkView.device!.makeTexture(descriptor: desc)
//
//	}


	// MARK: - ParsecPlayground
	func loadViewIfNeeded() {
		mtkView = MTKView(frame: viewController.view.bounds)

		mtkView.device = MTLCreateSystemDefaultDevice()

		guard let device = mtkView.device else {
			fatalError("❌ Metal device not available!")
		}
		print("✅ Metal device available:", device)


		mtkView.isPaused = false
		mtkView.enableSetNeedsDisplay = false
		mtkView.framebufferOnly = false

		mtkView.isHidden = false
		mtkView.backgroundColor = .red // 先給個底色確認有沒有被加到視圖層

		mtkView.preferredFramesPerSecond = preferredFPS


		// 設置 MTKView Delegate
		mtkView.delegate = self


		// 建立 CommandQueue
		commandQueue = mtkView.device!.makeCommandQueue()

		// 4. 加入父 view

		viewController.view.addSubview(mtkView)


		

		DispatchQueue.main.async { [weak self] in
			guard let self = self else { return }
			self.mtkView.contentScaleFactor = self.viewController.view.window?.screen.nativeScale ?? UIScreen.main.nativeScale
			print("✅ MTKView scale set to", self.mtkView.contentScaleFactor)
		}

		// ⚡ 設定靜態 sharedWrapper
		ParsecMetalViewControllerWrapper.sharedWrapper = self



		// 建立 Parsec 專用 target texture
		//createParsecTargetTexture(size: mtkView.drawableSize)




		let library = device.makeDefaultLibrary()
		guard let library = library else {
			fatalError("❌ Failed to load default Metal library")
		}
		print("✅ Default Metal library loaded")

		let vertexFunction = library.makeFunction(name: "vertexShader")
		let fragmentFunction = library.makeFunction(name: "fragmentShader")

		guard let vertexFunction = vertexFunction, let fragmentFunction = fragmentFunction else {
			fatalError("❌ Shader functions not found")
		}
		print("✅ Shader functions found:", vertexFunction.name, fragmentFunction.name)



		let pipelineDescriptor = MTLRenderPipelineDescriptor()
		pipelineDescriptor.vertexFunction = vertexFunction
		pipelineDescriptor.fragmentFunction = fragmentFunction
		pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

		do {
			myPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
			print("✅ Pipeline state created successfully")
		} catch {
			fatalError("❌ Failed to create pipeline state: \(error)")
		}



	}



	func cleanUp() {
		mtkView?.removeFromSuperview()
		mtkView = nil
	}

	func updateSize(width: CGFloat, height: CGFloat) {

		guard let mtkView = mtkView else {
			// renderer 還沒 load view，不要動
			return
		}
		mtkView.drawableSize = CGSize(width: width, height: height)

		//createParsecTargetTexture(size: mtkView.drawableSize)

		setupParsecHolder(queue: commandQueue, texture: renderTargetTexture)
		CParsec.setFrame(width, height, mtkView.contentScaleFactor)
	}

	// MARK: - ParsecRenderController
	func drawFrameCompleted() { framesDisplayedCounter += 1 }
	func getFramesDisplayed() -> Int { framesDisplayedCounter }

	// MARK: - MTKViewDelegate
	func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {

		let scale = view.contentScaleFactor

		let w = size.width  / view.contentScaleFactor
		let h = size.height / view.contentScaleFactor

		CParsec.setFrame(w, h, scale)
		print("Scale:\(scale) \(w)x\(h)")

	}



	// 靜態共享 instance
	static var sharedWrapper: ParsecMetalViewControllerWrapper?

	// C callback

	// Swift 對應 SDK callback，只接受 opaque
	static let preRenderCallback: ParsecPreRenderCallback = { opaque in
		guard let opaque = opaque else { return false }
		let wrapper = Unmanaged<ParsecMetalViewControllerWrapper>.fromOpaque(opaque).takeUnretainedValue()

		guard let cmdQueue = wrapper.commandQueue,
			  let pipeline = wrapper.myPipelineState else {
			return false
		}

		let parsecTexture = wrapper.renderTargetTexture!

		// 建立簡單 render pass
		guard let commandBuffer = cmdQueue.makeCommandBuffer(),
			  let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: {
				  let desc = MTLRenderPassDescriptor()
				  desc.colorAttachments[0].texture = parsecTexture
				  desc.colorAttachments[0].loadAction = .load
				  desc.colorAttachments[0].storeAction = .store
				  return desc
			  }()) else {
			return false
		}

		renderEncoder.setRenderPipelineState(pipeline)
		renderEncoder.endEncoding()
		commandBuffer.commit()

		return true
	}





	func draw(in view: MTKView) {
		guard let commandQueue = commandQueue,
			  let renderTargetTexture = view.currentDrawable
			  else { return }



		// ⚡ 使用 drawable 的 texture
		let texture = renderTargetTexture.texture
		setupParsecHolder(queue: commandQueue, texture: texture)


		// ⚡ Step 1: 先讓 Parsec 把最新幀寫到 texture
		let status = CParsec.renderMetalFrame(
			queue: commandQueue,
			texture: renderTargetTexture.texture,
			preRender: nil,
			opaque: nil,
			timeout: 16
		)
		print("Render->\(status)")

		guard let drawable = view.currentDrawable else { return }

		let renderPassDesc = view.currentRenderPassDescriptor!
		renderPassDesc.colorAttachments[0].loadAction = .clear
		renderPassDesc.colorAttachments[0].storeAction = .store

		guard let commandBuffer = commandQueue.makeCommandBuffer(),
			  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)
		else { return }

		encoder.setRenderPipelineState(myPipelineState)
		encoder.setFragmentTexture(renderTargetTexture.texture, index: 0)


		encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

		encoder.endEncoding()
		commandBuffer.present(drawable)
		commandBuffer.commit()



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
