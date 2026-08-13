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
    // 버전은 앱(`project.yml`)과 같은 범위를 쓴다. 두 주문서의 요구가 어긋나면
    // 해석 결과가 달라져 API 가 바뀌고 빌드가 깨진다.
    // `mlx-swift` 는 앱이 선언하지 않았지만 `import MLX` 가 쓰고 있어(전이 의존) 여기서는 명시한다.
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.6"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        // 무거운 의존이 없는 코어. 평가는 여기까지만 링크해 초 단위로 돈다.
        .target(
            name: "HorongAI",
            // 프롬프트 `.md` 는 태스크 폴더 안에 둔다 — 파서를 고치면 프롬프트도 함께 고치기 때문이다.
            // 소스와 같은 폴더라 디렉터리째가 아니라 파일 단위로 선언한다.
            resources: [
                .process("Tasks/GoalRecommendation/weekly_goal.md"),
                .process("Tasks/GoalRecommendation/monthly_goal.md"),
            ],
            swiftSettings: swiftSettings
        ),
        // 소스를 내려받아 컴파일하는 의존이 붙는 유일한 자리.
        .target(
            name: "HorongAIMLX",
            dependencies: [
                "HorongAI",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
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
