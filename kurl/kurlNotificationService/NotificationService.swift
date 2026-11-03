import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    var decorator = PushFaceDecorator()
    private var original: UNNotificationContent?
    private var deliver: PushFaceOnce<UNNotificationContent>?
    private var work: Task<Void, Never>?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let deliver = PushFaceOnce(contentHandler)
        let decorator = decorator
        original = request.content
        self.deliver = deliver
        work = Task { deliver(await decorator.decorate(request.content)) }
    }

    override func serviceExtensionTimeWillExpire() {
        work?.cancel()
        if let original { deliver?(original) }
    }
}
