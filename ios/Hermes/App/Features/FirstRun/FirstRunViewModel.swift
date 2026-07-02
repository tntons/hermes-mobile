//
//  FirstRunViewModel.swift
//  Hermes
//

import Foundation
import Observation

@Observable
@MainActor
public final class FirstRunViewModel {
    public var gatewayURLString: String = ""
    public var bearerToken: String = ""
    public var profile: String = ""
    public var isTesting: Bool = false
    public var testResult: TestResult?
    public var errorMessage: String?

    public enum TestResult: Equatable, Sendable {
        case success
        case failure(String)
    }

    public init() {
        let kc = KeychainStore.shared
        self.gatewayURLString = kc.gatewayURL?.absoluteString ?? ""
        self.bearerToken = kc.bearerToken ?? ""
        self.profile = kc.profile ?? ""
    }

    public func saveAndContinue(appState: AppState) async {
        guard let url = URL(string: gatewayURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased())
        else {
            errorMessage = "Enter a full URL starting with https:// (e.g. https://hermes.example.com)."
            return
        }
        let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            errorMessage = "Enter your MOBILE_TOKEN."
            return
        }

        let kc = KeychainStore.shared
        kc.gatewayURL = url
        kc.bearerToken = token
        let trimmedProfile = profile.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedProfile.isEmpty {
            kc.profile = nil
        } else {
            kc.profile = trimmedProfile
        }
        appState.reloadAuth()
        HermesLog.auth.info("first-run configured gateway=\(url.absoluteString, privacy: .public)")
    }

    /// Probe `/health` to validate the URL + token before saving.
    public func testConnection() async {
        guard let url = URL(string: gatewayURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        else {
            testResult = .failure("URL and token are required.")
            return
        }
        isTesting = true
        defer { isTesting = false }
        var req = URLRequest(url: url.appendingPathComponent("health"))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 8
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                testResult = .success
                errorMessage = nil
            } else {
                let s = String(data: data, encoding: .utf8) ?? "no body"
                testResult = .failure("HTTP \(((response as? HTTPURLResponse)?.statusCode ?? 0)): \(s)")
            }
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
