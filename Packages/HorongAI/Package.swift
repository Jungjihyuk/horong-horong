// swift-tools-version: 6.0

import PackageDescription

// 앱 타깃과 같은 수준을 유지한다. 파일 이동과 동시성 수정을 함께 하면
// 골든셋 점수가 바뀌었을 때 원인을 가릴 수 없기 때문이다.
// Phase 2 가 끝난 뒤 .v6 로 올린다 — docs/5. 운영/프로젝트 운영/12. 기술 문서/Architecture/horongai-folder-structure-decisions.md
let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "HorongAI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HorongAI", targets: ["HorongAI"]),
        .library(name: "HorongAIMLX", targets: ["HorongAIMLX"]),
        .library(name: "HorongAITestSupport", targets: ["HorongAITestSupport"]),
    ],
    targets: [
        // 무거운 의존이 없는 코어. 평가는 여기까지만 링크해 초 단위로 돈다.
        .target(
            name: "HorongAI",
            swiftSettings: swiftSettings
        ),
        // mlx-swift-lm 이 붙는 유일한 자리. 의존은 S3 에서 MLXTransport 와 함께 추가한다.
        .target(
            name: "HorongAIMLX",
            dependencies: ["HorongAI"],
            swiftSettings: swiftSettings
        ),
        // 제품에 포함되지 않는다. 패키지 테스트와 앱 테스트가 함께 쓰는 가짜 공급자·픽스처.
        .target(
            name: "HorongAITestSupport",
            dependencies: ["HorongAI"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "HorongAITests",
            dependencies: ["HorongAI", "HorongAITestSupport"],
            swiftSettings: swiftSettings
        ),
    ]
)
