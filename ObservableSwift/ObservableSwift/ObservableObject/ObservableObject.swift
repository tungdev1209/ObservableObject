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
    fileprivate let badId = NSUUID.createBaseTime()
    fileprivate let subcribers = NSHashTable<AnyObject>(options: NSPointerFunctions.Options.weakMemory)
    fileprivate func registerSubcriberObject(_ subcriber: Subcriber) {
        subcribers.add(subcriber)
    }
    
    fileprivate func removeAllSubcribers() {
        subcribers.removeAllObjects()
    }
    
    deinit {
        for sub in subcribers.allObjects as! [Subcriber] {
            sub.bag = nil
        }
    }
}

class Subcriber: NSObject {
    var subBlock: SubcribeBlock?
    
    fileprivate let subcriberId = NSUUID.createBaseTime()
    @objc fileprivate weak var bag: CleanBag?
    fileprivate weak var observableObj: ObservableObject?
    
    func cleanupBy(_ b: CleanBag) {
        guard b.badId != bag?.badId else {return}
        if let _ = bag {
            removeObservingBag()
        }
        bag = b
        b.registerSubcriberObject(self)
        
    }
    
    func removeObservingBag() {
        removeObserver(self, forKeyPath: #keyPath(Subcriber.bag), context: nil)
    }
    
    func addObservingBag() {
        addObserver(self, forKeyPath: #keyPath(Subcriber.bag), options: NSKeyValueObservingOptions.new, context: nil)
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
    fileprivate var obsAdded = false
    fileprivate let objectID = NSUUID.createBaseTime()
    
    func subcribe(_ block: SubcribeBlock?) -> Subcriber {
        var subcriber: Subcriber!
        executionQueue.sync { [weak self] in
            guard let `self` = self else {return}
            subcriber = self.addSubcriberWithBlock(block)
            subcriberIds.append(subcriber.subcriberId)
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
        executionQueue.sync { [weak self] in
            guard let `self` = self else {return}
            guard let propertySelectorSubcriberIds = selectorSubcribers[kPath] else {return}
            for subcriberId in propertySelectorSubcriberIds {
                if let sub = self.subcriberById[subcriberId] {
                    sub.subBlock?(kPath, value(forKey: kPath))
                }
            }
            
            for subcriberId in subcriberIds {
                if let sub = self.subcriberById[subcriberId] {
                    sub.subBlock?(kPath, value(forKey: kPath))
                }
            }
        }
    }
    
    func addSubcriberWithBlock(_ subBlock: SubcribeBlock?) -> Subcriber {
        addObservingProperties()
        
        let subcriber = Subcriber()
        subcriber.subBlock = subBlock
        subcriber.observableObj = self
        
        subcriberById[subcriber.subcriberId] = subcriber
        return subcriber
    }
    
    func addSubcriber(_ subcriber: Subcriber, keyPath: String) {
        var subs = selectorSubcribers[keyPath]
        if subs == nil {
            subs = [String]()
        }
        subs!.append(subcriber.subcriberId)
        selectorSubcribers[keyPath] = subs
    }
    
    func removeSubcriberWithId(_ subcriberId: String) {
        subcriberIds = subcriberIds.filter({ $0 != subcriberId })
        subcriberById.removeValue(forKey: subcriberId)
        for keyPath in selectorSubcribers.keys {
            var selectorSubcriberIds = selectorSubcribers[keyPath]
            selectorSubcriberIds = selectorSubcriberIds?.filter({ $0 != subcriberId })
            selectorSubcribers[keyPath] = selectorSubcriberIds
        }
    }
    
    func addObservingProperties() {
        observationQueue.sync { [weak self] in
            guard let `self` = self else {return}
            self.addObservingPropertiesForObject(self)
        }
    }
    
    func removeObservingProperties() {
        observationQueue.sync { [weak self] in
            guard let `self` = self else {return}
            self.removeObservingPropertiesForObject(self)
        }
    }
    
    func addObservingPropertiesForObject(_ object: NSObject) {
        
    }
    
    func removeObservingPropertiesForObject(_ object: NSObject) {
        
    }
    
    func removeObservingPropertiesForObject() {
        
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
        removeSubcribers()
    }
}

let UUIDQueue = DispatchQueue.init(label: "com.nsuuid.basetime")
extension NSUUID {
    static func createBaseTime() -> String {
        var uuidString: String = ""
        UUIDQueue.sync {
            let uuidSize = MemoryLayout.size(ofValue: uuid_t.self)
            let uuidPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: uuidSize)
            uuid_generate_time(uuidPointer)
            let uuid = NSUUID(uuidBytes: uuidPointer)
            uuidPointer.deallocate()
            uuidString = uuid.uuidString
        }
        return uuidString
    }
}
