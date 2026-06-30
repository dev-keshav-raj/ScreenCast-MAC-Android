import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Set up MethodChannel before super.awakeFromNib is executed if macOS 12.3+ is available
    if #available(macOS 12.3, *) {
      let channel = FlutterMethodChannel(name: "com.example.screenmirror/channel",
                                         binaryMessenger: flutterViewController.engine.binaryMessenger)
      UsbStreamer.shared.methodChannel = channel
      
      channel.setMethodCallHandler { (call, result) in
        switch call.method {
        case "getDisplays":
          result(UsbStreamer.shared.getDisplays())
        case "getDevices":
          result(UsbStreamer.shared.getDevices())
        case "runAdbCommand":
          if let args = call.arguments as? [String: Any],
             let action = args["action"] as? String {
            result(UsbStreamer.shared.runAdbCommand(action: action))
          } else {
            result(false)
          }
        case "startMirroring":
          if let args = call.arguments as? [String: Any],
             let res = args["resolution"] as? String,
             let fps = args["fps"] as? Int,
             let bitrate = args["bitrate"] as? Int,
             let mode = args["connectionMode"] as? String,
             let displayId = args["displayId"] as? String {
            
            let customWidth = args["customWidth"] as? Int ?? 1920
            let customHeight = args["customHeight"] as? Int ?? 1080
            let extendDisplay = args["extendDisplay"] as? Bool ?? false
            
            UsbStreamer.shared.startMirroring(
              resolution: res,
              fps: fps,
              bitrate: bitrate,
              connectionMode: mode,
              displayId: displayId,
              customWidth: customWidth,
              customHeight: customHeight,
              extendDisplay: extendDisplay
            ) { success in
              result(success)
            }
          } else {
            result(false)
          }
        case "stopMirroring":
          UsbStreamer.shared.stopMirroring()
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    } else {
      // Fallback or warning if on an older macOS version
      print("ScreenMirror requires macOS 12.3 or higher for ScreenCaptureKit.")
    }

    super.awakeFromNib()
  }
}
