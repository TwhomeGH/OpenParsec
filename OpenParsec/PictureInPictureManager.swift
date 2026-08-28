import AVKit
import AVFoundation
import CoreVideo
import OpenGLES
import GLKit
import MetalKit
import CoreMedia
import IOSurface
import UIKit
import ParsecSDK



private let kGL_BGRA: GLenum = 0x80E1

protocol CaptureSurfaceProvider {
    func setup(width: Int, height: Int)
    func destroy()
    func getPixelBuffer() -> CVPixelBuffer?
    var captureSize: CGSize { get }
}

// MARK: - Picture in Picture Manager for OpenGL
final class GLCaptureSurfaceProvider: CaptureSurfaceProvider {
    private var textureCache: CVOpenGLESTextureCache?
    private var pixelBuffer: CVPixelBuffer?
    private var cvTexture: CVOpenGLESTexture?
    private var captureFBO: GLuint = 0
    private var glContext: EAGLContext
    private var prevFramebuffer: GLint = 0
    private var prevViewport: [GLint] = [0, 0, 0, 0]
    private(set) var captureWidth = 0
    private(set) var captureHeight = 0

    init(glContext: EAGLContext) {
        self.glContext = glContext
        CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, glContext, nil, &textureCache)
    }

    func setup(width: Int, height: Int) {
        destroy()

        // texture/FBO 必須建立在正確的 GL context 上
        EAGLContext.setCurrent(glContext)

        var savedFBO: GLint = 0
        glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &savedFBO)

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferOpenGLESCompatibilityKey as String: true
        ]

        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_32BGRA,
                            attrs as CFDictionary, &pb)
        guard let pixelBuffer = pb else { return }
        self.pixelBuffer = pixelBuffer

        var texture: CVOpenGLESTexture?
        CVOpenGLESTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache!,
            pixelBuffer,
            nil,
            GLenum(GL_TEXTURE_2D),
            GL_RGBA,
            GLsizei(width), GLsizei(height),
            kGL_BGRA,
            GLenum(GL_UNSIGNED_BYTE),
            0,
            &texture
        )
        guard let cvTex = texture else { return }
        self.cvTexture = cvTex

        let textureName = CVOpenGLESTextureGetName(cvTex)
        glGenFramebuffers(1, &captureFBO)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), captureFBO)
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER),
                               GLenum(GL_COLOR_ATTACHMENT0),
                               GLenum(GL_TEXTURE_2D),
                               textureName, 0)

        // 還原原本綁定的 FBO，避免 resize 發生在 draw 中途時污染 render loop
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLuint(savedFBO))

        captureWidth = width
        captureHeight = height
    }

    func destroy() {
        EAGLContext.setCurrent(glContext)
        if captureFBO != 0 {
            glDeleteFramebuffers(1, &captureFBO)
            captureFBO = 0
        }
        cvTexture = nil
        pixelBuffer = nil
    }

    func getPixelBuffer() -> CVPixelBuffer? {
        return pixelBuffer
    }

    var captureSize: CGSize {
        return CGSize(width: captureWidth, height: captureHeight)
    }

    /// Binds the capture FBO (must be called on the GL render context).
    /// Returns capture size, or nil when the capture surface is unavailable.
    func beginCaptureFrame() -> CGSize? {
        guard captureFBO != 0, let pb = pixelBuffer else { return nil }
        glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &prevFramebuffer)
        glGetIntegerv(GLenum(GL_VIEWPORT), &prevViewport)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), captureFBO)
        let w = GLsizei(CVPixelBufferGetWidth(pb))
        let h = GLsizei(CVPixelBufferGetHeight(pb))
        glViewport(0, 0, w, h)
        return CGSize(width: Int(w), height: Int(h))
    }

    func endCaptureFrame() {
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), GLuint(prevFramebuffer))
        glViewport(prevViewport[0], prevViewport[1], prevViewport[2], prevViewport[3])
    }
}

// MARK: - Picture in Picture Manager for Metal
final class MetalCaptureSurfaceProvider: CaptureSurfaceProvider {
    private var pixelBuffer: CVPixelBuffer?
    private var mtlTexture: MTLTexture?
    private var device: MTLDevice
    private(set) var captureWidth = 0
    private(set) var captureHeight = 0

    init(device: MTLDevice) {
        self.device = device
    }

