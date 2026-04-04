//
//  ShareViewController.swift
//  BiteRecipeShare
//
//  Receives a URL from the iOS share sheet (e.g. Safari) and hands it off to
//  the main BiteRecipe app via the shared App Group UserDefaults, then opens
//  the main app via a custom URL scheme.
//

import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        extractURL { [weak self] url in
            guard let self else { return }
            if let url {
                self.handOff(url: url)
            }
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    // MARK: - Extract URL from extension items

    private func extractURL(completion: @escaping (URL?) -> Void) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments else {
            completion(nil)
            return
        }

        let urlType  = UTType.url.identifier
        let textType = UTType.plainText.identifier

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(urlType) }) {
            provider.loadItem(forTypeIdentifier: urlType) { item, _ in
                DispatchQueue.main.async {
                    completion(item as? URL)
                }
            }
        } else if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(textType) }) {
            provider.loadItem(forTypeIdentifier: textType) { item, _ in
                DispatchQueue.main.async {
                    if let str = item as? String, let url = URL(string: str) {
                        completion(url)
                    } else {
                        completion(nil)
                    }
                }
            }
        } else {
            completion(nil)
        }
    }

    // MARK: - Hand off to main app

    private func handOff(url: URL) {
        // Write the pending URL to the shared App Group so the main app can read it
        let defaults = UserDefaults(suiteName: "group.com.ridepro.biteledger")
        defaults?.set(url.absoluteString, forKey: "pendingRecipeURL")
        defaults?.synchronize()

        // Open the main app via custom URL scheme.
        // Walk the responder chain — in a Share Extension the UIApplication instance
        // exists in the chain even though UIApplication.shared is unavailable.
        guard let appURL = URL(string: "biterecipe://import") else { return }
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(appURL)
                return
            }
            responder = r.next
        }
    }
}
