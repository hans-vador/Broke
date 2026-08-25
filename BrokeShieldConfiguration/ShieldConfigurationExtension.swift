import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The screen you hit when you try to open something you've blocked.
///
/// Tone: firm but friendly. It should feel like a mate holding your phone
/// above their head, not a compliance banner. The block itself is the strict
/// part, so the words don't need to nag.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private let ink = UIColor(red: 0.07, green: 0.07, blue: 0.06, alpha: 1)
    private let signal = UIColor(red: 0.91, green: 0.25, blue: 0.13, alpha: 1)
    private let canvas = UIColor(red: 0.96, green: 0.94, blue: 0.89, alpha: 1)

    private let headlines = [
        "Nope.",
        "Not right now.",
        "Nice try.",
        "Absolutely not.",
        "Hard pass.",
        "We've been through this.",
        "Denied, with love.",
    ]

    private let asides = [
        "Past you made a call. Present you has to live with it.",
        "This is the part where Broke does its job.",
        "You asked for a bouncer. Here's the bouncer.",
        "Whatever's in there will still be in there later.",
        "Nothing has happened on that app since you last checked.",
        "You already know how that scroll ends.",
        "Go outside. It's rendering in real time.",
    ]

    private let buttons = [
        "FINE",
        "OK, POINT TAKEN",
        "UGH, FINE",
        "YOU'RE RIGHT",
        "BACK TO REAL LIFE",
    ]

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration(itemName: application.localizedDisplayName)
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration(itemName: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration(itemName: webDomain.domain)
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration(itemName: webDomain.domain)
    }

    /// Picks a line from `list` in a way that is stable for a given app but
    /// different between apps, so the wording varies without flickering each
    /// time the same shield is redrawn.
    private func pick(_ list: [String], for name: String?, salt: Int) -> String {
        let seed = abs((name ?? "broke").hashValue &+ salt)
        return list[seed % list.count]
    }

    private func makeConfiguration(itemName: String?) -> ShieldConfiguration {
        let headline = pick(headlines, for: itemName, salt: 0)
        let aside = pick(asides, for: itemName, salt: 17)
        let button = pick(buttons, for: itemName, salt: 41)

        let subject = itemName.map { "\($0) is on your block list.\n" } ?? ""

        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: canvas,
            // Static and intentionally downsampled: shield extensions are
            // memory-limited and cannot host the Lottie runtime.
            icon: UIImage(named: "StrawberryBlocking"),
            title: .init(text: headline, color: ink),
            subtitle: .init(
                text: subject + aside,
                color: ink.withAlphaComponent(0.62)
            ),
            primaryButtonLabel: .init(text: button, color: .white),
            primaryButtonBackgroundColor: signal,
            secondaryButtonLabel: nil
        )
    }
}
