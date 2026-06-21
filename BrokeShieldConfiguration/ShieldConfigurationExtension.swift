import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private let ink = UIColor(red: 0.07, green: 0.07, blue: 0.06, alpha: 1)
    private let signal = UIColor(red: 0.91, green: 0.25, blue: 0.13, alpha: 1)
    private let canvas = UIColor(red: 0.96, green: 0.94, blue: 0.89, alpha: 1)

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

    private func makeConfiguration(itemName: String?) -> ShieldConfiguration {
        let subject = itemName.map { "\($0) can wait." } ?? "This distraction can wait."

        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: canvas,
            icon: makeBrokeGraphic(),
            title: .init(text: "SCROLL BLOCKED", color: ink),
            subtitle: .init(
                text: "\(subject)\nMove away from your Broke pod or scan your NFC tag to unlock.",
                color: ink.withAlphaComponent(0.62)
            ),
            primaryButtonLabel: .init(text: "BACK TO REAL LIFE", color: .white),
            primaryButtonBackgroundColor: signal,
            secondaryButtonLabel: nil
        )
    }

    private func makeBrokeGraphic() -> UIImage {
        let size = CGSize(width: 180, height: 180)
        return UIGraphicsImageRenderer(size: size).image { context in
            let bounds = CGRect(origin: .zero, size: size)
            signal.setFill()
            context.cgContext.fillEllipse(in: bounds.insetBy(dx: 6, dy: 6))

            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 72, weight: .black)
            let symbol = UIImage(
                systemName: "lock.fill",
                withConfiguration: symbolConfig
            )?.withTintColor(.white, renderingMode: .alwaysOriginal)

            symbol?.draw(
                in: CGRect(x: 54, y: 43, width: 72, height: 80)
            )

            context.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.72).cgColor)
            context.cgContext.setLineWidth(5)
            context.cgContext.setLineCap(.round)
            context.cgContext.addArc(
                center: CGPoint(x: 90, y: 90),
                radius: 72,
                startAngle: -.pi * 0.18,
                endAngle: .pi * 0.18,
                clockwise: false
            )
            context.cgContext.strokePath()
        }
    }
}
