import SwiftUI
import WebKit

/// 网易易盾 H5 验证码（复刻官方客户端做法）
///
/// 官方 Android 客户端就是加载 `cstaticdun.126.net/load.min.js`，
/// 用 `initNECaptcha({captchaId})` 出验证码，成功后把 `data.validate` 回传原生，
/// 原生再调 `uais/1.1/graphicVerificationV2` 触发短信下发。
struct CaptchaView: UIViewRepresentable {
    static let captchaId = "b4800c43901c4113856a95938560ae0a"

    var onValidate: (String) -> Void
    var onError: ((String) -> Void)?
    var onLog: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onValidate: onValidate, onError: onError, onLog: onLog)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "captcha")
        config.userContentController.add(context.coordinator, name: "captchaError")
        config.userContentController.add(context.coordinator, name: "captchaLog")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        // baseURL 用 nil：页面 origin 是 about:blank，避免 mp.ebanma.com 的
        // CORS / Referer 限制阻断易盾向 dun.126.net 的行为上报。
        webView.loadHTMLString(Self.html, baseURL: nil)
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "captcha")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "captchaError")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "captchaLog")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onValidate: (String) -> Void
        let onError: ((String) -> Void)?
        let onLog: ((String) -> Void)?
        weak var webView: WKWebView?
        private var delivered = false

        init(onValidate: @escaping (String) -> Void,
             onError: ((String) -> Void)?,
             onLog: ((String) -> Void)?) {
            self.onValidate = onValidate
            self.onError = onError
            self.onLog = onLog
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case "captcha":
                if let validate = message.body as? String, !validate.isEmpty, !delivered {
                    delivered = true
                    onValidate(validate)
                }
            case "captchaError":
                onError?(String(describing: message.body))
            case "captchaLog":
                if let text = message.body as? String {
                    print("CAPTCHA: \(text)")
                    onLog?(text)
                }
            default:
                break
            }
        }
    }

    static let html = """
    <!DOCTYPE html>
    <html lang="zh-CN">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
      <style>
        body, html { width: 100%; height: 100%; margin: 0; padding: 0; display: flex;
                     justify-content: center; align-items: center; background: #ffffff; }
        #captcha { width: 300px; }
      </style>
      <script>
        window.onerror = function (msg, url, line) {
          try { window.webkit.messageHandlers.captchaError.postMessage('js:' + msg + '@' + line); } catch (e) {}
        };
        function post(name, value) {
          try { window.webkit.messageHandlers[name].postMessage(value); } catch (e) {}
        }
        window.__startCaptcha = function () {
          post('captchaLog', 'script-loaded');
          if (typeof initNECaptcha !== 'function') { post('captchaError', 'initNECaptcha-missing'); return; }
          setTimeout(function () { if (!window.__ready) { post('captchaLog', 'timeout-5s'); } }, 5000);
          initNECaptcha({
            captchaId: '\(captchaId)',
            element: '#captcha',
            mode: 'float',
            width: '300px',
            onVerify: function (err, data) {
              if (err) { post('captchaError', JSON.stringify(err)); return; }
              var v = '';
              try {
                if (data && data.validate) { v = data.validate; }
                else if (typeof data === 'string') { v = data; }
              } catch (e) {}
              if (v) { post('captcha', v); }
              else { post('captchaError', 'empty-validate'); }
            }
          }, function (instance) {
            window.__ready = true;
            post('captchaLog', 'instance-ready');
          }, function (err) {
            post('captchaError', 'init:' + String(err));
          });
        };
      </script>
      <script src="https://cstaticdun.126.net/load.min.js" onload="window.__startCaptcha()" onerror="post('captchaError','script-load-failed')"></script>
    </head>
    <body>
      <div id="captcha"></div>
    </body>
    </html>
    """
}

/// 验证码弹窗
struct CaptchaSheet: View {
    let phone: String
    var onValidate: (String) -> Void
    var onCancel: () -> Void

    @State private var errorText: String?
    @State private var logText = ""
    @State private var reloadToken = UUID()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                VStack(spacing: 12) {
                    Text("请完成安全验证")
                        .font(.headline)
                        .foregroundStyle(.black)
                    Text("验证通过后将向 \(phone) 发送短信验证码")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    CaptchaView(onValidate: { validate in
                        onValidate(validate)
                    }, onError: { message in
                        errorText = message
                    }, onLog: { text in
                        logText = text
                    })
                    .id(reloadToken)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let message = errorText {
                        VStack(spacing: 6) {
                            Text("验证未通过：\(message)")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                            Button("重新加载验证码") {
                                errorText = nil
                                reloadToken = UUID()
                            }
                            .font(.footnote.weight(.semibold))
                        }
                        .padding(.bottom, 8)
                    }

                    if !logText.isEmpty {
                        Text(logText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(16)
            }
            .navigationTitle("安全验证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
            }
        }
    }
}
