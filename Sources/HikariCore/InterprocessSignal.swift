import Foundation

public enum InterprocessSignal {
    public static let screenSaverDidStart = Notification.Name(
        "com.hodadako.hikari.screenSaverDidStart"
    )
    public static let screenSaverDidStop = Notification.Name(
        "com.hodadako.hikari.screenSaverDidStop"
    )

    public static func post(_ name: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(
            name,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
