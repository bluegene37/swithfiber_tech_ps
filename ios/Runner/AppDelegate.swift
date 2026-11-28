import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    /*
    // Gene - Nov, 28, 2026: Re-register BGTaskScheduler launch handlers during didFinishLaunching for UIScene lifecycle compatibility.
    WorkmanagerPlugin.registerLaunchHandlers()
    */
    // Gene - Nov, 28, 2026: Pre-register the periodic BGAppRefreshTask identifier and background plugin registrant during didFinishLaunching so workmanager_apple never calls BGTaskScheduler.register after app launch (which throws NSInternalInconsistencyException on real iOS devices / TestFlight).
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "dev.genexis.swithfibertech.backgroundSync",
      earliestBeginInSeconds: NSNumber(value: 15 * 60)
    )
    WorkmanagerPlugin.registerLaunchHandlers()
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
