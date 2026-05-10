import ParsecSDK
import UIKit


class TouchController
{
	let viewController: UIViewController

	init(viewController: UIViewController) {
		self.viewController = viewController
	}

	private func currentMousePosition() -> (x: Int32, y: Int32) {
		let mouseInfo = CParsec.mouseInfo
		return (mouseInfo.mouseX, mouseInfo.mouseY)
	}
	
	func onTouch(typeOfTap:Int, location:CGPoint, state: UIGestureRecognizer.State) {

		let x = Int32(location.x)
		let y = Int32(location.y)

		// Send the mouse input to the host
		let parsecTap = ParsecMouseButton(rawValue: UInt32(typeOfTap))
		switch state
		{
			case .began:
				CParsec.sendMouseMessage(parsecTap, x, y, true)
			case .changed:
				CParsec.sendMousePosition(x, y)
			case .ended, .cancelled:
				CParsec.sendMouseMessage(parsecTap, x, y, false)
			default:
				break
		}
	}

	func onTap(typeOfTap:Int, location:CGPoint) {

		let parsecTap = ParsecMouseButton(rawValue: UInt32(typeOfTap))

		if SettingsHandler.shared.cursorMode == .direct {
			let x = Int32(location.x)
			let y = Int32(location.y)

			// Send the mouse input to the host
			// add release delay in case some games ignore instant key release
			CParsec.sendMouseMessage(parsecTap, x, y, true)
			DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) {
				CParsec.sendMouseMessage(parsecTap, x, y, false)
			}

		} else {
			let position = currentMousePosition()
			CParsec.sendMouseMessage(parsecTap, position.x, position.y, true)
			DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) {
				CParsec.sendMouseMessage(parsecTap, position.x, position.y, false)
			}
		}
	}

	public func viewDidLoad() { }

}
