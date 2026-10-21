import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Unified window: the traffic lights float over the app's own canvas,
    // as in Notes or Things, instead of a grey title bar.
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    styleMask.insert(.fullSizeContentView)
    minSize = NSSize(width: 760, height: 560)
    setFrameAutosaveName("JustMainWindow")

    let channel = FlutterMethodChannel(
      name: "day/platform",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "feedbackAllowed":
        // macOS has no global "quiet" API for apps; Focus filters already
        // silence notifications, so interface tones stay on.
        result(true)
      case "hasPackageIdentity":
        result(true)
      case "dragWindow":
        // The top strip is Flutter content, so it asks the window to move.
        if let event = NSApp.currentEvent { self?.performDrag(with: event) }
        result(nil)
      case "zoomWindow":
        self?.zoom(nil)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
