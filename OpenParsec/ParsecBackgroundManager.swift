import UIKit
import AVFoundation

class ParsecBackgroundManager {
    static let shared = ParsecBackgroundManager()

    private(set) var hasActiveConnection = false
    private var lastPeerId: String?
    private var didDisconnectDueToBackground = false
    private(set) var isReconnecting = false

    var onShouldReconnect: ((String) -> Void)?
    var onShouldDisconnect: (() -> Void)?

    var isMarkedForReconnect: Bool {
        return didDisconnectDueToBackground || isReconnecting
    }

    var isPiPActive: Bool {
        if #available(iOS 15.0, *) {
            return PictureInPictureManager.shared.isPiPActive
        }
        return false
    }

    private init() {}

    func connectionDidStart(peerId: String) {
        hasActiveConnection = true
        lastPeerId = peerId
        didDisconnectDueToBackground = false
        isReconnecting = false
    }

    func connectionDidEnd() {
        hasActiveConnection = false
        lastPeerId = nil
        isReconnecting = false
        didDisconnectDueToBackground = false
    }

    func sceneWillResignActive() {
        // 保留空間，必要時可加上暫停邏輯
    }

    func sceneDidBecomeActive() {
        guard didDisconnectDueToBackground, let peerId = lastPeerId else { return }

        // 如果 PiP 還在 active 或正在停止，延遲再檢查一次
        if #available(iOS 15.0, *), PictureInPictureManager.shared.isPiPActive || PictureInPictureManager.shared.isStarting {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.sceneDidBecomeActive()
            }
            return
        }

        didDisconnectDueToBackground = false
        isReconnecting = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, let peerId = self.lastPeerId else { return }
            self.onShouldReconnect?(peerId)
        }
    }

    func sceneDidEnterBackground() {
        guard hasActiveConnection else { return }

        var pipAttempted = false
        if #available(iOS 15.0, *) {
            pipAttempted = PictureInPictureManager.shared.isPiPActive || PictureInPictureManager.shared.isStarting
        }

        // 如果沒有 PiP，才標記需要斷線
        if !pipAttempted {
            didDisconnectDueToBackground = true
            onShouldDisconnect?()
        }
    }

    func markForReconnect() {
        guard lastPeerId != nil else { return }
        didDisconnectDueToBackground = true
    }

    func disableAutoReconnect() {
        didDisconnectDueToBackground = false
        isReconnecting = false
        lastPeerId = nil
    }
}
