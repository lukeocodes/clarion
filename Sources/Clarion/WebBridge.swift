import AppKit
import WebKit

final class WebBridge: NSObject, WKScriptMessageHandler {
    let webView: WKWebView
    var onAction: ((String, [String: Any]) -> Void)?

    init(htmlFileName: String) {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        config.userContentController = controller
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        self.webView = webView

        super.init()

        controller.add(self, name: "clarion")
        loadHTML(named: htmlFileName)
    }

    private func loadHTML(named name: String) {
        guard let htmlURL = Bundle.main.url(forResource: name, withExtension: "html"),
              var html = try? String(contentsOf: htmlURL, encoding: .utf8)
        else {
            print("[WebBridge] HTML file not found: \(name).html")
            return
        }

        // Inline the CSS so we can load with a real base URL (for 1Password autofill)
        if let cssURL = Bundle.main.url(forResource: "styles", withExtension: "css"),
           let css = try? String(contentsOf: cssURL, encoding: .utf8) {
            html = html.replacingOccurrences(
                of: "<link rel=\"stylesheet\" href=\"styles.css\">",
                with: "<style>\(css)</style>"
            )
        }

        // Use console.deepgram.com as base URL so 1Password offers Deepgram credentials
        let baseURL = URL(string: "https://console.deepgram.com")
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func evaluateJS(_ script: String) {
        webView.evaluateJavaScript(script) { _, error in
            if let error {
                print("[WebBridge] JS error: \(error)")
            }
        }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String
        else { return }

        onAction?(action, body)
    }
}
