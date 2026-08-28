import UIKit
import AVFoundation

@main
class AppDelegate: UIResponder, UIApplicationDelegate
{
	func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions:[UIApplication.LaunchOptionsKey: Any]?) -> Bool
	{
		// Override point for customization after application launch.
		//UTMViewControllerPatches.patchAll()

		// 統一在啟動時設定音訊 session：`.playback` 允許背景播放（PiP／遠端音訊），
		// `.mixWithOthers` 讓遠端音訊與用戶正在播的其他音訊（音樂、影片）並存，
		// 不會在連線開始播放時打斷它們。
		try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])

		return true
	}

	func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration
	{
		// Called when a new scene session is being created.
		// Use this method to select a configuration to create the new scene with.
		return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
	}

	func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>)
	{
		// Called when the user discards a scene session.
		// If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
		// Use this method to release any resources that were specific to the discarded scenes, as they will not return.
	}

	func applicationWillTerminate(_ application: UIApplication)
	{
		// 系統終止應用程序時的回調，這裡可以進行清理工作
		CParsec.destroy()
	}
}
