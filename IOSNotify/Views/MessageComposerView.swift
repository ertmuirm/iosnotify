import SwiftUI
import MessageUI

struct MessageComposerView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let parent: MessageComposerView
        init(_ parent: MessageComposerView) { self.parent = parent }

        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            let sent = result == .sent
            Task { @MainActor in
                DiagnosticLog.shared.log("Message compose finished: \(result.rawValue) sent=\(sent)", tag: "TRIGGER")
            }
            parent.onFinish(sent)
            controller.dismiss(animated: true)
        }
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = recipients
        vc.body = body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController,
                                context: Context) {}
}
