import Foundation
import ObjectiveC
import BatteryGuardShared

/// Apples natives Ladelimit („Manual Charge Limit“) über die private Klasse
/// `PowerUISmartChargeClient` aus PowerUI.framework (ab macOS 26/27).
/// Die Schnittstelle ist undokumentiert: Jeder Aufruf prüft Klasse und Selektor zur Laufzeit,
/// gesetzt werden nur Werte, die macOS selbst als verfügbar meldet.
final class SystemChargeLimitClient {
    // `NSError **` ist autoreleasing; ein UnsafeMutablePointer würde das Fehlerobjekt doppelt freigeben.
    private typealias InitFn = @convention(c) (AnyObject, Selector, NSString) -> AnyObject?
    private typealias ListFn = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> NSArray?
    private typealias GetFn = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> UInt8
    private typealias SetFn = @convention(c) (AnyObject, Selector, UInt8, AutoreleasingUnsafeMutablePointer<NSError?>?) -> Bool

    private let client: AnyObject

    init?() {
        guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW) != nil,
              let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type else { return nil }
        let initSel = NSSelectorFromString("initWithClientName:")
        guard let allocated = Self.allocate(cls),
              let fn: InitFn = Self.implementation(of: allocated, initSel),
              let instance = fn(allocated, initSel, "B-Guard" as NSString) else { return nil }
        client = instance
    }

    private static func allocate(_ cls: NSObject.Type) -> AnyObject? {
        let sel = NSSelectorFromString("alloc")
        guard let method = class_getClassMethod(cls, sel) else { return nil }
        typealias AllocFn = @convention(c) (AnyClass, Selector) -> AnyObject?
        return unsafeBitCast(method_getImplementation(method), to: AllocFn.self)(cls, sel)
    }

    private static func implementation<T>(of object: AnyObject, _ selector: Selector) -> T? {
        guard let cls = object_getClass(object), let method = class_getInstanceMethod(cls, selector) else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: T.self)
    }

    /// Von macOS angebotene Stufen, z. B. [80, 85, 90, 95, 100].
    func availableLimits() -> [Int]? {
        let sel = NSSelectorFromString("availableChargeLimitsWithError:")
        guard let fn: ListFn = Self.implementation(of: client, sel) else { return nil }
        var error: NSError?
        guard let list = fn(client, sel, &error), error == nil else { return nil }
        let limits = list.compactMap { ($0 as? NSNumber)?.intValue }.filter { (1...100).contains($0) }
        return limits.isEmpty ? nil : limits.sorted()
    }

    func currentLimit() -> Int? {
        let sel = NSSelectorFromString("getMCLLimitWithError:")
        guard let fn: GetFn = Self.implementation(of: client, sel) else { return nil }
        var error: NSError?
        let value = Int(fn(client, sel, &error))
        return error == nil && (1...100).contains(value) ? value : nil
    }

    func setLimit(_ limit: Int) -> Bool {
        let sel = NSSelectorFromString("setMCLLimit:error:")
        guard (1...100).contains(limit), let fn: SetFn = Self.implementation(of: client, sel) else { return false }
        var error: NSError?
        return fn(client, sel, UInt8(limit), &error) && error == nil
    }
}

/// Setzt das native Limit nur bei Abweichung und prüft es danach zurück.
final class SystemChargeLimitController {
    struct Driver {
        var availableLimits: () -> [Int]?
        var currentLimit: () -> Int?
        var setLimit: (Int) -> Bool

        static var system: Driver {
            let client = SystemChargeLimitClient()
            return Driver(availableLimits: { client?.availableLimits() },
                          currentLimit: { client?.currentLimit() },
                          setLimit: { client?.setLimit($0) ?? false })
        }
    }

    private let driver: Driver
    private var cachedLimits: [Int]?
    private var lastLimitsRead: TimeInterval?
    /// Merkt sich Apples Limit vor B-Guards erstem Eingriff, um es beim Verlassen des Modus wiederherzustellen.
    private let ownershipPath: String

    static let defaultOwnershipPath = BGPaths.directory + "/system-limit-original.json"

    init(driver: Driver = .system, ownershipPath: String = SystemChargeLimitController.defaultOwnershipPath) {
        self.driver = driver
        self.ownershipPath = ownershipPath
    }

    private var originalLimit: Int? {
        (FileManager.default.contents(atPath: ownershipPath)).flatMap { try? JSONDecoder().decode(Int.self, from: $0) }
    }

    /// Stellt Apples ursprüngliches Limit wieder her, falls B-Guard es geändert hat. Gibt true zurück, wenn nichts mehr offen ist.
    @discardableResult
    func restoreOriginal(dryRun: Bool, logger: ((String) -> Void)?) -> Bool {
        guard let original = originalLimit else { return true }
        if dryRun { logger?("[DRY-RUN] macOS-Limit würde auf \(original) % zurückgesetzt"); return true }
        let restored = driver.currentLimit() == original || (driver.setLimit(original) && driver.currentLimit() == original)
        if restored { try? FileManager.default.removeItem(atPath: ownershipPath) }
        logger?("macOS-Limit auf ursprüngliche \(original) % \(restored ? "zurückgesetzt" : "nicht zurückgesetzt")")
        return restored
    }

    /// Verfügbare Stufen, höchstens alle zehn Minuten neu gelesen.
    func availableLimits(uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [Int] {
        if cachedLimits == nil || (lastLimitsRead.map { uptime - $0 >= 600 } ?? true) {
            cachedLimits = driver.availableLimits()
            lastLimitsRead = uptime
        }
        return cachedLimits ?? []
    }

    func currentLimit() -> Int? { driver.currentLimit() }

    /// Returns false when macOS rejected or did not confirm the requested limit.
    func apply(_ limit: Int, dryRun: Bool, logger: ((String) -> Void)?) -> Bool {
        guard availableLimits().contains(limit) else {
            logger?("macOS-Limit \(limit) % wird von macOS nicht angeboten.")
            return false
        }
        if driver.currentLimit() == limit { return true }
        if !dryRun, originalLimit == nil, let current = driver.currentLimit(),
           let data = try? JSONEncoder().encode(current) {
            FileManager.default.createFile(atPath: ownershipPath, contents: data)
        }
        if dryRun {
            logger?("[DRY-RUN] macOS-Limit würde auf \(limit) % gesetzt")
            return true
        }
        let success = driver.setLimit(limit) && driver.currentLimit() == limit
        logger?("macOS-Limit: setMCLLimit(\(limit)) => \(success ? "ok" : "failed")")
        return success
    }
}
