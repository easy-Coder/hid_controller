import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationWillTerminate(_ notification: Notification) {
    // Release synthetic keys and join the HID thread before process exit.
    let path = Bundle.main.bundlePath + "/Contents/Frameworks/libcontroller_hid.dylib"
    if let library = dlopen(path, RTLD_NOW | RTLD_NOLOAD) {
      if let symbol = dlsym(library, "hc_stop") {
        let stop = unsafeBitCast(symbol, to: (@convention(c) () -> Void).self)
        stop()
      }
      dlclose(library)
    }
    super.applicationWillTerminate(notification)
  }
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
