import CoreNFC
import Foundation

final class NFCService: NSObject {
    enum Mode {
        case scan
        case write(String)
    }

    static var isAvailable: Bool {
        NFCNDEFReaderSession.readingAvailable
    }

    var onRead: ((String) -> Void)?
    var onWrite: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private var session: NFCNDEFReaderSession?
    private var mode: Mode = .scan

    func scan() {
        guard Self.isAvailable else {
            onError?("NFC scanning is not available on this device.")
            return
        }

        mode = .scan
        let session = NFCNDEFReaderSession(
            delegate: self,
            queue: nil,
            invalidateAfterFirstRead: true
        )
        session.alertMessage = "Hold your iPhone near your Broke focus tag."
        self.session = session
        session.begin()
    }

    func write(payload: String) {
        guard Self.isAvailable else {
            onError?("Writing an NFC tag requires a supported physical iPhone.")
            return
        }

        mode = .write(payload)
        let session = NFCNDEFReaderSession(
            delegate: self,
            queue: nil,
            invalidateAfterFirstRead: false
        )
        session.alertMessage = "Hold your iPhone near a writable NDEF tag."
        self.session = session
        session.begin()
    }

    private func textRecord(for text: String) -> NFCNDEFPayload {
        let language = Data("en".utf8)
        let status = UInt8(language.count)
        var payload = Data([status])
        payload.append(language)
        payload.append(Data(text.utf8))

        return NFCNDEFPayload(
            format: .nfcWellKnown,
            type: Data([0x54]),
            identifier: Data(),
            payload: payload
        )
    }

    private func text(from message: NFCNDEFMessage) -> String? {
        for record in message.records {
            guard record.typeNameFormat == .nfcWellKnown,
                  record.type == Data([0x54]),
                  let status = record.payload.first else {
                continue
            }

            let languageLength = Int(status & 0x3F)
            let textStart = 1 + languageLength
            guard record.payload.count > textStart else { continue }

            let textData = record.payload.subdata(in: textStart..<record.payload.count)
            if let value = String(data: textData, encoding: .utf8),
               value.hasPrefix("broke://focus/") {
                return value
            }
        }
        return nil
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
        guard case .scan = mode,
              let payload = messages.compactMap(text(from:)).first else {
            DispatchQueue.main.async { [weak self] in
                self?.onError?("That tag does not contain a valid Broke NDEF key.")
            }
            return
        }

        session.alertMessage = "Focus tag recognized."
        DispatchQueue.main.async { [weak self] in
            self?.onRead?(payload)
        }
    }

    func readerSession(
        _ session: NFCNDEFReaderSession,
        didDetect tags: [NFCNDEFTag]
    ) {
        guard case .write(let payload) = mode else { return }
        guard tags.count == 1, let tag = tags.first else {
            session.alertMessage = "More than one tag detected. Present only one."
            session.restartPolling()
            return
        }

        session.connect(to: tag) { [weak self] error in
            guard error == nil else {
                session.alertMessage = "Could not connect to this tag."
                session.invalidate()
                return
            }

            tag.queryNDEFStatus { status, capacity, error in
                guard error == nil, status == .readWrite else {
                    session.alertMessage = "This tag is not writable."
                    session.invalidate()
                    return
                }

                guard let self else { return }
                let message = NFCNDEFMessage(records: [self.textRecord(for: payload)])
                guard message.length <= capacity else {
                    session.alertMessage = "This tag does not have enough space."
                    session.invalidate()
                    return
                }

                tag.writeNDEF(message) { error in
                    if error == nil {
                        session.alertMessage = "Your Broke focus tag is ready."
                        session.invalidate()
                        DispatchQueue.main.async {
                            self.onWrite?(payload)
                        }
                    } else {
                        session.alertMessage = "The tag could not be written."
                        session.invalidate()
                    }
                }
            }
        }
    }
}
