import MetalKit
import ParsecSDK
import OSLog

//
//class ParsecMetalRenderer:NSObject, MTKViewDelegate
//{
//	var parent:ParsecMetalViewController
//	var onBeforeRender:() -> Void
//	var metalDevice:MTLDevice!
//	var metalCommandQueue:MTLCommandQueue!
//	var metalTexture:MTLTexture!
//	var metalTexturePtr: UnsafeMutableRawPointer?
//
//	var lastWidth:CGFloat = 1.0
//
//	init(_ parent:ParsecMetalViewController, _ beforeRender:@escaping () -> Void)
//	{
//		self.parent = parent;
//		onBeforeRender = beforeRender
//		if let metalDevice = MTLCreateSystemDefaultDevice()
//		{
//			self.metalDevice = metalDevice
//		}
//		self.metalCommandQueue = metalDevice.makeCommandQueue()
//		metalTexture = metalDevice.makeTexture(descriptor:MTLTextureDescriptor())
//		metalTexturePtr = createTextureRef(&metalTexture)
//
//		super.init()
//	}
//
//	func mtkView(_ view:MTKView, drawableSizeWillChange size: CGSize) { }
//
//	func draw(in view:MTKView)
//	{
//		onBeforeRender()
//		let deltaWidth: CGFloat = view.frame.size.width - lastWidth
//		if deltaWidth > 0.1 || deltaWidth < -0.1
//		{
//			CParsec.setFrame(view.frame.size.width, view.frame.size.height, view.contentScaleFactor)
//			lastWidth = view.frame.size.width
//		}
//		CParsec.renderMetalFrame(&metalCommandQueue, &metalTexturePtr)
//	}
//}




//
//class ParsecMetalRenderer: NSObject, MTKViewDelegate {
//	var mtkView: MTKView
//	var updateImage: () -> Void
//
//	// Metal pipeline
//	private var commandQueue: MTLCommandQueue!
//	private var pipelineState: MTLRenderPipelineState!
//
//	// 紀錄尺寸
//	private var lastWidth: CGFloat = 1.0
//	private var lastHeight: CGFloat = 1.0
//
//	init(_ view: MTKView, updateImage: @escaping () -> Void) {
//		self.mtkView = view
//		self.updateImage = updateImage
//		super.init()
//
//		guard let device = view.device else { fatalError("Metal device not found") }
//
//		// 1️⃣ 建立 CommandQueue
//		commandQueue = device.makeCommandQueue()
//
//		// 2️⃣ 建立簡單 Pipeline (Passthrough shader)
//		if let library = device.makeDefaultLibrary(),
//		   let vertexFunc = library.makeFunction(name: "vertexPassthrough"),
//		   let fragmentFunc = library.makeFunction(name: "fragmentPassthrough") {
//
//			let pipelineDesc = MTLRenderPipelineDescriptor()
//			pipelineDesc.vertexFunction = vertexFunc
//			pipelineDesc.fragmentFunction = fragmentFunc
//			pipelineDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
//
//			do {
//				pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDesc)
//			} catch {
//				fatalError("Failed to create pipeline state: \(error)")
//			}
//		} else {
//			fatalError("Failed to load default Metal library or functions")
//		}
//
//		// 3️⃣ MTKView 設置
//		view.delegate = self
//		view.enableSetNeedsDisplay = false
//		view.isPaused = false
//		view.framebufferOnly = false
//		view.colorPixelFormat = .bgra8Unorm
//	}
//
//	func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
//		lastWidth = size.width
//		lastHeight = size.height
//		CParsec.setFrame(size.width, size.height, view.contentScaleFactor)
//	}
//
//	func draw(in view: MTKView) {
//		let newWidth = view.drawableSize.width
//		let newHeight = view.drawableSize.height
//
//		// 1️⃣ 更新尺寸
//		if newWidth != lastWidth || newHeight != lastHeight {
//			CParsec.setFrame(newWidth, newHeight, view.contentScaleFactor)
//			lastWidth = newWidth
//			lastHeight = newHeight
//		}
//
//		guard let drawable = view.currentDrawable else { return }
//
//		// 2️⃣ 用 Parsec render 到 drawable.texture
//		CParsec.renderMetalFrame(queue: commandQueue, drawable: drawable)
//
//		// 3️⃣ 用 pipeline 把 texture 畫到 screen
//		guard let renderPass = view.currentRenderPassDescriptor,
//			  let commandBuffer = commandQueue.makeCommandBuffer() else { return }
//
//		let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)!
//		encoder.setRenderPipelineState(pipelineState)
//		encoder.setFragmentTexture(drawable.texture, index: 0)
//		encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
//		encoder.endEncoding()
//
//		commandBuffer.present(drawable)
//		commandBuffer.commit()
//
//		// 4️⃣ 通知 wrapper frame 已完成
//		if let wrapper = mtkView.delegate as? ParsecMetalViewControllerWrapper {
//			wrapper.drawFrameCompleted()
//		}
//
//		// 5️⃣ callback
//		updateImage()
//	}
//}


