import CoreData
import Foundation
import Security

struct HistoryVisit: Identifiable, Hashable {
    let id: UUID
    let title: String
    let url: URL
    let tabID: UUID
    let spaceID: UUID
    let visitedAt: Date
}

struct PersistenceSyncConfiguration: Equatable {
    static let cloudKitContainerIdentifier = "iCloud.org.lumabrowser.LumaBrowser"

    var syncsWorkspaceWithICloud: Bool
    var syncsHistoryWithICloud: Bool
    var cloudKitContainerIdentifier: String

    static var current: PersistenceSyncConfiguration {
        let canUseICloud = LumaCloudKitEntitlements.hasConfiguredContainer
        return PersistenceSyncConfiguration(
            syncsWorkspaceWithICloud: canUseICloud && LumaSyncPreferences.syncsWorkspaceWithICloud,
            syncsHistoryWithICloud: canUseICloud
                && LumaSyncPreferences.syncsWorkspaceWithICloud
                && LumaSyncPreferences.syncsHistoryWithICloud,
            cloudKitContainerIdentifier: cloudKitContainerIdentifier
        )
    }

    static var localOnly: PersistenceSyncConfiguration {
        PersistenceSyncConfiguration(
            syncsWorkspaceWithICloud: false,
            syncsHistoryWithICloud: false,
            cloudKitContainerIdentifier: cloudKitContainerIdentifier
        )
    }
}

enum LumaSyncPreferences {
    private static let workspaceKey = "Luma.Sync.WorkspaceWithICloud"
    private static let historyKey = "Luma.Sync.HistoryWithICloud"

    static var syncsWorkspaceWithICloud: Bool {
        get { UserDefaults.standard.bool(forKey: workspaceKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: workspaceKey)
            if !newValue {
                syncsHistoryWithICloud = false
            }
        }
    }

    static var syncsHistoryWithICloud: Bool {
        get { UserDefaults.standard.bool(forKey: historyKey) }
        set { UserDefaults.standard.set(newValue, forKey: historyKey) }
    }
}

enum LumaCloudKitEntitlements {
    static var hasConfiguredContainer: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        guard let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.icloud-container-identifiers" as CFString,
            nil
        ) else {
            return false
        }

        if let containers = value as? [String] {
            return containers.contains(PersistenceSyncConfiguration.cloudKitContainerIdentifier)
        }

        return false
    }
}

struct PersistenceService: @unchecked Sendable {
    static let shared = PersistenceService()
    static let remoteStoreDidChange = Notification.Name("Luma.PersistenceService.RemoteStoreDidChange")

    private static let appName = "Luma"
    private static let legacyAppName = "Luma Browser"

    private let container: NSPersistentContainer
    private let syncConfiguration: PersistenceSyncConfiguration
    private let remoteChangeObserver: NSObjectProtocol?
    private let loadsLegacyJSONState: Bool

    var syncsWorkspaceWithICloud: Bool {
        syncConfiguration.syncsWorkspaceWithICloud
    }

    var syncsHistoryWithICloud: Bool {
        syncConfiguration.syncsHistoryWithICloud
    }