    func setup(width: Int, height: Int) {
        destroy()

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_32BGRA,
                            attrs as CFDictionary, &pb)
        guard let pixelBuffer = pb else { return }
        self.pixelBuffer = pixelBuffer

        // The texture-cache variant is shader-read only and cannot be used as a render
        // target — create an explicit IOSurface-backed texture we are allowed to draw into.
        guard let ioSurface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .renderTarget]
        desc.storageMode = .shared
        self.mtlTexture = device.makeTexture(descriptor: desc, iosurface: ioSurface, plane: 0)

        captureWidth = width
        captureHeight = height
    }

    func destroy() {
        mtlTexture = nil
        pixelBuffer = nil
    }

    func getPixelBuffer() -> CVPixelBuffer? {
        return pixelBuffer
    }

    var captureSize: CGSize {
        return CGSize(width: captureWidth, height: captureHeight)
    }

    func getMTLTexture() -> MTLTexture? {
        return mtlTexture
    }
}



@available(iOS 15.0, *)
class PictureInPictureManager: NSObject {
    static let shared = PictureInPictureManager()

    private var pipController: AVPictureInPictureController?
    private var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer?
    private var pipSourceView: UIView?

    private var captureProvider: CaptureSurfaceProvider?
    private var cachedFormatDescription: CMVideoFormatDescription?

    private var frameTimer: DispatchSourceTimer?
    private var currentPTS: CMTime = .zero
    private var lastFormattedBuffer: CVPixelBuffer?

    /// 由 renderer 註冊：把最新一幀畫進擷取面。
    /// 前景時 display link 會負責填內容；App 背景化後 display link 停止，
    /// frame pump 必須改用這個 closure 自行拉幀＋繪製，PiP 才不會凍結。
    var captureSourceRenderer: (() -> Void)?

    private(set) var isPiPActive = false
    private(set) var isStarting = false
    private var isSetup = false

    var onPiPStopped: (() -> Void)?
    var onPiPStartFailed: (() -> Void)?
    var onRestoreUserInterface: (() -> Void)?

    private override init() { super.init() }

    /// 目前擷取面的尺寸（pixel buffer 尺寸，決定 PiP 小窗比例）
    var captureSize: CGSize? {
        return captureProvider?.captureSize
    }

    /// 依實際視訊尺寸調整擷取面。
    /// PiP 小窗比例由 buffer 決定，必須對齊影片比例（如 16:9），
    /// 而非裝置螢幕比例（iPad 常為 4:3）——否則小窗會是 4:3 加上 letterbox。
    func updateVideoSize(width: Int, height: Int) {
        guard isPiPActive || isStarting else { return }
        guard width > 0, height > 0 else { return }
        guard let provider = captureProvider else { return }

        let current = provider.captureSize
        guard Int(current.width) != width || Int(current.height) != height else { return }

        provider.setup(width: width, height: height)
        write_log_from_swift("PiP 擷取面調整為 \(width)x\(height)")
    }

    /// 啟動 PiP 前先以目前視訊尺寸重建擷取面，讓小窗第一次出現就是正確比例
    private func refreshCaptureSizeFromVideoStatus() {
        var pcs = ParsecClientStatus()
        guard CParsec.getStatusEx(&pcs) == PARSEC_OK else { return }
        updateVideoSize(width: Int(pcs.decoder.0.width), height: Int(pcs.decoder.0.height))
    }

    // MARK: - Setup
    func setup(sourceView: UIView, provider: CaptureSurfaceProvider) {
        guard !isSetup else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

        self.captureProvider = provider

        // mixWithOthers：啟用 PiP 時不要打斷用戶正在播的其他音訊（音樂、影片等）
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspect

        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        containerView.isUserInteractionEnabled = false

        containerView.layer.addSublayer(layer)
        layer.frame = containerView.bounds
        sourceView.addSubview(containerView)

        self.sampleBufferDisplayLayer = layer
        self.pipSourceView = containerView

        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: layer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        self.pipController = controller

        isSetup = true

    }

    // MARK: - PiP Control

    private func startFramePump() {
        stopFramePump()

        currentPTS = .zero

        // GCD timer instead of CADisplayLink: display links never fire once the app is
        // backgrounded, which would freeze the PiP window on the last frame.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0 / 30.0)
        timer.setEventHandler { [weak self] in
            self?.renderFrame()
        }
        timer.resume()
        frameTimer = timer
    }

