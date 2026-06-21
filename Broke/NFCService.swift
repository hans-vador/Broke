import CoreNFC
import Foundation

final class NFCService: NSObject {
    enum Mode {
        case scan
        case pair
    }

    static var isAvailable: Bool {
        NFCNDEFReaderSession.readingAvailable
    }

    var onRead: ((String) -> Void)?
    var onPair: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private var session: NFCNDEFReaderSession?
    private var mode: Mode = .scan
    private var successMessage = "Broke tag recognized."

    func scan(successMessage: String) {
        beginSession(
            mode: .scan,
            alertMessage: "Hold your iPhone near your paired Broke tag.",
            successMessage: successMessage
        )
    }

    func pair() {
        beginSession(
            mode: .pair,
            alertMessage: "Hold your iPhone near your prewritten Broke tag.",
            successMessage: "Broke tag paired."
        )
    }

    private func beginSession(mode: Mode, alertMessage: String, successMessage: String) {
        guard Self.isAvailable else {
            onError?("NFC scanning is not available on this device.")
            return
        }

        self.mode = mode
        self.successMessage = successMessage
        let session = NFCNDEFReaderSession(
            delegate: self,
            queue: nil,
            invalidateAfterFirstRead: true
        )
        session.alertMessage = alertMessage
        self.session = session
        session.begin()
    }

    private func brokeTagPayload(from message: NFCNDEFMessage) -> String? {
        for record in message.records {
            if let uri = uri(from: record), let payload = Self.validatedPayload(uri) {
                return payload
            }

            if let text = text(from: record), let payload = Self.validatedPayload(text) {
                return payload
            }
        }
        return nil
    }

    private func uri(from record: NFCNDEFPayload) -> String? {
        guard record.typeNameFormat == .nfcWellKnown,
              record.type == Data([0x55]),
              record.payload.first == 0 else {
            return nil
        }

        return String(data: Data(record.payload.dropFirst()), encoding: .utf8)
    }

    private func text(from record: NFCNDEFPayload) -> String? {
        guard record.typeNameFormat == .nfcWellKnown,
              record.type == Data([0x54]),
              let status = record.payload.first else {
            return nil
        }

        let languageLength = Int(status & 0x3F)
        let textStart = 1 + languageLength
        guard record.payload.count > textStart else { return nil }
        return String(data: record.payload[textStart...], encoding: .utf8)
    }

    static func validatedPayload(_ value: String) -> String? {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "broke",
              components.host?.lowercased() == "tag" else {
            return nil
        }

        let path = components.path.split(separator: "/").map(String.init)
        guard path.count == 2,
              path[0] == "v1",
              let tagID = UUID(uuidString: path[1]) else {
            return nil
        }

        return "broke://tag/v1/\(tagID.uuidString.lowercased())"
    }
}

extension NFCService: NFCNDEFReaderSessionDelegate {
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {}

    func readerSession(
        _ session: NFCNDEFReaderSession,
        didInvalidateWithError error: Error
    ) {
        let readerError = error as? NFCReaderError
        guard readerError?.code != .readerSessionInvalidationErrorUserCanceled,
              readerError?.code != .readerSessionInvalidationErrorFirstNDEFTagRead else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onError?("The NFC session ended before the tag could be read. Please try again.")
        }
    }

    func readerSession(
        _ session: NFCNDEFReaderSession,
        didDetectNDEFs messages: [NFCNDEFMessage]
    ) {
        guard let payload = messages.compactMap(brokeTagPayload(from:)).first else {
            DispatchQueue.main.async { [weak self] in
                self?.onError?("That tag is not a valid prewritten Broke tag.")
            }
            return
        }

        session.alertMessage = successMessage
        DispatchQueue.main.async { [weak self] in
            switch self?.mode {
            case .pair:
                self?.onPair?(payload)
            case .scan:
                self?.onRead?(payload)
            case nil:
                break
            }
        }
    }
}
