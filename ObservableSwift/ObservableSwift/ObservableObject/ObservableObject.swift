//
//  ObservableObject.swift
//  ObservableSwift
//
//  Created by Tung Nguyen on 11/8/18.
//  Copyright © 2018 Tung Nguyen. All rights reserved.
//

import UIKit

typealias SubcribeBlock = ((String, Any?) -> Void)

let kCleanBagDealloc = "CleanBag_Dealloc"
let kCleanBagObjectId = "CleanBag_ObjectId"

class CleanBag: NSObject {
    fileprivate let bagId = NSUUID.createBaseTime()
    fileprivate let subcribers = NSHashTable<AnyObject>(options: NSPointerFunctions.Options.weakMemory)
    fileprivate let subcriberQueue = DispatchQueue.init(label: "com.obj.cleanbag.subs")
    
    fileprivate func registerSubcriberObject(_ subcriber: Subcriber) {
        subcriberQueue.sync { [weak self] in
            guard let `self` = self else {return}
            self.subcribers.add(subcriber)
        }
    }
    
    fileprivate func removeAllSubcribers() {
        subcriberQueue.sync { [weak self] in
            guard let `self` = self else {return}
            self.subcribers.removeAllObjects()
        }
    }
    
    deinit {
        subcriberQueue.sync { [weak self] in
            guard let `self` = self else {return}
            for sub in self.subcribers.allObjects as! [Subcriber] {
                sub.bag = nil
            }
        }
    }
}

class Subcriber: NSObject {
    var subBlock: SubcribeBlock?
    
    fileprivate let subcriberId = NSUUID.createBaseTime()
    @objc fileprivate weak var bag: CleanBag?
    fileprivate weak var observableObj: ObservableObject?
    fileprivate let observeQueue = DispatchQueue.init(label: "com.obj.subcriber.observe")
    
    func cleanupBy(_ b: CleanBag) {
        guard b.bagId != bag?.bagId else {return}
        if let _ = bag {
            removeObservingBag()
        }
        bag = b
        b.registerSubcriberObject(self)
        addObservingBag()
    }
    
