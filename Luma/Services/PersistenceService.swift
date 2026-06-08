import CoreData
import Foundation

struct PersistenceService {
    static let shared = PersistenceService()

    private let container: NSPersistentContainer

    init() {
        let model = Self.makeModel()
        let container = NSPersistentContainer(name: "Luma", managedObjectModel: model)
        let folderURL = Self.applicationSupportURL
        let storeURL = folderURL.appendingPathComponent("Luma.sqlite")
        let storeDescription = NSPersistentStoreDescription(url: storeURL)
        storeDescription.shouldMigrateStoreAutomatically = true
        storeDescription.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [storeDescription]

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            NSLog("Luma Browser failed to create persistence folder: \(error.localizedDescription)")
        }

        container.loadPersistentStores { _, error in
            if let error {
                NSLog("Luma Browser failed to load Core Data store: \(error.localizedDescription)")
            }
        }

        self.container = container
    }

    private static var applicationSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Luma Browser", isDirectory: true)
    }

    private static var legacyStateURL: URL {
        applicationSupportURL.appendingPathComponent("session.json")
    }

    func loadState() -> BrowserWindowState? {
        if let state = loadCoreDataState() {
            return state
        }

        guard let legacyState = loadLegacyJSONState() else {
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
                try deleteExistingState(in: context)
                insert(state, in: context)
                try context.save()
            } catch {
                context.rollback()
                NSLog("Luma Browser failed to save session: \(error.localizedDescription)")
            }
        }
    }

    func recordVisit(title: String, url: URL, tabID: UUID, spaceID: UUID, visitedAt: Date = Date()) {
        let context = container.newBackgroundContext()

        context.perform {
            let object = NSEntityDescription.insertNewObject(forEntityName: Entity.historyVisit, into: context)
            object.setValue(UUID(), forKey: Key.id)
            object.setValue(title, forKey: Key.title)
            object.setValue(url.absoluteString, forKey: Key.urlString)
            object.setValue(tabID, forKey: Key.tabID)
            object.setValue(spaceID, forKey: Key.spaceID)
            object.setValue(visitedAt, forKey: Key.visitedAt)

            do {
                try context.save()
            } catch {
                context.rollback()
                NSLog("Luma Browser failed to record history visit: \(error.localizedDescription)")
            }
        }
    }

    private func loadCoreDataState() -> BrowserWindowState? {
        let context = container.viewContext
        return context.performAndWait {
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

                let spaces = try context.fetch(spaceRequest).compactMap(Self.space(from:))
                let tabs = try context.fetch(tabRequest).compactMap(Self.tab(from:))
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
                NSLog("Luma Browser failed to load session: \(error.localizedDescription)")
                return nil
            }
        }
    }

    private func loadLegacyJSONState() -> BrowserWindowState? {
        do {
            let data = try Data(contentsOf: Self.legacyStateURL)
            return try JSONDecoder.luma.decode(BrowserWindowState.self, from: data)
        } catch {
            return nil
        }
    }

    private func deleteExistingState(in context: NSManagedObjectContext) throws {
        for entityName in [Entity.session, Entity.space, Entity.tab] {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            deleteRequest.resultType = .resultTypeObjectIDs

            if let result = try context.execute(deleteRequest) as? NSBatchDeleteResult,
               let objectIDs = result.result as? [NSManagedObjectID] {
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                    into: [context]
                )
            }
        }
    }

    private func insert(_ state: BrowserWindowState, in context: NSManagedObjectContext) {
        let session = NSEntityDescription.insertNewObject(forEntityName: Entity.session, into: context)
        session.setValue("main", forKey: Key.id)
        session.setValue(state.activeSpaceID, forKey: Key.activeSpaceID)
        session.setValue(state.activeTabID, forKey: Key.activeTabID)
        session.setValue(state.splitTabID, forKey: Key.splitTabID)
        session.setValue(state.isSplitViewEnabled, forKey: Key.isSplitViewEnabled)

        for space in state.spaces {
            let object = NSEntityDescription.insertNewObject(forEntityName: Entity.space, into: context)
            object.setValue(space.id, forKey: Key.id)
            object.setValue(space.name, forKey: Key.name)
            object.setValue(space.symbolName, forKey: Key.symbolName)
            object.setValue(space.themeColorHex, forKey: Key.themeColorHex)
            object.setValue(space.dataStoreID, forKey: Key.dataStoreID)
            object.setValue(space.createdAt, forKey: Key.createdAt)
        }

        for tab in state.tabs {
            let object = NSEntityDescription.insertNewObject(forEntityName: Entity.tab, into: context)
            object.setValue(tab.id, forKey: Key.id)
            object.setValue(tab.title, forKey: Key.title)
            object.setValue(tab.url?.absoluteString, forKey: Key.urlString)
            object.setValue(tab.faviconSymbol, forKey: Key.faviconSymbol)
            object.setValue(tab.faviconData, forKey: Key.faviconData)
            object.setValue(tab.isPinned, forKey: Key.isPinned)
            object.setValue(tab.spaceID, forKey: Key.spaceID)
            object.setValue(tab.sortOrder, forKey: Key.sortOrder)
            object.setValue(tab.lastAccessedAt, forKey: Key.lastAccessedAt)
        }
    }

    private static func space(from object: NSManagedObject) -> BrowserSpace? {
        guard let id = object.uuid(for: Key.id) else { return nil }

        return BrowserSpace(
            id: id,
            name: object.string(for: Key.name) ?? "Space",
            symbolName: object.string(for: Key.symbolName) ?? "sparkle",
            themeColorHex: object.string(for: Key.themeColorHex) ?? "#6E8BFF",
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
            title: object.string(for: Key.title) ?? "New Tab",
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

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.entities = [
            makeSessionEntity(),
            makeSpaceEntity(),
            makeTabEntity(),
            makeHistoryVisitEntity()
        ]
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
                attribute(Key.themeColorHex, .stringAttributeType, optional: false),
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
        return attribute
    }
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
