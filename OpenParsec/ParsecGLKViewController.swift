import UIKit
import GLKit

import OSLog

protocol ParsecRenderController : AnyObject {
    var preferredFPS: Int { get set }
    func getFramesDisplayed() -> Int
}

extension ParsecGLKViewController: ParsecRenderController {
    var preferredFPS: Int {
        get { glkViewController.preferredFramesPerSecond }
        set { glkViewController.preferredFramesPerSecond = newValue }
    }
    
    func getFramesDisplayed() -> Int {
        return glkViewController.framesDisplayed
    }
}

final class ParsecRenderCenter {
    static let shared = ParsecRenderCenter()
    
	weak var renderController: ParsecRenderController? // FPS檢測

	weak var viewController: ParsecViewController? // Metal/OpenGL


	var rendererType: RendererType = SettingsHandler.renderer

	private(set) var isInitialized = false
	private(set) var isClientInitialized = false

	private var rendererReady = false
	private var clientReady = false

	private var pendingResolutionUpdate = false
	private var pendingBitrateUpdate = false

	func requestResolutionUpdate() {
		pendingResolutionUpdate = true
		applyIfPossible()
	}

	func requestBitrateUpdate() {
		pendingBitrateUpdate = true
		applyIfPossible()
	}

	func setMuted(_ muted: Bool) {
		CParsec.setMuted(muted)
	}

	func applyIfPossible() {
		guard rendererReady, clientReady else { return }

		if pendingResolutionUpdate {

			CParsec.updateHostVideoConfig()
			updateNativeResolutionIfNeeded()
			pendingResolutionUpdate = false
		}

		if pendingBitrateUpdate {
			CParsec.updateHostVideoConfig()
			pendingBitrateUpdate = false
		}
	}

	func onRendererReady(size: CGSize, scale: CGFloat) {
		guard !rendererReady else { return }

		rendererReady = true

		CParsec.setFrame(
			CGFloat(Int(size.width)),
			CGFloat(Int(size.height)),
			scale
		)

		applyIfPossible()
		os_log("✅ Renderer ready")
	}
	


	func updateNativeResolutionIfNeeded() {
		guard let vc = viewController else { return }

		let size = vc.view.bounds.size
		guard size.width > 0, size.height > 0 else { return }

		let scale = UIScreen.main.nativeScale
		let w = Int(size.width * scale)
		let h = Int(size.height * scale)

		let cur = ParsecResolution.resolutions[1]
		guard cur.width != w || cur.height != h else { return }

		ParsecResolution.resolutions[1].width = w
		ParsecResolution.resolutions[1].height = h

		os_log("📐 Native resolution updated: %dx%d", w, h)
	}

	func start(muted: Bool) {
		guard !isInitialized else {
			os_log("⚠️ ParsecRenderCenter already initialized")
			return
		}

		initRenderer()
		initCParsec(muted: muted)

		isInitialized = true
		isClientInitialized = true
	}

	func shutdown() {
		CParsec.disconnect()

		viewController?.renderer.cleanUp()
		viewController = nil
		renderController = nil

		isInitialized = false
		isClientInitialized = false
		didNotifyRendererReady = false
		
		os_log("🧹 ParsecRenderCenter shutdown complete")
	}

	private var didNotifyRendererReady = false

	func notifyRendererReadyIfNeeded(from vc: ParsecViewController) {
		guard !didNotifyRendererReady else { return }

		let size = vc.view.bounds.size
		guard size.width > 0, size.height > 0 else { return }

		didNotifyRendererReady = true
		rendererReady = true

		// renderer 此時一定已存在
		renderController = vc.renderer

		updateNativeResolutionIfNeeded()

		os_log("✅ Renderer ready, layout confirmed")
	}

	func getHostUserData() {
		let data = "".data(using: .utf8)!
		CParsec.sendUserData(type: .getVideoConfig, message: data)
		CParsec.sendUserData(type: .getAdapterInfo, message: data)
	}
	
	func initCParsec(muted: Bool) {

			os_log("初始化客戶端")
			CParsec.applyConfig()
			CParsec.setMuted(muted)
			getHostUserData()

			clientReady = true

		}


	// MARK: - 初始化或切換 Renderer
	func initRenderer() {
		guard viewController == nil else { return }

		let controller = ParsecViewController()

		controller.renderer = controller.createRenderer(type: rendererType)

		viewController = controller
	}

	func switchRenderer(to type: RendererType) {
		rendererType = type

		viewController?.switchRenderer(to: type)
		SettingsHandler.renderer = type
		SettingsHandler.save()
	}



    func updateFPS(_ fps: Int) {
        renderController?.preferredFPS = fps
    }
    
    func currentFPS() -> Int {
        return renderController?.preferredFPS ?? 60
    }

    // MARK: - 實際送出 FPS 計算
    private var startTime: CFTimeInterval = CACurrentMediaTime()
    private var lastFramesDisplayed: Int = 0

    /// 從開始到現在的平均實際 FPS
    func actualFPS() -> Double {
        guard let controller = renderController else { return 0 }
        let now = CACurrentMediaTime()
        let elapsed = now - startTime
        guard elapsed > 0 else { return 0 }

        let frames = Double(controller.getFramesDisplayed())
        return frames / elapsed
    }

    /// 從上次呼叫到現在的增量 FPS（可每秒更新顯示）
    func deltaFPS() -> Double {
        guard let controller = renderController else { return 0 }
        let now = CACurrentMediaTime()
        let elapsed = now - startTime
        guard elapsed > 0 else { return 0 }

        let deltaFrames = Double(controller.getFramesDisplayed() - lastFramesDisplayed)
        lastFramesDisplayed = controller.getFramesDisplayed()
        startTime = now

        return deltaFrames / elapsed
    }
}

class ParsecGLKViewController : ParsecPlayground {

	var glkView: GLKView!
	let glkViewController = GLKViewController()
	var glkRenderer: ParsecGLKRenderer!
	let updateImage:() -> Void
	
	let viewController: UIViewController
	
	required init(viewController: UIViewController, updateImage: @escaping () -> Void) {
		self.viewController = viewController
		self.updateImage = updateImage
	}

	public func viewDidLoad() {
		glkView = GLKView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height))
		glkRenderer = ParsecGLKRenderer(glkView, glkViewController, updateImage)
		
		self.viewController.view.addSubview(glkView)
		setupGLKViewController()
		

	}

	private func setupGLKViewController() {
		glkView.context = EAGLContext(api: .openGLES3)!
		glkViewController.view = glkView
		glkViewController.preferredFramesPerSecond = SettingsHandler.fpsPerFrame
		self.viewController.addChild(glkViewController)
		self.viewController.view.addSubview(glkViewController.view)
		self.glkViewController.didMove(toParent: self.viewController)
		
	}

	
	func cleanUp() {
		
	}
	
	func updateSize(width: CGFloat, height: CGFloat) {
		glkView.frame.size.width = width
		glkView.frame.size.height = height
	}

	
}