    init(
        storeURL: URL? = nil,
        syncConfiguration: PersistenceSyncConfiguration = .current
    ) {
        self.syncConfiguration = syncConfiguration
        loadsLegacyJSONState = storeURL == nil
        let model = Self.makeModel()
        let usesCloudKit = syncConfiguration.syncsWorkspaceWithICloud || syncConfiguration.syncsHistoryWithICloud
        let container: NSPersistentContainer = usesCloudKit
            ? NSPersistentCloudKitContainer(name: "Luma", managedObjectModel: model)
            : NSPersistentContainer(name: "Luma", managedObjectModel: model)
        let storeURLs = Self.storeURLs(from: storeURL)
        let needsLegacyMigration = storeURL == nil
            && !FileManager.default.fileExists(atPath: storeURLs.session.path)
            && FileManager.default.fileExists(atPath: Self.legacyCombinedStoreURL.path)

        container.persistentStoreDescriptions = [
            Self.storeDescription(
                url: storeURLs.session,
                configuration: StoreConfiguration.session,
                cloudKitContainerIdentifier: syncConfiguration.syncsWorkspaceWithICloud
                    ? syncConfiguration.cloudKitContainerIdentifier
                    : nil
            ),
            Self.storeDescription(
                url: storeURLs.history,
                configuration: StoreConfiguration.history,
                cloudKitContainerIdentifier: syncConfiguration.syncsHistoryWithICloud
                    ? syncConfiguration.cloudKitContainerIdentifier
                    : nil
            )
        ]

        do {
            try FileManager.default.createDirectory(
                at: storeURLs.session.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: storeURLs.history.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            NSLog("\(Self.appName) failed to create persistence folder: \(error.localizedDescription)")
        }

        container.loadPersistentStores { _, error in
            if let error {
                NSLog("\(Self.appName) failed to load Core Data store: \(error.localizedDescription)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        self.container = container
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: Self.remoteStoreDidChange, object: nil)
        }

        if needsLegacyMigration {
            migrateLegacyCombinedStore(from: Self.legacyCombinedStoreURL)
        }
    }

    private static func storeURLs(from baseStoreURL: URL?) -> (session: URL, history: URL) {
        guard let baseStoreURL else {
            return (
                applicationSupportURL.appendingPathComponent("LumaSession.sqlite"),
                applicationSupportURL.appendingPathComponent("LumaHistory.sqlite")
            )
        }

        let directory = baseStoreURL.deletingLastPathComponent()
        let baseName = baseStoreURL.deletingPathExtension().lastPathComponent
        return (
            directory.appendingPathComponent("\(baseName)-Session.sqlite"),
            directory.appendingPathComponent("\(baseName)-History.sqlite")
        )
    }

    private static func storeDescription(
        url: URL,
        configuration: String,
        cloudKitContainerIdentifier: String?
    ) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.configuration = configuration
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        if let cloudKitContainerIdentifier {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: cloudKitContainerIdentifier
            )
        }

        return description
    }

    private static var applicationSupportURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let currentURL = baseURL.appendingPathComponent(appName, isDirectory: true)
        let legacyURL = baseURL.appendingPathComponent(legacyAppName, isDirectory: true)

