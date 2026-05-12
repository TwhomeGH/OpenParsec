import AVKit
import AVFoundation
import CoreVideo
import OpenGLES
import GLKit
import CoreMedia

private let kGL_BGRA: GLenum = 0x80E1

protocol CaptureSurfaceProvider {
    func setup(width: Int, height: Int)
    func destroy()
    func getPixelBuffer() -> CVPixelBuffer?
}

// MARK: - Picture in Picture Manager for OpenGL
final class GLCaptureSurfaceProvider: CaptureSurfaceProvider {
    private var textureCache: CVOpenGLESTextureCache?
    private var pixelBuffer: CVPixelBuffer?
    private var cvTexture: CVOpenGLESTexture?
    private var captureFBO: GLuint = 0
    private var glContext: EAGLContext

    init(glContext: EAGLContext) {
        self.glContext = glContext
        CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, glContext, nil, &textureCache)
    }

    func setup(width: Int, height: Int) {
        destroy()

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
    }

    func destroy() {
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
}

// MARK: - Picture in Picture Manager for Metal
final class MetalCaptureSurfaceProvider: CaptureSurfaceProvider {
    private var textureCache: CVMetalTextureCache?
    private var pixelBuffer: CVPixelBuffer?
    private var cvTexture: CVMetalTexture?
    private var device: MTLDevice

    init(device: MTLDevice) {
        self.device = device
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
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

        var cvTex: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache!,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTex
        )
        guard let cvTexture = cvTex else { return }
        self.cvTexture = cvTexture
    }

    func destroy() {
        cvTexture = nil
        pixelBuffer = nil
    }

    func getPixelBuffer() -> CVPixelBuffer? {
        return pixelBuffer
    }

    func getMTLTexture() -> MTLTexture? {
        return cvTexture != nil ? CVMetalTextureGetTexture(cvTexture!) : nil
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

    private(set) var isPiPActive = false
    private var isSetup = false
    private(set) var isStarting = false

    var onPiPStopped: (() -> Void)?
    var onPiPStartFailed: (() -> Void)?
    var onRestoreUserInterface: (() -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Setup
    func setup(sourceView: UIView, provider: CaptureSurfaceProvider) {
        guard !isSetup else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }

        self.captureProvider = provider

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspect

        let containerView = UIView(frame: sourceView.bounds)
        containerView.isUserInteractionEnabled = false
        containerView.alpha = 0
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

    // MARK: - Feed SampleBuffer
    func feedSampleBuffer() {
        guard let provider = captureProvider,
              let pixelBuffer = provider.getPixelBuffer(),
              let displayLayer = sampleBufferDisplayLayer,
              displayLayer.isReadyForMoreMediaData else { return }

        if cachedFormatDescription == nil {
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &cachedFormatDescription
            )
        }
        guard let format = cachedFormatDescription else { return }

        let now = CMClockGetTime(CMClockGetHostTimeClock())
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: now,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        guard let buffer = sampleBuffer else { return }
        displayLayer.enqueue(buffer)
    }

    // MARK: - PiP Control
    func startPiP() {
        guard isSetup, let controller = pipController, !isPiPActive, !isStarting else { return }
        isStarting = true
        controller.startPictureInPicture()
    }

    func stopPiP() {
        isStarting = false
        guard isPiPActive else { return }
        pipController?.stopPictureInPicture()
    }

    // MARK: - Cleanup
    func teardown() {
        stopPiP()
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
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}






// MARK: - AVPictureInPictureControllerDelegate
@available(iOS 15.0, *)
extension PictureInPictureManager: AVPictureInPictureControllerDelegate {

	func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
		isPiPActive = true
		isStarting = false
		// Keep GL render loop alive during PiP so frames keep updating

		if let vc = ParsecRenderCenter.shared.viewController,let renderer = vc.renderer,let renderView = renderer.renderView {
			renderView.isPaused = false
		}


	}

	func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
	}

	func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
	}

	func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
		isPiPActive = false
		onPiPStopped?()
	}

	func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
									restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
		onRestoreUserInterface?()
		completionHandler(true)
	}

	func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
									failedToStartPictureInPictureWithError error: Error) {
		isPiPActive = false
		isStarting = false
		onPiPStartFailed?()
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