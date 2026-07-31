import CoreGraphics
import Foundation

/// 사용자가 마우스로 지정한 활동 영역. 전역 화면 좌표계의 사각형을 그대로 담는다.
/// 영역을 지정하지 않으면(nil) 컴패니언이 서 있는 화면 전체를 활동 영역으로 본다.
enum CompanionRoamingRegion {
    /// UserDefaults 에 "x,y,w,h" 로 저장한다. 화면 구성이 바뀌어도 원본 좌표를 잃지 않도록
    /// 검증·보정은 저장이 아니라 읽는 시점에 한다.
    static func storageValue(for rect: CGRect) -> String {
        [rect.origin.x, rect.origin.y, rect.width, rect.height]
            .map { String(format: "%.1f", $0) }
            .joined(separator: ",")
    }

    static func rect(fromStorageValue value: String) -> CGRect? {
        let parts = value.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4, parts[2] > 0, parts[3] > 0 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// 활동 무대가 될 화면 하나를 고른다.
    /// 지정한 영역이 있으면 그 영역과 가장 많이 겹치는 화면을, 없으면 기준점이 놓인 화면을 쓴다.
    /// 영역을 그렸던 디스플레이를 뽑아버려도 남아있는 화면 중 하나로 안전하게 떨어진다.
    static func stage(
        for region: CGRect?,
        fallbackPoint: CGPoint,
        screens: [CGRect],
        mainScreen: CGRect?
    ) -> CGRect? {
        guard !screens.isEmpty else { return mainScreen }

        if let region {
            let overlapping = screens
                .map { screen -> (screen: CGRect, area: CGFloat) in
                    let intersection = screen.intersection(region)
                    let area = intersection.isNull ? 0 : intersection.width * intersection.height
                    return (screen, area)
                }
                .filter { $0.area > 0 }
            if let best = overlapping.max(by: { $0.area < $1.area }) {
                return best.screen
            }
        }

        return screens.first { $0.contains(fallbackPoint) } ?? mainScreen ?? screens.first
    }

    /// 스프라이트 좌하단이 머무를 수 있는 사각형.
    /// 지정 영역을 화면 안으로 잘라낸 뒤, 캐릭터가 잘리지 않도록 스프라이트 크기만큼 안쪽으로 줄인다.
    /// 영역이 스프라이트보다 작아도 폭·높이 0 인 유효한 사각형을 돌려준다(제자리에 머문다).
    static func bounds(
        region: CGRect?,
        stage: CGRect,
        spriteSize: CGSize
    ) -> CGRect {
        var usable = stage
        if let region {
            let clipped = region.intersection(stage)
            if !clipped.isNull, clipped.width > 0, clipped.height > 0 {
                usable = clipped
            }
        }

        return CGRect(
            x: usable.minX,
            y: usable.minY,
            width: max(0, usable.width - spriteSize.width),
            height: max(0, usable.height - spriteSize.height)
        )
    }

    /// 사람이 읽을 수 있는 영역 설명. 설정 화면에 그대로 쓴다.
    static func description(for rect: CGRect?) -> String {
        guard let rect else { return "화면 전체" }
        return "\(Int(rect.width.rounded()))×\(Int(rect.height.rounded())) 영역"
    }
}