        if !FileManager.default.fileExists(atPath: currentURL.path),
           FileManager.default.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }

        return currentURL
    }

    private static var legacyCombinedStoreURL: URL {
        applicationSupportURL.appendingPathComponent("Luma.sqlite")
    }

    private static var legacyStateURL: URL {
        applicationSupportURL.appendingPathComponent("session.json")
    }

    func loadState() -> BrowserWindowState? {
        if let state = loadCoreDataState() {
            return state
        }

        guard loadsLegacyJSONState, let legacyState = loadLegacyJSONState() else {
            return nil
        }

        saveState(legacyState)
        return legacyState
    }

    func saveState(_ state: BrowserWindowState) {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        context.performAndWait {
            do {
                try upsert(state, in: context)
                try context.save()
            } catch {
                context.rollback()
                NSLog("\(Self.appName) failed to save session: \(error.localizedDescription)")
            }
        }
    }

    func recordVisit(title: String, url: URL, tabID: UUID, spaceID: UUID, visitedAt: Date = Date()) {
        let context = container.newBackgroundContext()
        let visit = HistoryVisit(
            id: UUID(),
            title: title,
            url: url,
            tabID: tabID,
            spaceID: spaceID,
            visitedAt: visitedAt
        )

        context.perform {
            Self.insert(visit, in: context)

            do {
                try context.save()
            } catch {
                context.rollback()
                NSLog("\(Self.appName) failed to record history visit: \(error.localizedDescription)")
            }
        }
    }

    func recentHistory(
        matching rawQuery: String = "",
        in spaceID: UUID? = nil,
        limit: Int = 8
    ) -> [HistoryVisit] {
        guard limit > 0 else { return [] }

        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = container.viewContext

        return context.performAndWait {
            do {
                let request = NSFetchRequest<NSManagedObject>(entityName: Entity.historyVisit)
                request.sortDescriptors = [NSSortDescriptor(key: Key.visitedAt, ascending: false)]
                request.fetchLimit = max(limit * 4, limit)

                var predicates: [NSPredicate] = []

                if let spaceID {
                    predicates.append(NSPredicate(format: "%K == %@", Key.spaceID, spaceID as NSUUID))
                }

                if !query.isEmpty {
                    predicates.append(
                        NSCompoundPredicate(
                            orPredicateWithSubpredicates: [
                                NSPredicate(format: "%K CONTAINS[cd] %@", Key.title, query),
                                NSPredicate(format: "%K CONTAINS[cd] %@", Key.urlString, query)
                            ]
                        )
                    )
                }

                if predicates.count == 1 {
                    request.predicate = predicates[0]
                } else if !predicates.isEmpty {
                    request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                }

                var seenURLs = Set<String>()
                var visits: [HistoryVisit] = []

                for visit in try context.fetch(request).compactMap(Self.historyVisit(from:)) {
                    let key = visit.url.absoluteString
                    guard !seenURLs.contains(key) else { continue }
                    seenURLs.insert(key)
                    visits.append(visit)

                    if visits.count == limit {
                        break
                    }
                }

                return visits
            } catch {
                NSLog("\(Self.appName) failed to load history: \(error.localizedDescription)")
                return []
            }
        }
    }

    private func loadCoreDataState() -> BrowserWindowState? {
        let context = container.viewContext
        return Self.loadCoreDataState(in: context)
    }

    private func loadLegacyJSONState() -> BrowserWindowState? {
        do {
            let data = try Data(contentsOf: Self.legacyStateURL)
            return try JSONDecoder.luma.decode(BrowserWindowState.self, from: data)
        } catch {
            return nil
        }
    }

    private func upsert(_ state: BrowserWindowState, in context: NSManagedObjectContext) throws {
        let session = try fetchSession(in: context)
        session.setValue("main", forKey: Key.id)
        session.setValue(state.activeSpaceID, forKey: Key.activeSpaceID)
        session.setValue(state.activeTabID, forKey: Key.activeTabID)
        session.setValue(state.splitTabID, forKey: Key.splitTabID)
        session.setValue(state.isSplitViewEnabled, forKey: Key.isSplitViewEnabled)

        let existingSpaces = try fetchObjects(entityName: Entity.space, in: context)
        var spacesByID = Dictionary(
            uniqueKeysWithValues: existingSpaces.compactMap { object -> (UUID, NSManagedObject)? in
                guard let id = object.uuid(for: Key.id) else { return nil }
                return (id, object)
            }
        )

        for space in state.spaces {
            let object = spacesByID[space.id]
                ?? NSEntityDescription.insertNewObject(forEntityName: Entity.space, into: context)
            object.setValue(space.id, forKey: Key.id)
            object.setValue(space.name, forKey: Key.name)
            object.setValue(space.symbolName, forKey: Key.symbolName)
            object.setValue(space.themeColorHex, forKey: Key.themeColorHex)
            object.setValue(space.themeAppearance.rawValue, forKey: Key.themeAppearance)
            object.setValue(space.themeOpacity, forKey: Key.themeOpacity)
            object.setValue(space.themeTexture, forKey: Key.themeTexture)
            object.setValue(space.dataStoreID, forKey: Key.dataStoreID)
            object.setValue(space.createdAt, forKey: Key.createdAt)
            spacesByID[space.id] = nil
        }

        for object in spacesByID.values {
            context.delete(object)
        }

        let existingTabs = try fetchObjects(entityName: Entity.tab, in: context)
        var tabsByID = Dictionary(
            uniqueKeysWithValues: existingTabs.compactMap { object -> (UUID, NSManagedObject)? in
                guard let id = object.uuid(for: Key.id) else { return nil }
                return (id, object)
            }
        )
        let spaceIDs = Set(state.spaces.map(\.id))

        for tab in state.tabs {
            guard spaceIDs.contains(tab.spaceID) else { continue }
            let object = tabsByID[tab.id]
                ?? NSEntityDescription.insertNewObject(forEntityName: Entity.tab, into: context)
            object.setValue(tab.id, forKey: Key.id)
            object.setValue(tab.title, forKey: Key.title)
            object.setValue(tab.url?.absoluteString, forKey: Key.urlString)
            object.setValue(tab.faviconSymbol, forKey: Key.faviconSymbol)
            object.setValue(tab.faviconData, forKey: Key.faviconData)
            object.setValue(tab.isPinned, forKey: Key.isPinned)
            object.setValue(tab.spaceID, forKey: Key.spaceID)
            object.setValue(tab.sortOrder, forKey: Key.sortOrder)
            object.setValue(tab.lastAccessedAt, forKey: Key.lastAccessedAt)
            tabsByID[tab.id] = nil
        }

        for object in tabsByID.values {
            context.delete(object)
        }
    }

    private func fetchSession(in context: NSManagedObjectContext) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.session)
        request.predicate = NSPredicate(format: "%K == %@", Key.id, "main")
        request.fetchLimit = 1

        if let session = try context.fetch(request).first {
            return session
        }

        return NSEntityDescription.insertNewObject(forEntityName: Entity.session, into: context)
    }

    private func fetchObjects(entityName: String, in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        return try context.fetch(request)
    }

    private func migrateLegacyCombinedStore(from legacyURL: URL) {
        let snapshot = Self.loadLegacyCombinedStore(from: legacyURL)

        if let state = snapshot.state {
            saveState(state)
        }

        guard !snapshot.historyVisits.isEmpty else { return }
        let context = container.newBackgroundContext()

        context.performAndWait {
            do {
                for visit in snapshot.historyVisits {
                    Self.insert(visit, in: context)
                }
                try context.save()
            } catch {
                context.rollback()
                NSLog("\(Self.appName) failed to migrate local history: \(error.localizedDescription)")
            }
        }
    }

    private static func loadLegacyCombinedStore(from legacyURL: URL) -> (
        state: BrowserWindowState?,
        historyVisits: [HistoryVisit]
    ) {
        let legacyContainer = NSPersistentContainer(
            name: "LumaLegacy",
            managedObjectModel: makeModel(configuresStoreConfigurations: false)
        )
        let description = NSPersistentStoreDescription(url: legacyURL)
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        legacyContainer.persistentStoreDescriptions = [description]

        var loadError: Error?
        legacyContainer.loadPersistentStores { _, error in
            loadError = error
        }

        if let loadError {
            NSLog("\(appName) failed to load legacy persistence store: \(loadError.localizedDescription)")
            return (nil, [])
        }

        let context = legacyContainer.viewContext
        let state = loadCoreDataState(in: context)
        let visits = loadHistoryVisits(in: context)
        return (state, visits)
    }

    private static func loadCoreDataState(in context: NSManagedObjectContext) -> BrowserWindowState? {
        context.performAndWait {
            do {
                let sessionRequest = NSFetchRequest<NSManagedObject>(entityName: Entity.session)
                sessionRequest.fetchLimit = 1

                guard let session = try context.fetch(sessionRequest).first else {
                    return nil
                }

                let spaceRequest = NSFetchRequest<NSManagedObject>(entityName: Entity.space)
                spaceRequest.sortDescriptors = [NSSortDescriptor(key: Key.createdAt, ascending: true)]

                let tabRequest = NSFetchRequest<NSManagedObject>(entityName: Entity.tab)
                tabRequest.sortDescriptors = [NSSortDescriptor(key: Key.sortOrder, ascending: true)]

                let spaces = try context.fetch(spaceRequest).compactMap(space(from:))
                let tabs = try context.fetch(tabRequest).compactMap(tab(from:))
                guard let activeSpaceID = session.uuid(for: Key.activeSpaceID) ?? spaces.first?.id else {
                    return nil
                }

                return BrowserWindowState(
                    spaces: spaces,
                    tabs: tabs,
                    activeSpaceID: activeSpaceID,
                    activeTabID: session.uuid(for: Key.activeTabID),
                    splitTabID: session.uuid(for: Key.splitTabID),
                    isSplitViewEnabled: session.bool(for: Key.isSplitViewEnabled)
                )
            } catch {
                NSLog("\(appName) failed to load session: \(error.localizedDescription)")
                return nil
            }
        }
    }

    private static func loadHistoryVisits(in context: NSManagedObjectContext) -> [HistoryVisit] {
        context.performAndWait {
            do {
                let request = NSFetchRequest<NSManagedObject>(entityName: Entity.historyVisit)
                request.sortDescriptors = [NSSortDescriptor(key: Key.visitedAt, ascending: true)]
                return try context.fetch(request).compactMap(historyVisit(from:))
            } catch {
                NSLog("\(appName) failed to load legacy history: \(error.localizedDescription)")
                return []
            }
        }
    }

    private static func insert(_ visit: HistoryVisit, in context: NSManagedObjectContext) {
        let object = NSEntityDescription.insertNewObject(forEntityName: Entity.historyVisit, into: context)
        object.setValue(visit.id, forKey: Key.id)
        object.setValue(visit.title, forKey: Key.title)
        object.setValue(visit.url.absoluteString, forKey: Key.urlString)
        object.setValue(visit.tabID, forKey: Key.tabID)
        object.setValue(visit.spaceID, forKey: Key.spaceID)
        object.setValue(visit.visitedAt, forKey: Key.visitedAt)
    }

    private static func space(from object: NSManagedObject) -> BrowserSpace? {
        guard let id = object.uuid(for: Key.id) else { return nil }

        return BrowserSpace(
            id: id,
            name: object.string(for: Key.name) ?? "Space",
            symbolName: object.string(for: Key.symbolName) ?? "sparkle",
            themeColorHex: object.string(for: Key.themeColorHex),
            themeAppearance: object.string(for: Key.themeAppearance)
                .flatMap(SpaceThemeAppearance.init(rawValue:)) ?? .automatic,
            themeOpacity: object.optionalDouble(for: Key.themeOpacity) ?? 0.5,
            themeTexture: object.optionalDouble(for: Key.themeTexture) ?? 0,
            dataStoreID: object.uuid(for: Key.dataStoreID) ?? id,
            createdAt: object.date(for: Key.createdAt) ?? Date()
        )
    }

    private static func tab(from object: NSManagedObject) -> BrowserTab? {
        guard
            let id = object.uuid(for: Key.id),
            let spaceID = object.uuid(for: Key.spaceID)
        else {
            return nil
        }

        let url = object.string(for: Key.urlString).flatMap(URL.init(string:))

        return BrowserTab(
            id: id,
            title: object.string(for: Key.title) ?? BrowserDefaults.newTabTitle,
            url: url,
            faviconSymbol: object.string(for: Key.faviconSymbol) ?? "globe",
            faviconData: object.data(for: Key.faviconData),
            isLoading: false,
            loadingProgress: 0,
            isPinned: object.bool(for: Key.isPinned),
            spaceID: spaceID,
            sortOrder: object.double(for: Key.sortOrder),
            lastAccessedAt: object.date(for: Key.lastAccessedAt) ?? Date()
        )
    }

    private static func historyVisit(from object: NSManagedObject) -> HistoryVisit? {
        guard
            let id = object.uuid(for: Key.id),
            let urlString = object.string(for: Key.urlString),
            let url = URL(string: urlString),
            let tabID = object.uuid(for: Key.tabID),
            let spaceID = object.uuid(for: Key.spaceID),
            let visitedAt = object.date(for: Key.visitedAt)
        else {
            return nil
        }

        return HistoryVisit(
            id: id,
            title: object.string(for: Key.title) ?? urlString,
            url: url,
            tabID: tabID,
            spaceID: spaceID,
            visitedAt: visitedAt
        )
    }

    private static func makeModel(configuresStoreConfigurations: Bool = true) -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let sessionEntities = [
            makeSessionEntity(),
            makeSpaceEntity(),
            makeTabEntity()
        ]
        let historyEntities = [makeHistoryVisitEntity()]

        model.entities = sessionEntities + historyEntities
        if configuresStoreConfigurations {
            model.setEntities(sessionEntities, forConfigurationName: StoreConfiguration.session)
            model.setEntities(historyEntities, forConfigurationName: StoreConfiguration.history)
        }
        return model
    }

    private static func makeSessionEntity() -> NSEntityDescription {
        makeEntity(
            named: Entity.session,
            properties: [
                attribute(Key.id, .stringAttributeType, optional: false),
                attribute(Key.activeSpaceID, .UUIDAttributeType, optional: false),
                attribute(Key.activeTabID, .UUIDAttributeType),
                attribute(Key.splitTabID, .UUIDAttributeType),
                attribute(Key.isSplitViewEnabled, .booleanAttributeType, optional: false)
            ]
        )
    }

    private static func makeSpaceEntity() -> NSEntityDescription {
        makeEntity(
            named: Entity.space,
            properties: [
                attribute(Key.id, .UUIDAttributeType, optional: false),
                attribute(Key.name, .stringAttributeType, optional: false),
                attribute(Key.symbolName, .stringAttributeType, optional: false),
                attribute(Key.themeColorHex, .stringAttributeType),
                attribute(Key.themeAppearance, .stringAttributeType),
                attribute(Key.themeOpacity, .doubleAttributeType),
                attribute(Key.themeTexture, .doubleAttributeType),
                attribute(Key.dataStoreID, .UUIDAttributeType),
                attribute(Key.createdAt, .dateAttributeType, optional: false)
            ]
        )
    }

    private static func makeTabEntity() -> NSEntityDescription {
        makeEntity(
            named: Entity.tab,
            properties: [
                attribute(Key.id, .UUIDAttributeType, optional: false),
                attribute(Key.title, .stringAttributeType, optional: false),
                attribute(Key.urlString, .stringAttributeType),
                attribute(Key.faviconSymbol, .stringAttributeType, optional: false),
                attribute(Key.faviconData, .binaryDataAttributeType),
                attribute(Key.isPinned, .booleanAttributeType, optional: false),
                attribute(Key.spaceID, .UUIDAttributeType, optional: false),
                attribute(Key.sortOrder, .doubleAttributeType, optional: false),
                attribute(Key.lastAccessedAt, .dateAttributeType, optional: false)
            ]
        )
    }

    private static func makeHistoryVisitEntity() -> NSEntityDescription {
        makeEntity(
            named: Entity.historyVisit,
            properties: [
                attribute(Key.id, .UUIDAttributeType, optional: false),
                attribute(Key.title, .stringAttributeType, optional: false),
                attribute(Key.urlString, .stringAttributeType, optional: false),
                attribute(Key.tabID, .UUIDAttributeType, optional: false),
                attribute(Key.spaceID, .UUIDAttributeType, optional: false),
                attribute(Key.visitedAt, .dateAttributeType, optional: false)
            ]
        )
    }

    private static func makeEntity(named name: String, properties: [NSPropertyDescription]) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = properties
        return entity
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = true
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        if !optional {
            attribute.defaultValue = defaultValue(for: type)
        }
        return attribute
    }

    private static func defaultValue(for type: NSAttributeType) -> Any? {
        switch type {
        case .stringAttributeType:
            return ""
        case .UUIDAttributeType:
            return UUID()
        case .dateAttributeType:
            return Date(timeIntervalSince1970: 0)
        case .booleanAttributeType:
            return false
        case .doubleAttributeType:
            return 0
        case .binaryDataAttributeType:
            return nil
        default:
            return nil
        }
    }
}

