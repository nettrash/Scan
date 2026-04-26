//
//  Persistence.swift
//  Scan
//
//  Created by nettrash on 16/09/2023.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        let samples: [(value: String, symbology: String)] = [
            ("https://nettrash.me", "QR"),
            ("WIFI:T:WPA;S:HomeNet;P:supersecret;;", "QR"),
            ("MECARD:N:Doe,Jane;TEL:+15551234567;EMAIL:jane@example.com;;", "QR"),
            ("4006381333931", "EAN-13"),
            ("geo:37.3349,-122.0090?q=Apple+Park", "QR")
        ]
        for (idx, sample) in samples.enumerated() {
            let record = ScanRecord(context: viewContext)
            record.id = UUID()
            record.value = sample.value
            record.symbology = sample.symbology
            record.timestamp = Date(timeIntervalSinceNow: TimeInterval(-idx * 60))
        }
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentCloudKitContainer

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Scan")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
