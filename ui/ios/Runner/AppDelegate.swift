import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Mostra lembretes de aniversário também com a app em primeiro plano.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  /// "Responder" e "Marcar como lida" num push de mensagem (categoria chat_message,
  /// registada em notification_service.dart). O iOS mostra o push sem passar
  /// pela app, por isso a resposta segue daqui para a API com o reply_token,
  /// mesmo com a app fechada. As notificações locais seguem para o plugin.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let action = response.actionIdentifier
    guard action == "chat_reply" || action == "chat_read",
      let token = response.notification.request.content.userInfo["reply_token"] as? String
    else {
      super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
      return
    }
    var body: [String: Any] = ["token": token]
    if action == "chat_reply" {
      let text = (response as? UNTextInputNotificationResponse)?.userText
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if text.isEmpty {
        completionHandler()
        return
      }
      body["id"] = UUID().uuidString.lowercased()
      body["body"] = text
    }
    let base = UserDefaults.standard.string(forKey: "flutter.velas.apiUrl") ?? "https://birthdaymemo.com"
    let path = action == "chat_reply" ? "/push/reply" : "/push/read"
    guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
      completionHandler()
      return
    }
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    // O iOS dá uns segundos à app em segundo plano; o pedido tem de acabar antes.
    var task = UIBackgroundTaskIdentifier.invalid
    task = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(task) }
    URLSession.shared.dataTask(with: request) { _, _, _ in
      // Sem rede a resposta perde-se, como no Android.
      DispatchQueue.main.async {
        completionHandler()
        UIApplication.shared.endBackgroundTask(task)
      }
    }.resume()
  }
}