private enum StoreConfiguration {
    static let session = "SessionState"
    static let history = "History"
}

private enum Entity {
    static let session = "PersistedSessionState"
    static let space = "PersistedBrowserSpace"
    static let tab = "PersistedBrowserTab"
    static let historyVisit = "PersistedHistoryVisit"
}

private enum Key {
    static let id = "id"
    static let activeSpaceID = "activeSpaceID"
    static let activeTabID = "activeTabID"
    static let splitTabID = "splitTabID"
    static let isSplitViewEnabled = "isSplitViewEnabled"
    static let name = "name"
    static let symbolName = "symbolName"
    static let themeColorHex = "themeColorHex"
    static let themeAppearance = "themeAppearance"
    static let themeOpacity = "themeOpacity"
    static let themeTexture = "themeTexture"
    static let dataStoreID = "dataStoreID"
    static let createdAt = "createdAt"
    static let title = "title"
    static let urlString = "urlString"
    static let faviconSymbol = "faviconSymbol"
    static let faviconData = "faviconData"
    static let isPinned = "isPinned"
    static let tabID = "tabID"
    static let spaceID = "spaceID"
    static let sortOrder = "sortOrder"
    static let lastAccessedAt = "lastAccessedAt"
    static let visitedAt = "visitedAt"
}

private extension NSManagedObject {
    func bool(for key: String) -> Bool {
        value(forKey: key) as? Bool ?? false
    }

    func data(for key: String) -> Data? {
        value(forKey: key) as? Data
    }

    func date(for key: String) -> Date? {
        value(forKey: key) as? Date
    }

    func double(for key: String) -> Double {
        value(forKey: key) as? Double ?? 0
    }

    func optionalDouble(for key: String) -> Double? {
        value(forKey: key) as? Double
    }

    func string(for key: String) -> String? {
        value(forKey: key) as? String
    }

    func uuid(for key: String) -> UUID? {
        value(forKey: key) as? UUID
    }
}

private extension JSONEncoder {
    static var luma: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var luma: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
