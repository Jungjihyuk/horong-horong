import Foundation

/// 같은 쪽지를 **본 창과 위젯 창이 동시에** 열고 있을 수 있다.
///
/// `@Query` 를 안 쓰기로 한 이상 저장소가 바뀌었다는 사실을 알려 줄 사람이 없다.
/// 성취 창이 쓰는 방식(`AchievementSummaryView` 의 «`@Query` 자동 갱신을 대신한다»)과 같이
/// 알림 한 번으로 양쪽이 다시 읽게 한다.
enum ReferenceChangeBroadcast {
    static let name = Notification.Name("horonghorong.reference.didChange")
    static let idKey = "referenceID"

    static func post(id: UUID) {
        NotificationCenter.default.post(name: name, object: nil, userInfo: [idKey: id])
    }

    static func id(from notification: Notification) -> UUID? {
        notification.userInfo?[idKey] as? UUID
    }
}