//class ParsecMetalRendererold: NSObject, MTKViewDelegate {
//    var mtkView: MTKView
//    var updateImage: () -> Void
//    var lastWidth: CGFloat = 1.0
//	var lastHeight: CGFloat = 1.0
//
//
//	// Metal pipeline
//	var commandQueue: MTLCommandQueue!
//	var pipelineState: MTLRenderPipelineState!
//
//
//
//
//    init(_ view: MTKView, updateImage: @escaping () -> Void) {
//
//
//		self.mtkView = view
//        self.updateImage = updateImage
//
//		super.init()
//
//		guard let device = view.device else { fatalError("Metal device not found") }
//		commandQueue = device.makeCommandQueue()
//
//		// 建立簡單 pipeline，把 texture 畫到 screen
//		let library = device.makeDefaultLibrary()
//		let vertexFunc = library?.makeFunction(name: "vertexPassthrough")
//		let fragmentFunc = library?.makeFunction(name: "fragmentPassthrough")
//
//		let pipelineDesc = MTLRenderPipelineDescriptor()
//		pipelineDesc.vertexFunction = vertexFunc
//		pipelineDesc.fragmentFunction = fragmentFunc
//		pipelineDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
//
//		pipelineState = try? device.makeRenderPipelineState(descriptor: pipelineDesc)
//
//
//
//        view.delegate = self
//
//
//
//
//
//    }
//    
//	func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
//		CParsec.setFrame(size.width, size.height, view.contentScaleFactor)
//
//		lastWidth = size.width
//		lastHeight = size.height
//
//
//	}
//
//
//
//	func draw(in view: MTKView) {
//		let newWidth = view.drawableSize.width
//		let newHeight = view.drawableSize.height
//
//		if newWidth != lastWidth || newHeight != lastHeight {
//			CParsec.setFrame(newWidth, newHeight, view.contentScaleFactor)
//			lastWidth = newWidth
//			lastHeight = newHeight
//		}
//
//		guard let drawable = view.currentDrawable else { return }
//
//		CParsec.renderMetalFrame(
//			queue: commandQueue, drawable: drawable
//		)
//
//		drawable.present()
//
//		// 2️⃣ 畫到 screen
////		guard let commandBuffer = commandQueue.makeCommandBuffer(),
////			  let renderPass = view.currentRenderPassDescriptor else {
////			return
////		}
////
////		let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)!
////		encoder.setRenderPipelineState(pipelineState)
////
////		// 設定 drawable texture
////		encoder.setFragmentTexture(drawable.texture, index: 0)
////
////		// 畫 full screen quad
////		encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
////		encoder.endEncoding()
////
////		commandBuffer.present(drawable)
////		commandBuffer.commit()
//
//
//
//
//
//
////		os_log("Drawable texture size: \(drawable.texture.width)x\(drawable.texture.height)")
////		os_log("Drawable pixel format: \(drawable.texture.pixelFormat.rawValue)")
////
//
//
//		if let wrapper = mtkView.delegate as? ParsecMetalViewControllerWrapper {
//			wrapper.drawFrameCompleted()
//		}
//
//		updateImage()
//	}
//
//}


//
//class ParsecMetalRenderer:NSObject, MTKViewDelegate
//{
//	var parent:ParsecMetalViewControllerWrapper
//	var onBeforeRender:() -> Void
//	var metalDevice:MTLDevice!
//	var metalCommandQueue:MTLCommandQueue!
//	var metalTexture:MTLTexture!
//	var metalTexturePtr:UnsafeMutableRawPointer?
//	
//	var lastWidth:CGFloat = 1.0
//
//	init(
//		_ parent:ParsecMetalViewControllerWrapper,
//		_ beforeRender:@escaping () -> Void
//	)
//	{
//		self.parent = parent;
//		onBeforeRender = beforeRender
//		if let metalDevice = MTLCreateSystemDefaultDevice()
//		{
//			self.metalDevice = metalDevice
//		}
//		self.metalCommandQueue = metalDevice.makeCommandQueue()
//		metalTexture = metalDevice.makeTexture(descriptor:MTLTextureDescriptor())
//		metalTexturePtr = createTextureRef(&metalTexture)
//		
//		super.init()
//	}
//	
//	func mtkView(_ view:MTKView, drawableSizeWillChange size:CGSize) { }
//	
//	func draw(in view:MTKView)
//	{
//		onBeforeRender()
//		let deltaWidth: CGFloat = view.frame.size.width - lastWidth
//		if deltaWidth > 0.1 || deltaWidth < -0.1
//		{
//			CParsec.setFrame(view.frame.size.width, view.frame.size.height, view.contentScaleFactor)
//			lastWidth = view.frame.size.width
//		}
//		CParsec.renderMetalFrame(&metalCommandQueue, &metalTexturePtr)
//	}
//}



