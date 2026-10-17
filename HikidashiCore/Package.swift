// swift-tools-version:5.9
// Hikidashi の中身。
//   HikidashiKit: 画面に依存しない処理（メモの保存、共有シートの受け口、Claude での整理と取り出し）。
//                 アプリ本体と共有シートの拡張機能の両方から使う
//   HikidashiUI:  SwiftUI の画面（iOS のみ。macOS では空のモジュールになる）
//
//   cd HikidashiCore && swift test

import PackageDescription

let package = Package(
    name: "HikidashiCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HikidashiKit", targets: ["HikidashiKit"]),
        .library(name: "HikidashiUI", targets: ["HikidashiUI"]),
    ],
    targets: [
        .target(name: "HikidashiKit"),
        .target(name: "HikidashiUI", dependencies: ["HikidashiKit"]),
        .testTarget(name: "HikidashiKitTests", dependencies: ["HikidashiKit"]),
    ]
)
