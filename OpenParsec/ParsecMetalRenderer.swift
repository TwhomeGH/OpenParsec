import MetalKit
import ParsecSDK



class ParsecMetalRenderer: NSObject, MTKViewDelegate {
    var mtkView: MTKView
    var updateImage: () -> Void
    var lastWidth: CGFloat = 1.0
    
    init(_ view: MTKView, updateImage: @escaping () -> Void) {
        self.mtkView = view
        self.updateImage = updateImage
        super.init()
        view.delegate = self
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // 可以根據大小改變 Metal 的 framebuffer，如果需要
    }
    
    func draw(in view: MTKView) {
        let deltaWidth = view.frame.size.width - lastWidth
        if abs(deltaWidth) > 0.1 {
            CParsec.setFrame(view.frame.size.width, view.frame.size.height, view.contentScaleFactor)
            lastWidth = view.frame.size.width
        }

	    guard let commandQueue = view.device?.makeCommandQueue(),
          let commandBuffer = commandQueue.makeCommandBuffer(),
          let drawable = view.currentDrawable else { return }

        
        
        // 呼叫 Parsec Metal Render
		CParsec.renderMetalFrame(commandBuffer, drawable.texture)
	
		commandBuffer.present(drawable)
		commandBuffer.commit()
		
        updateImage()
    }
}


/*import MetalKit
import ParsecSDK

class ParsecMetalRenderer:NSObject, MTKViewDelegate
{
	var parent:ParsecMetalViewController
	var onBeforeRender:() -> Void
	var metalDevice:MTLDevice!
	var metalCommandQueue:MTLCommandQueue!
	var metalTexture:MTLTexture!
	var metalTexturePtr:UnsafeMutableRawPointer?
	
	var lastWidth:CGFloat = 1.0

	init(_ parent:ParsecMetalViewController, _ beforeRender:@escaping () -> Void)
	{
		self.parent = parent;
		onBeforeRender = beforeRender
		if let metalDevice = MTLCreateSystemDefaultDevice()
		{
			self.metalDevice = metalDevice
		}
		self.metalCommandQueue = metalDevice.makeCommandQueue()
		metalTexture = metalDevice.makeTexture(descriptor:MTLTextureDescriptor())
		metalTexturePtr = createTextureRef(&metalTexture)
		
		super.init()
	}
	
	func mtkView(_ view:MTKView, drawableSizeWillChange size:CGSize) { }
	
	func draw(in view:MTKView)
	{
		onBeforeRender()
		let deltaWidth: CGFloat = view.frame.size.width - lastWidth
		if deltaWidth > 0.1 || deltaWidth < -0.1
		{
			CParsec.setFrame(view.frame.size.width, view.frame.size.height, view.contentScaleFactor)
			lastWidth = view.frame.size.width
		}
		CParsec.renderMetalFrame(&metalCommandQueue, &metalTexturePtr)
	}
}*/
