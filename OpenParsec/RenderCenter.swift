//
//  RenderCenter.swift
//  OpenParsec
//
//  Created by user on 2026/1/12.
//

import UIKit
import GLKit

import OSLog


protocol ParsecRenderController : AnyObject {
	var preferredFPS: Int { get set }
	var DebugMes: String { get set }
	var view: UIView { get set }
	var viewController: UIViewController { get set }

	func getFramesDisplayed() -> Int

}

extension ParsecGLKViewController: ParsecRenderController {
	var preferredFPS: Int {
		get { glkViewController.preferredFramesPerSecond }
		set { glkViewController.preferredFramesPerSecond = newValue }
	}
	
	var view: UIView {
		get { glkView }
		set { glkView = newValue as? GLKView }
	}

	var viewController: UIViewController {
		get { glkViewController }
		set { glkViewController.view = newValue.view }
	}


	var glContext: EAGLContext? {
		return glkView?.context
	}

	var DebugMes: String {
		get { _debugMES }
		set { _debugMES = newValue }
	}

	func getFramesDisplayed() -> Int {
		return glkViewController.framesDisplayed
	}
}



final class ParsecRenderCenter {
	static let shared = ParsecRenderCenter()

	var renderController: ParsecRenderController? // FPS檢測

	var viewController: ParsecViewController? // Metal/OpenGL


	var rendererType: RendererType = SettingsHandler.shared.renderer

	private(set) var isInitialized = false
	private(set) var isClientInitialized = false

	private var rendererReady = false
	private var clientReady = false

	private var pendingResolutionUpdate = false
	private var pendingBitrateUpdate = false

	private func applyDefaultVideoSettings() {
		DataManager.model.resolutionX = SettingsHandler.shared.resolution.width
		DataManager.model.resolutionY = SettingsHandler.shared.resolution.height

		if SettingsHandler.shared.bitrate != 0 {
			DataManager.model.bitrate = SettingsHandler.shared.bitrate
		}
	}

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
		updateClientResolution(size: size, scale: scale)

		CParsec.setFrame(
			CGFloat(Int(size.width)),
			CGFloat(Int(size.height)),
			scale
		)

		applyIfPossible()
		os_log("✅ Renderer ready")
	}

	private func updateClientResolution(size: CGSize, scale: CGFloat) {
		guard size.width > 0, size.height > 0 else { return }

		let w = Int(size.width * scale)
		let h = Int(size.height * scale)
		ParsecResolution.updateClientResolution(width: w, height: h)

		if SettingsHandler.shared.resolution == .client {
			DataManager.model.resolutionX = w
			DataManager.model.resolutionY = h
		}

		os_log("📐 Client resolution updated: %dx%d", w, h)
	}



	func updateNativeResolutionIfNeeded() {
		guard let vc = viewController else { return }

		let size = vc.view.bounds.size
		guard size.width > 0, size.height > 0 else { return }

		let scale = UIScreen.main.nativeScale
		let w = Int(size.width * scale)
		let h = Int(size.height * scale)

		ParsecResolution.updateClientResolution(width: w, height: h)

		if SettingsHandler.shared.resolution == .client {
			DataManager.model.resolutionX = w
			DataManager.model.resolutionY = h
		}

		os_log("📐 Native resolution updated: %dx%d", w, h)
	}

	func start(muted: Bool = false) {
		guard !isInitialized else {
			os_log("⚠️ ParsecRenderCenter already initialized")
			return
		}

		initCParsec(muted: muted)

		DataManager.model.constantFps = SettingsHandler.shared.savedConstantFps
		
		write_log_from_swift("muted \(muted ? "true" : "false")")
		write_log_from_swift("constantFps \(DataManager.model.constantFps ? "true" : "false")")


		isInitialized = true
		isClientInitialized = true
	}

	func shutdown() {

		CParsec.disconnect()

		viewController?.shutdownRenderer()

		renderController = nil

		isInitialized = false
		isClientInitialized = false
		didNotifyRendererReady = false

		rendererReady = false
		clientReady = false

		os_log("🧹 ParsecRenderCenter shutdown complete")
	}

	private var didNotifyRendererReady = false

	func notifyRendererReadyIfNeeded(from vc: ParsecViewController) {
		guard !didNotifyRendererReady else { return }

		let size = vc.view.bounds.size
		guard size.width > 0, size.height > 0 else { return }

		didNotifyRendererReady = true
		rendererReady = true

		updateNativeResolutionIfNeeded()

		os_log("✅ Renderer ready, layout confirmed")
	}

	func getHostUserData() {
		let data = "".data(using: .utf8)!
		CParsec.sendUserData(type: .getVideoConfig, message: data)
		CParsec.sendUserData(type: .getAdapterInfo, message: data)

		let OUT=CParsec.getOutput(maxCount: 10)
		print("Out",OUT.count,OUT)

	}

	func initCParsec(muted: Bool) {

			os_log("初始化客戶端")
			CParsec.setMuted(muted)
			applyDefaultVideoSettings()
			getHostUserData()

			requestResolutionUpdate()
			requestBitrateUpdate()

			clientReady = true

		}


	func attach(viewController vc: ParsecViewController) {
		self.viewController = vc

	}

	func switchRenderer(to type: RendererType) {
		rendererType = type

		viewController?.switchRenderer(to: type)

		print("RenderT:\(type)")

	}


	func DebugMes() -> String? {

		return renderController?.DebugMes
	}


	func Update_DebugMes(_ text:String = "") {
		renderController?.DebugMes = text
	}

	func getViewController() -> UIViewController? {
		return renderController.viewController as? UIViewController
	}

	func getView() -> UIView? {
		return renderController?.view
	}

	func glContext() -> EAGLContext? {
		if let glkVC = renderController as? ParsecGLKViewController {
			return glkVC.glContext
		}
		return nil
	}


	func updateFPS(_ fps: Int) {
		renderController?.preferredFPS = fps
		write_log_from_swift("更新FPS: \(fps)")
	}

	func currentFPS() -> Int {
		return renderController?.preferredFPS ?? 60
	}

	// MARK: - 實際送出 FPS 計算
	private var startTime: CFTimeInterval = CACurrentMediaTime()
	private var lastTime: CFTimeInterval = CACurrentMediaTime()

	private var lastFramesDisplayed: Int = 0

	// MARK: 從開始到現在的平均實際 FPS
	func actualFPS() -> Double {
		guard let controller = renderController else { return 0 }
		let now = CACurrentMediaTime()
		let elapsed = now - startTime
		guard elapsed > 0 else { return 0 }

		let frames = Double(controller.getFramesDisplayed())
		return frames / elapsed
	}

	// MARK: 從上次呼叫到現在的增量 FPS（可每秒更新顯示）
	func deltaFPS() -> Double {
		guard let controller = renderController else { return 0 }
		let now = CACurrentMediaTime()
		let elapsed = now - lastTime
		guard elapsed > 0 else { return 0 }

		let currentFrames = controller.getFramesDisplayed()
		let deltaFrames = Double(currentFrames - lastFramesDisplayed)

		lastFramesDisplayed = currentFrames
		lastTime = now   // ✅ 用 lastTime，不要重設 startTime

		return deltaFrames / elapsed
	}

}
