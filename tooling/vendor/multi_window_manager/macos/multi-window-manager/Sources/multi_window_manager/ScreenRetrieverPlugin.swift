import Cocoa
import FlutterMacOS

private extension NSScreen {
  var mwmDisplayID: CGDirectDisplayID {
    deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as? CGDirectDisplayID ?? 0
  }

  func toMwmDictionary() -> NSDictionary {
    var name = ""
    if #available(macOS 10.15, *) {
      name = localizedName
    }
    let size: NSDictionary = [
      "width": frame.width,
      "height": frame.height,
    ]
    let visiblePosition: NSDictionary = [
      "dx": visibleFrame.topLeft.x,
      "dy": visibleFrame.topLeft.y,
    ]
    let visibleSize: NSDictionary = [
      "width": visibleFrame.width,
      "height": visibleFrame.height,
    ]
    return [
      "id": mwmDisplayID.description,
      "name": name,
      "size": size,
      "visiblePosition": visiblePosition,
      "visibleSize": visibleSize,
    ]
  }
}

class MwmScreenRetrieverPlugin: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var externalDisplayCount = 0

  static func register(with messenger: FlutterBinaryMessenger) {
    let instance = MwmScreenRetrieverPlugin()

    let methodChannel = FlutterMethodChannel(
      name: "multi_window_manager/screen_retriever",
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler(instance.handle)

    let eventChannel = FlutterEventChannel(
      name: "multi_window_manager/screen_retriever_event",
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(instance)

    instance.externalDisplayCount = NSScreen.screens.count
    instance.setupNotificationCenter()
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func setupNotificationCenter() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleDisplayChange),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
  }

  @objc private func handleDisplayChange(notification: Notification) {
    let current = NSScreen.screens.count
    if externalDisplayCount < current {
      emitEvent("display-added")
    } else if externalDisplayCount > current {
      emitEvent("display-removed")
    }
    externalDisplayCount = current
  }

  private func emitEvent(_ eventName: String) {
    guard let sink = eventSink else { return }
    sink(["type": eventName] as NSDictionary)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getCursorScreenPoint":
      getCursorScreenPoint(result: result)
    case "getPrimaryDisplay":
      guard let screen = NSScreen.screens.first else {
        result(FlutterError(code: "NO_SCREEN", message: "No primary display found", details: nil))
        return
      }
      result(screen.toMwmDictionary())
    case "getAllDisplays":
      result(["displays": NSScreen.screens.map { $0.toMwmDictionary() }] as NSDictionary)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func getCursorScreenPoint(result: @escaping FlutterResult) {
    guard let currentScreen = NSScreen.main else {
      result(FlutterError(code: "NO_SCREEN", message: "No main screen found", details: nil))
      return
    }
    let mouseLocation = NSEvent.mouseLocation
    var visibleHeight = currentScreen.frame.maxY
    for screen in NSScreen.screens where visibleHeight > screen.frame.maxY {
      visibleHeight = screen.frame.maxY
    }
    result(["dx": mouseLocation.x, "dy": visibleHeight - mouseLocation.y] as NSDictionary)
  }
}
