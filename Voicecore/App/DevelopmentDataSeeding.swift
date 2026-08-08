// DevelopmentDataSeeding.swift
// Provides Development Data Seeding for app lifecycle and routing.

import Foundation

#if DEBUG
extension AppDelegate {
    func seedDevelopmentStorageData(dictionaryCount: Int, historyCount: Int) {
        guard isDevelopmentBundle else {
            VoicecoreLog.warning("Development data seeding is only available in the dev app bundle.")
            return
        }

        VoicecoreLog.info("Development data seeding started. dictionary=\(dictionaryCount), history=\(historyCount)")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                try DevelopmentDataSeeder.seed(dictionaryCount: dictionaryCount, historyCount: historyCount)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.dictionaryStore.reloadAsync()
                    self.historyStore.reloadAsync()
                    self.openMainWindow(target: SettingsNavigationTarget(tab: .dictionary, section: .dictionaryEntries))
                    VoicecoreLog.info("Development data seeding completed. dictionary=\(dictionaryCount), history=\(historyCount)")
                }
            } catch {
                VoicecoreLog.error("Development data seeding failed: \(error.localizedDescription)")
            }
        }
    }

    private var isDevelopmentBundle: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
    }
}
#endif
