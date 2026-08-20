import SwiftUI
import StoreKit
import WattsonCore

/// The paywall.
///
/// Three rules shaped this screen, all of them App Review requirements as much as
/// good manners: the price, the billing period and the renewal terms are on screen
/// before the buy button; Restore Purchases is always reachable; and the free tier
/// is described honestly so nobody buys to get something they already have.
@MainActor
struct PaywallView: View {

    @ObservedObject var store: StoreManager
    var onClose: () -> Void = {}

    @State private var selectedProductID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    featureGrid
                    plans
                    freeTierNote
                    legal
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(width: 520, height: 620)
        .task {
            if store.products.isEmpty { await store.bootstrap() }
            selectedProductID = store.products.first(where: { $0.id == StoreManager.ProductID.yearly })?.id
                ?? store.products.first?.id
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            MascotView(mood: .fullAndSmug, skin: .neon, level: 1, staticPhase: 0.6)
                .frame(width: 56, height: 68)

            VStack(alignment: .leading, spacing: 3) {
                Text("Wattson Pro")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Everything in Wattson, plus the parts that make it yours.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isPro {
                Text("Active")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.18), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
        .padding(18)
    }

    // MARK: - Features

    private var featureGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(ProFeature.allCases, id: \.self) { feature in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: feature.systemImage)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(feature.title)
                            .font(.system(size: 11, weight: .semibold))
                        Text(feature.blurb)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Plans

    @ViewBuilder
    private var plans: some View {
        switch store.loadState {
        case .loading, .idle:
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading plans…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)

        case .failed(let message):
            VStack(spacing: 8) {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await store.bootstrap() } }
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)

        case .loaded:
            VStack(spacing: 8) {
                ForEach(store.products, id: \.id) { product in
                    planRow(product)
                }
            }
        }
    }

    private func planRow(_ product: Product) -> some View {
        let isSelected = selectedProductID == product.id
        let isYearly = product.id == StoreManager.ProductID.yearly

        return Button {
            selectedProductID = product.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(planTitle(product))
                            .font(.system(size: 13, weight: .semibold))
                        if isYearly, let saving = store.annualSavingPercent() {
                            Text("Save \(saving)%")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.green.opacity(0.18), in: Capsule())
                                .foregroundStyle(.green)
                        }
                    }
                    if let intro = store.introductoryOfferText(for: product) {
                        Text(intro)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text(renewalDescription(product))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func planTitle(_ product: Product) -> String {
        product.subscription == nil ? "\(product.displayName) · one-time" : product.displayName
    }

    private func renewalDescription(_ product: Product) -> String {
        guard product.subscription != nil else { return "Pay once. Yours for good." }
        return "\(product.displayPrice) per \(store.priceCadence(for: product)) · renews automatically"
    }

    // MARK: - Honesty & legal

    private var freeTierNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Free forever, with or without Pro")
                .font(.system(size: 11, weight: .semibold))
            ForEach(EntitlementMatrix.freeTierPromise, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                    Text(line)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
    }

    private var legal: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel in App Store → Account → Subscriptions. Payment is charged to your Apple Account on confirmation.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") ?? URL(fileURLWithPath: "/"))
                Link("Privacy Policy", destination: URL(string: "https://wattson.app/privacy") ?? URL(fileURLWithPath: "/"))
            }
            .font(.system(size: 9))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            if case .failed(let message) = store.purchaseState {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            if case .pending = store.purchaseState {
                Text("Waiting for approval. Pro switches on by itself once the purchase is approved.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Restore purchases") {
                    Task { await store.restore() }
                }
                .buttonStyle(.link)

                Spacer()

                Button("Not now") { onClose() }

                Button(action: purchaseSelected) {
                    if isPurchasing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(store.isPro ? "Pro is active" : "Continue")
                            .frame(minWidth: 80)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isPro || selectedProductID == nil || isPurchasing)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .onChange(of: store.isPro) { isPro in
            // Close on success so the user lands straight back on the thing they
            // were trying to unlock.
            if isPro { onClose() }
        }
    }

    private var isPurchasing: Bool {
        if case .purchasing = store.purchaseState { return true }
        return false
    }

    private func purchaseSelected() {
        guard let product = store.products.first(where: { $0.id == selectedProductID }) else { return }
        Task { await store.purchase(product) }
    }
}