    func addObservingBag() {
        observeQueue.sync { [weak self] in
            guard let `self` = self else {return}
            addObserver(self, forKeyPath: #keyPath(Subcriber.bag), options: NSKeyValueObservingOptions.new, context: nil)
        }
    }
    
    func removeObservingBag() {
        observeQueue.sync { [weak self] in
            guard let `self` = self else {return}
            removeObserver(self, forKeyPath: #keyPath(Subcriber.bag), context: nil)
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(Subcriber.bag), let _ = bag {
            removeObservingBag()
            observableObj?.removeSubcriberWithId(subcriberId)
        }
    }
}

class ObservableObject: NSObject {
    fileprivate var subcriberIds = [String]()
    fileprivate var selectorSubcribers = [String: [String]]()
    fileprivate var subcriberById = [String: Subcriber]()
    fileprivate let observationQueue = DispatchQueue(label: "com.observable.observation")
    fileprivate let executionQueue = DispatchQueue(label: "com.observable.execution")
    fileprivate let selectorSubQueue = DispatchQueue(label: "com.observable.selectorsubcriber")
    fileprivate let subIdsQueue = DispatchQueue(label: "com.observable.subcriberid")
    fileprivate let subByIdsQueue = DispatchQueue(label: "com.observable.subcriberbyid")
    fileprivate var obsAdded = false
    fileprivate let objectID = NSUUID.createBaseTime()
    
    fileprivate var syncupObject: ObservableObject?
    
    func syncupWithObject(_ object: ObservableObject) -> ObservableObject {
        guard syncupObject?.objectID != objectID else {return self}
        executionQueue.sync { [weak self] in
            guard let `self` = self else {return}
            if let _ = self.syncupObject {
                self.removeSyncupObservingProperties()
            }
            self.syncupObject = object
            self.addSyncupObservingProperties()
        }
        return self
    }
    
    func removeSyncupObject() -> ObservableObject {
        if let _ = syncupObject {
            removeSyncupObservingProperties()
            syncupObject = nil
        }
        return self
    }
    
    func subcribe(_ block: SubcribeBlock?) -> Subcriber {
        var subcriber: Subcriber!
        executionQueue.sync { [weak self] in
            guard let `self` = self else {return}
            subcriber = self.addSubcriberWithBlock(block)
            self.subcriberIds.append(subcriber.subcriberId)
        }
        return subcriber
    }
    
    func subcribeKeySelector(_ keyPath: String, binding: SubcribeBlock?) -> Subcriber {
        var subcriber: Subcriber!
        executionQueue.sync { [weak self] in
            guard let `self` = self else {return}
            subcriber = self.addSubcriberWithBlock(binding)
            self.addSubcriber(subcriber, keyPath: keyPath)
        }
        return subcriber
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let kPath = keyPath else {return}
        
        if let obj = object as? ObservableObject, obj.objectID == syncupObject?.objectID {
            syncupValueForKeyPath(kPath)
            return
        }
        
        executionQueue.sync { [weak self] in
            guard let `self` = self else {return}
            self.subByIdsQueue.sync { [weak self] in
                guard let `self` = self else {return}
                guard let propertySelectorSubcriberIds = self.selectorSubcribers[kPath] else {return}
                
                self.selectorSubQueue.sync { [weak self] in
                    guard let `self` = self else {return}
                    for subcriberId in propertySelectorSubcriberIds {
                        if let sub = self.subcriberById[subcriberId] {
                            sub.subBlock?(kPath, value(forKey: kPath))
                        }
                    }
                }
                self.subIdsQueue.sync { [weak self] in
                    guard let `self` = self else {return}
                    for subcriberId in self.subcriberIds {
                        if let sub = self.subcriberById[subcriberId] {
                            sub.subBlock?(kPath, value(forKey: kPath))
                        }
                    }
                }
            }
        }
    }
    
    func addSubcriberWithBlock(_ subBlock: SubcribeBlock?) -> Subcriber {
        addObservingProperties()
        
        let subcriber = Subcriber()
        subcriber.subBlock = subBlock
        subcriber.observableObj = self
        
        subByIdsQueue.sync { [weak self] in
            guard let `self` = self else {return}
            self.subcriberById[subcriber.subcriberId] = subcriber
        }
        
        return subcriber
    }
    
    func addSubcriber(_ subcriber: Subcriber, keyPath: String) {
        selectorSubQueue.sync { [weak self] in
            guard let `self` = self else {return}
            var subs = self.selectorSubcribers[keyPath] ?? []
            subs.append(subcriber.subcriberId)
            self.selectorSubcribers[keyPath] = subs
        }
    }
    
    func removeSubcriberWithId(_ subcriberId: String) {
        subIdsQueue.sync { [weak self] in
            guard let `self` = self else {return}
            self.subcriberIds = subcriberIds.filter({ $0 != subcriberId })
        }
        subByIdsQueue.sync { [weak self] in
            guard let `self` = self else {return}
            self.subcriberById.removeValue(forKey: subcriberId)
        }
        selectorSubQueue.sync { [weak self] in
            guard let `self` = self else {return}
            for keyPath in self.selectorSubcribers.keys {
                var selectorSubcriberIds = self.selectorSubcribers[keyPath]
                selectorSubcriberIds = selectorSubcriberIds?.filter({ $0 != subcriberId })
                self.selectorSubcribers[keyPath] = selectorSubcriberIds
            }
        }
    }
    
    func syncupValues() {
        guard let syncupObj = syncupObject else {return}
        for case let (label, _) in Mirror.init(reflecting: syncupObj).children {
            guard let keyPath = label else {continue}
            syncupValueForKeyPath(keyPath)
        }
    }
    
    func syncupValueForKeyPath(_ keyPath: String) {
        let value = syncupObject?.value(forKey: keyPath)
        setValue(value, forKey: keyPath)
    }
    
    // MARK: add/remove funcs
    func addObservingProperties() {
        observationQueue.sync { [weak self] in
            guard let `self` = self else {return}
            guard !self.obsAdded else {return}
            self.obsAdded = true
            self.addObservingPropertiesForObject(self)
        }
    }
    
    func addSyncupObservingProperties() {
        observationQueue.sync { [weak self] in
            guard let `self` = self, let obj = self.syncupObject else {return}
            self.addObservingPropertiesForObject(obj)
        }
    }
    
    func addObservingPropertiesForObject(_ object: NSObject) {
        for case let (label, _) in Mirror.init(reflecting: object).children {
            guard let keyPath = label else {continue}
            object.addObserver(self, forKeyPath: keyPath, options: NSKeyValueObservingOptions.new, context: nil)
        }
    }
    
    func removeObservingProperties() {
        observationQueue.sync { [weak self] in
            guard let `self` = self else {return}
            guard self.obsAdded else {return}
            self.obsAdded = false
            self.removeObservingPropertiesForObject(self)
        }
    }
    
    func removeSyncupObservingProperties() {
        observationQueue.sync { [weak self] in
            guard let `self` = self, let obj = self.syncupObject else {return}
            self.removeObservingPropertiesForObject(obj)
        }
    }
    
    func removeObservingPropertiesForObject(_ object: NSObject) {
        for case let (label, _) in Mirror.init(reflecting: object).children {
            guard let keyPath = label else {continue}
            object.removeObserver(self, forKeyPath: keyPath)
        }
    }
    
    func removeSubcribers() {
        executionQueue.sync { [weak self] in
            guard let `self` = self else {return}
            self.subcriberIds.removeAll()
            self.selectorSubcribers.removeAll()
            self.subcriberById.removeAll()
        }
    }
    
    deinit {
        removeObservingProperties()
        removeSyncupObservingProperties()
        removeSubcribers()
    }
}

let UUIDQueue = DispatchQueue.init(label: "com.nsuuid.basetime")
extension NSUUID {
    static func createBaseTime() -> String {
        var uuidString: String = ""
        let uuidSize = MemoryLayout.size(ofValue: uuid_t.self)
        UUIDQueue.sync {
            let uuidPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: uuidSize)
            uuid_generate_time(uuidPointer)
            let uuid = NSUUID(uuidBytes: uuidPointer)
            uuidPointer.deallocate()
            uuidString = uuid.uuidString
        }
        return uuidString
    }
}
