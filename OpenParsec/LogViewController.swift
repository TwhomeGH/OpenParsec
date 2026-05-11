import UIKit

class LogViewController: UIViewController {
    private let textView = UITextView()
    private var timer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Logs"
        view.backgroundColor = .systemBackground
        textView.isEditable = false
        textView.frame = view.bounds
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(textView)

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Clear", style: .plain, target: self, action: #selector(clearLogs))

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { [weak self] _ in
            self?.refresh()
        })
    }

    @objc func clearLogs() {
        Logger.shared.clear()
        refresh()
    }

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async {
            let s = Logger.shared.read()
            DispatchQueue.main.async {
                self.textView.text = s
                if s.count > 0 {
                    let bottom = NSRange(location: max(0, s.count - 1), length: 1)
                    self.textView.scrollRangeToVisible(bottom)
                }
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}
