import SwiftUI
import UIKit

/// Applies readable tab item colors even on newer iOS tab-bar materials.
/// SwiftUI's `tint` controls the selected item, but the system can choose a very
/// low-contrast unselected tint. This bridge styles both states explicitly.
struct MomentsTabBarStyleApplier: UIViewRepresentable {
    let mode: MomentsAppearanceMode
    let colorScheme: ColorScheme

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { apply(from: view) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { apply(from: uiView) }
    }

    private func apply(from anchor: UIView) {
        guard let window = anchor.window else { return }
        for tabBar in findTabBars(in: window) {
            let colors = colorsForCurrentMode()
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = colors.background
            appearance.shadowColor = colors.border

            appearance.stackedLayoutAppearance = itemAppearance(selected: colors.selected, normal: colors.normal)
            appearance.inlineLayoutAppearance = itemAppearance(selected: colors.selected, normal: colors.normal)
            appearance.compactInlineLayoutAppearance = itemAppearance(selected: colors.selected, normal: colors.normal)

            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            tabBar.tintColor = colors.selected
            tabBar.unselectedItemTintColor = colors.normal
            tabBar.isTranslucent = false
        }
    }

    private func itemAppearance(selected: UIColor, normal: UIColor) -> UITabBarItemAppearance {
        let item = UITabBarItemAppearance()
        item.normal.iconColor = normal
        item.normal.titleTextAttributes = [
            .foregroundColor: normal,
            .font: UIFont.systemFont(ofSize: 10.5, weight: .semibold)
        ]
        item.selected.iconColor = selected
        item.selected.titleTextAttributes = [
            .foregroundColor: selected,
            .font: UIFont.systemFont(ofSize: 10.5, weight: .bold)
        ]
        return item
    }

    private func colorsForCurrentMode() -> (background: UIColor, selected: UIColor, normal: UIColor, border: UIColor) {
        switch mode {
        case .moments:
            // Deliberately dark icon/text colors on the light lavender bar.
            return (
                UIColor(red: 0.945, green: 0.925, blue: 0.975, alpha: 1),
                UIColor(red: 0.290, green: 0.090, blue: 0.535, alpha: 1),
                UIColor(red: 0.245, green: 0.215, blue: 0.300, alpha: 1),
                UIColor(red: 0.825, green: 0.785, blue: 0.890, alpha: 1)
            )
        case .contrast:
            if colorScheme == .dark {
                return (.black, .white, UIColor(white: 0.74, alpha: 1), UIColor(white: 0.25, alpha: 1))
            }
            return (.white, .black, UIColor(white: 0.30, alpha: 1), UIColor(white: 0.82, alpha: 1))
        case .system:
            return (
                .systemBackground,
                UIColor(red: 0.376, green: 0.145, blue: 0.690, alpha: 1),
                .secondaryLabel,
                .separator
            )
        }
    }

    private func findTabBars(in view: UIView) -> [UITabBar] {
        var result: [UITabBar] = []
        if let bar = view as? UITabBar { result.append(bar) }
        for child in view.subviews { result.append(contentsOf: findTabBars(in: child)) }
        return result
    }
}
