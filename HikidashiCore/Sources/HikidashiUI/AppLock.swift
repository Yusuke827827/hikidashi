// Face ID（または パスコード）でアプリをロックする。設定でオンにしたときだけ。
// アプリを離れたらロックし、戻ってきたら顔認証で開く。

#if os(iOS)
import HikidashiKit
import LocalAuthentication
import SwiftUI

@MainActor
@Observable
final class AppLock {
    static let shared = AppLock()
    static let settingKey = "appLock"

    var isOn: Bool { UserDefaults.standard.bool(forKey: Self.settingKey) }
    private(set) var locked = UserDefaults.standard.bool(forKey: AppLock.settingKey)
    private var authenticating = false

    /// 顔認証が使えるか（使えなければパスコード）
    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return L("パスコード", "Passcode")
        }
    }

    func lockIfNeeded() {
        if isOn { locked = true }
    }

    /// 認証してロックを外す。成功したら true
    @discardableResult
    func unlock() async -> Bool {
        guard locked, !authenticating else { return !locked }
        authenticating = true
        defer { authenticating = false }
        let ok = await Self.authenticate(reason: L("メモを開く", "Open your notes"))
        if ok { locked = false }
        return ok
    }

    /// オンにするときは、先に認証できることを確かめる
    func setOn(_ on: Bool) async -> Bool {
        if on {
            guard await Self.authenticate(reason: L("ロックをオンにする", "Turn on the lock")) else { return false }
        }
        UserDefaults.standard.set(on, forKey: Self.settingKey)
        if !on { locked = false }
        return on
    }

    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// ロック中の画面
struct LockScreen: View {
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill").font(.system(size: 40)).foregroundStyle(p.accent)
            Text("Mindrawer").font(Fonts.mincho(28)).foregroundStyle(p.text)
            Button {
                Task { await AppLock.shared.unlock() }
            } label: {
                Text(L("\(AppLock.biometryName) で開く", "Unlock with \(AppLock.biometryName)"))
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.bg.ignoresSafeArea())
        .task { await AppLock.shared.unlock() }
    }
}
#endif
