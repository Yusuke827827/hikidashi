// iCloud で同期（設定でオンにしたときだけ）。自分の iCloud の非公開データベースに、メモを 1 件ずつ置く。
// 運営側のサーバーは通らない。同じメモが両方で変わったときは、後から変えた方を残す。画像は同期しない。

#if os(iOS)
import CloudKit
import Foundation
import HikidashiKit

@MainActor
final class CloudSync: CKSyncEngineDelegate {
    static let shared = CloudSync()

    static let settingKey = "iCloudSync"
    private static let stateKey = "iCloudSyncState"
    private static let zoneName = "Notes"
    private static let recordType = "Note"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: settingKey) }

    /// iCloud のコンテナ（project.yml の CLOUD_CONTAINER）
    static var containerID: String? {
        (Bundle.main.object(forInfoDictionaryKey: "MindrawerCloudContainer") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private var engine: CKSyncEngine?
    private weak var store: NoteStore?
    private let zoneID = CKRecordZone.ID(zoneName: CloudSync.zoneName)
    /// サーバーにあるレコードの情報（上書きのときに必要）。recordName → encodeSystemFields の中身
    private var systemFields: [String: Data] = [:]
    private var fieldsURL: URL? { store.map { $0.root.appendingPathComponent("cloud-fields.plist") } }

    var lastError: String?

    /// iCloud にサインインしているか
    static func accountAvailable() async -> Bool {
        guard let id = containerID else { return false }
        let status = try? await CKContainer(identifier: id).accountStatus()
        return status == .available
    }

    /// 同期を始める（アプリ起動時、またはオンにしたとき）
    func start(store: NoteStore, uploadAll: Bool = false) {
        guard engine == nil, let id = Self.containerID else { return }
        self.store = store
        loadFields()
        var state: CKSyncEngine.State.Serialization?
        if let data = UserDefaults.standard.data(forKey: Self.stateKey) {
            state = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }
        let config = CKSyncEngine.Configuration(database: CKContainer(identifier: id).privateCloudDatabase,
                                                stateSerialization: state, delegate: self)
        let engine = CKSyncEngine(config)
        self.engine = engine
        if state == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        }
        store.onChange = { [weak self] saved, deleted in self?.enqueue(saved: saved, deleted: deleted) }
        if uploadAll || state == nil {
            enqueue(saved: store.notes.filter { !$0.example }.map(\.id), deleted: [])
        }
        Task { try? await engine.fetchChanges() }
    }

    /// 同期を止める（iCloud のデータはそのまま残す）
    func stop() {
        store?.onChange = nil
        engine = nil
        UserDefaults.standard.removeObject(forKey: Self.stateKey)
        systemFields = [:]
        if let url = fieldsURL { try? FileManager.default.removeItem(at: url) }
    }

    /// アプリを開いたときに、他の端末の変更を取りにいく
    func fetch() async {
        try? await engine?.fetchChanges()
    }

    private func enqueue(saved: [String], deleted: [String]) {
        guard let engine else { return }
        let changes: [CKSyncEngine.PendingRecordZoneChange] =
            saved.map { .saveRecord(CKRecord.ID(recordName: $0, zoneID: zoneID)) } +
            deleted.map { .deleteRecord(CKRecord.ID(recordName: $0, zoneID: zoneID)) }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    // MARK: レコードとメモの変換

    private func record(for note: Note) -> CKRecord {
        let id = CKRecord.ID(recordName: note.id, zoneID: zoneID)
        var record = CKRecord(recordType: Self.recordType, recordID: id)
        if let data = systemFields[note.id], let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
            coder.requiresSecureCoding = true
            if let r = CKRecord(coder: coder) { record = r }
            coder.finishDecoding()
        }
        var n = note
        n.imageFile = nil
        record["json"] = (try? JSONEncoder().encode(n)) as CKRecordValue?
        record["modifiedAt"] = note.modifiedAt as CKRecordValue
        return record
    }

    private static func note(from record: CKRecord) -> Note? {
        guard let data = record["json"] as? Data else { return nil }
        return try? JSONDecoder().decode(Note.self, from: data)
    }

    private func remember(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        systemFields[record.recordID.recordName] = coder.encodedData
    }

    private func loadFields() {
        guard let url = fieldsURL, let data = try? Data(contentsOf: url),
              let dict = try? PropertyListDecoder().decode([String: Data].self, from: data) else { return }
        systemFields = dict
    }

    private func saveFields() {
        guard let url = fieldsURL, let data = try? PropertyListEncoder().encode(systemFields) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                UserDefaults.standard.set(data, forKey: Self.stateKey)
            }

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                if let store { enqueue(saved: store.notes.filter { !$0.example }.map(\.id), deleted: []) }
            case .signOut, .switchAccounts:
                systemFields = [:]
                saveFields()
            @unknown default:
                break
            }

        case .fetchedRecordZoneChanges(let changes):
            var saved: [Note] = []
            for m in changes.modifications {
                remember(m.record)
                if let n = Self.note(from: m.record) { saved.append(n) }
            }
            let deleted = changes.deletions.map(\.recordID.recordName)
            for d in deleted { systemFields[d] = nil }
            store?.applyRemote(saved: saved, deleted: deleted)
            saveFields()

        case .sentRecordZoneChanges(let sent):
            for r in sent.savedRecords { remember(r) }
            for id in sent.deletedRecordIDs { systemFields[id.recordName] = nil }
            for failure in sent.failedRecordSaves {
                let name = failure.record.recordID.recordName
                switch failure.error.code {
                case .serverRecordChanged:
                    // 他の端末が先に変えていた。新しい方を残す
                    guard let server = failure.error.serverRecord else { continue }
                    remember(server)
                    let local = store?.note(name)
                    if let remote = Self.note(from: server), local == nil || remote.modifiedAt >= local!.modifiedAt {
                        store?.applyRemote(saved: [remote], deleted: [])
                    } else {
                        enqueue(saved: [name], deleted: [])
                    }
                case .zoneNotFound:
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                    enqueue(saved: [name], deleted: [])
                case .unknownItem:
                    systemFields[name] = nil
                    enqueue(saved: [name], deleted: [])
                default:
                    lastError = failure.error.localizedDescription
                }
            }
            saveFields()

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        var wanted = Set<String>()
        for change in pending {
            if case .saveRecord(let id) = change { wanted.insert(id.recordName) }
        }
        var records: [String: CKRecord] = [:]
        for n in store?.notes ?? [] where wanted.contains(n.id) {
            records[n.id] = record(for: n)
        }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            // 消えたメモは送らない（保存の予定から外れる）
            records[id.recordName]
        }
    }
}
#endif