    private func stopFramePump() {
        frameTimer?.cancel()
        frameTimer = nil
    }


    // MARK: PIP 繪製
    private func renderFrame() {
        // 前景時 display link 已把畫面畫進擷取面；背景時 display link 停止，
        // 由 pump 自己拉最新幀並繪製，否則 PiP 小窗會凍結在最後一幀。
        if UIApplication.shared.applicationState != .active {
            captureSourceRenderer?()
        }

        guard let pixelBuffer = captureProvider?.getPixelBuffer(),
            let layer = sampleBufferDisplayLayer else {
            return
        }

        // 建立 format description；buffer 被重建（尺寸變更）時一併重建
        if cachedFormatDescription == nil || lastFormattedBuffer !== pixelBuffer {
            cachedFormatDescription = nil
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &cachedFormatDescription
            )
            lastFormattedBuffer = pixelBuffer
        }

        guard let format = cachedFormatDescription else {
            return
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: currentPTS,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?

        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr,
            let sb = sampleBuffer else {
            return
        }

        if layer.status == .failed {
            layer.flush()
        }

        layer.enqueue(sb)

        currentPTS = CMTimeAdd(
            currentPTS,
            CMTime(value: 1, timescale: 30)
        )
    }



    func startPiP() {
        guard isSetup, let controller = pipController,
              !isPiPActive, !isStarting else { return }

        guard controller.isPictureInPicturePossible else {
            write_log_from_swift("PiP not possible right now")
            return
        }

        isStarting = true
        refreshCaptureSizeFromVideoStatus()
        startFramePump()
        controller.startPictureInPicture()
    }

    func stopPiP() {
        guard isSetup, let controller = pipController,
              isPiPActive else { return }
        isStarting = false
        controller.stopPictureInPicture()
    }

    /// Binds the GL capture FBO on the current (render) context; pair with endOpenGLCaptureFrame().
    @discardableResult
    func beginOpenGLCaptureFrame() -> Bool {
        guard let provider = captureProvider as? GLCaptureSurfaceProvider else { return false }
        return provider.beginCaptureFrame() != nil
    }

    func endOpenGLCaptureFrame() {
        (captureProvider as? GLCaptureSurfaceProvider)?.endCaptureFrame()
    }

    func metalCaptureTexture() -> MTLTexture? {
        guard let provider = captureProvider as? MetalCaptureSurfaceProvider else { return nil }
        return provider.getMTLTexture()
    }

    // MARK: - Cleanup
    func teardown() {
        if isPiPActive {
            stopPiP()
        }

        stopFramePump()

        captureProvider?.destroy()
        captureProvider = nil
        pipController = nil
        sampleBufferDisplayLayer?.removeFromSuperlayer()
        sampleBufferDisplayLayer = nil
        pipSourceView?.removeFromSuperview()
        pipSourceView = nil
        isSetup = false
        isPiPActive = false
        isStarting = false
        cachedFormatDescription = nil
        onPiPStopped = nil
        onPiPStartFailed = nil
        onRestoreUserInterface = nil
        captureSourceRenderer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Delegate
@available(iOS 15.0, *)
extension PictureInPictureManager: AVPictureInPictureControllerDelegate {

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        isPiPActive = true
        isStarting = false

        write_log_from_swift("PiP 正在開始 (Delegate 回調)")
    }


    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {

        write_log_from_swift("PiP將開始 (Delegate 回調)")
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        isPiPActive = false
        stopFramePump()
        onPiPStopped?()

        write_log_from_swift("PiP did stop")
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        onRestoreUserInterface?()
        completionHandler(true)

        write_log_from_swift("Restoring UI for PiP stop")
    }

    func pictureInPictureController(_ controller: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        isPiPActive = false
        isStarting = false
        stopFramePump()
        onPiPStartFailed?()

        write_log_from_swift("PiP failed to start: \(error.localizedDescription)")
    }
}





// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate
@available(iOS 15.0, *)
extension PictureInPictureManager: AVPictureInPictureSampleBufferPlaybackDelegate {

	func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
		// Live content — nothing to do
	}

	func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
		return CMTimeRange(start: .zero, duration: .positiveInfinity)
	}

	func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
		return false
	}

	func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
									didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
	}

	func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
									skipByInterval skipInterval: CMTime,
									completion completionHandler: @escaping () -> Void) {
		// Live content — no seeking
		completionHandler()
	}
}