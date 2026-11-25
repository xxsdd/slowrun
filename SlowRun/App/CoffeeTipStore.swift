import StoreKit
import SwiftUI
import RunCore

@MainActor
final class CoffeeTipStore: ObservableObject {
    static let productID = "slowrun.tip.coffee"

    @Published private(set) var product: Product?
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var message: String?
    @Published private(set) var pending = false
    private var listener: Task<Void, Never>?

    init() {
        listener = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.handle(result)
            }
        }
        Task { [weak self] in
            for await result in StoreKit.Transaction.unfinished {
                await self?.handle(result)
            }
        }
    }

    deinit { listener?.cancel() }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            product = try await Product.products(for: [Self.productID]).first {
                $0.id == Self.productID && $0.type == .consumable
            }
        } catch {
            product = nil
        }
    }

    func purchase() async {
        guard let product, !isPurchasing, !pending, AppStore.canMakePayments else { return }
        isPurchasing = true
        message = nil
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case let .success(result): await handle(result)
            case .pending:
                pending = true
                message = "购买待 Apple 确认。"
            case .userCancelled: break
            @unknown default: message = "暂时无法确认购买，请查看 Apple 购买记录。"
            }
        } catch {
            message = "购买未完成，请查看 Apple 购买记录后再试。"
        }
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        switch result {
        case let .verified(transaction) where transaction.productID == Self.productID:
            pending = false
            message = transaction.revocationDate == nil ? "咖啡收到啦，谢谢你支持慢慢跑！" : nil
            await transaction.finish()
        case let .unverified(transaction, _) where transaction.productID == Self.productID:
            pending = false
            message = "暂时无法确认购买，请查看 Apple 购买记录。"
        default: break
        }
    }
}

struct CoffeeTipView: View {
    @EnvironmentObject private var tips: CoffeeTipStore

    var body: some View {
        List {
            Section {
                Label(RunLanguage.text("请我喝杯咖啡"), systemImage: "cup.and.saucer.fill").font(.headline)
                Text(RunLanguage.text("如果慢慢跑陪你跑过一段喜欢的路，可以请开发者喝杯咖啡。每次单独确认，所有跑步功能都免费。"))
                if !AppStore.canMakePayments {
                    Text(RunLanguage.text("这台设备已限制 App 内购买。"))
                } else if let product = tips.product {
                    Button(RunLanguage.text("请喝咖啡 · %1$@", product.displayPrice)) {
                        Task { await tips.purchase() }
                    }
                    .disabled(tips.isPurchasing || tips.pending)
                } else if tips.isLoading {
                    ProgressView(RunLanguage.text("正在读取商店价格…"))
                } else {
                    Text(RunLanguage.text("商店暂时没有提供这杯咖啡。"))
                    Button(RunLanguage.text("重新读取价格")) { Task { await tips.load() } }
                }
                if let message = tips.message {
                    Text(RunLanguage.text(message)).font(.subheadline).accessibilityAddTraits(.isStaticText)
                }
            }.listRowBackground(RunPalette.surface)
        }
        .scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle(RunLanguage.text("支持开发者"))
        .task { if AppStore.canMakePayments { await tips.load() } }
    }
}
