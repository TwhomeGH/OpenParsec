import UIKit
import GLKit

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
    
    weak var renderController: ParsecRenderController?  // 不再直接綁 GLK
    
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
