import SwiftUI
import UIKit

struct LogViewControllerWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = LogViewController()
        let nav = UINavigationController(rootViewController: vc)
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // no-op
    }
}
