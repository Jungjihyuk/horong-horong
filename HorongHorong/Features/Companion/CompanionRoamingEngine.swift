import CoreGraphics
import Foundation

/// 컴패니언이 활동 영역 안을 돌아다니는 동작을 계산하는 순수 로직.
/// 영역 안의 임의의 지점을 목표로 잡아 걸어가고, 도착하면 잠시 쉬었다가 다시 목표를 고른다.
/// 창·타이머 없이 값만 다루므로 그대로 테스트할 수 있다.
struct CompanionRoamingEngine {
    enum Motion: Equatable, Sendable {
        case resting
        case moving
    }

    /// 스프라이트 좌하단이 머무를 수 있는 사각형. 화면 경계와 활동 영역이 모두 반영된 값이다.
    let bounds: CGRect
    let speed: CGFloat
    private(set) var position: CGPoint
    private(set) var motion: Motion = .resting
    /// 좌우 스프라이트를 고르는 기준. 수직으로만 움직일 때는 직전 방향을 유지한다.
    private(set) var facesLeft = false

    private var target: CGPoint?
    private var restRemainingSeconds: Double = 0

    init(bounds: CGRect, start: CGPoint, speed: CGFloat = Constants.companionWalkSpeed) {
        self.bounds = bounds
        self.speed = speed
        self.position = Self.clamp(start, to: bounds)
    }

    var animation: CompanionAnimation {
        switch motion {
        case .resting:
            return .idle
        case .moving:
            return facesLeft ? .runningLeft : .runningRight
        }
    }

    mutating func advance(by seconds: Double, using generator: inout some RandomNumberGenerator) {
        guard seconds > 0 else { return }
        guard bounds.width > 0 || bounds.height > 0 else {
            // 영역이 스프라이트보다 작으면 제자리에 머문다.
            position = bounds.origin
            motion = .resting
            return
        }

        guard let target else {
            restRemainingSeconds -= seconds
            if restRemainingSeconds <= 0 {
                chooseTarget(using: &generator)
            }
            return
        }

        let dx = target.x - position.x
        let dy = target.y - position.y
        let distance = (dx * dx + dy * dy).squareRoot()
        let step = CGFloat(seconds) * speed

        if distance <= step || distance == 0 {
            position = target
            self.target = nil
            motion = .resting
            restRemainingSeconds = Double.random(in: 1.0...3.5, using: &generator)
        } else {
            position.x += dx / distance * step
            position.y += dy / distance * step
        }

        position = Self.clamp(position, to: bounds)
    }

    /// 사용자가 캐릭터를 끌어 옮겼을 때. 활동 영역 안으로 붙잡고, 가던 목표는 버린다.
    mutating func reposition(to point: CGPoint) {
        position = Self.clamp(point, to: bounds)
        target = nil
        motion = .resting
        // 놓자마자 다시 걸어가버리지 않도록 잠깐 멈춰 세운다.
        restRemainingSeconds = 0.8
    }

    private mutating func chooseTarget(using generator: inout some RandomNumberGenerator) {
        let nextX = bounds.width > 0
            ? CGFloat.random(in: bounds.minX...bounds.maxX, using: &generator)
            : bounds.minX
        let nextY = bounds.height > 0
            ? CGFloat.random(in: bounds.minY...bounds.maxY, using: &generator)
            : bounds.minY
        let next = CGPoint(x: nextX, y: nextY)

        guard next != position else {
            restRemainingSeconds = Double.random(in: 1.0...3.5, using: &generator)
            return
        }

        target = next
        motion = .moving
        // 좌우 이동이 거의 없으면(수직 이동) 직전에 보던 방향을 그대로 둔다.
        let dx = next.x - position.x
        if abs(dx) > 0.5 {
            facesLeft = dx < 0
        }
    }

    private static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }
}
