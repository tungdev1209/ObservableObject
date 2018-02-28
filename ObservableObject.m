//
//  ObservableObject.m
//  ReactiveObject
//
//  Created by Tung Nguyen on 2/2/18.
//  Copyright © 2018 Tung Nguyen. All rights reserved.
//

#import "ObservableObject.h"
#import "ObservableObject+Private.h"
#import <objc/runtime.h>

@implementation CleanBag

static dispatch_queue_t getUUIDQueue() {
    static dispatch_once_t onceToken;
    static dispatch_queue_t theQueue = nil;
    dispatch_once(&onceToken, ^{
        theQueue = dispatch_queue_create("com.elearning.observable.cleanbag", DISPATCH_QUEUE_SERIAL);
    });
    return theQueue;
}

//http://stackoverflow.com/questions/9015784/how-to-create-uuid-type-1-in-objective-c-ios/9015962#9015962
+(NSString *)getUUIDType1 {
    __block NSString *uuid1;
    dispatch_sync(getUUIDQueue(), ^{
        // Get UUID type 1
        
        uuid_t dateUUID;
        uuid_generate_time(dateUUID);
        
        // Convert it to string
        
        uuid_string_t unparsedUUID;
        uuid_unparse_lower(dateUUID, unparsedUUID);
        uuid1 = [[NSString alloc] initWithUTF8String:unparsedUUID];
    });
    return uuid1;
}

+(instancetype)bag {
    return [[CleanBag alloc] init];
}

-(NSString *)bagId {
    if (!_bagId) {
        _bagId = [CleanBag getUUIDType1];
    }
    return _bagId;
}

-(NSHashTable *)observables {
    if (!_observables) {
        _observables = [[NSHashTable alloc] initWithOptions:NSPointerFunctionsWeakMemory capacity:20];
    }
    return _observables;
}

-(void)removeAllObservables {
    [self.observables removeAllObjects];
}

-(void)registerObservableObject:(ObservableObject *)object {
    [self.observables addObject:object];
}

-(void)dealloc {
    NSLog(@"CleanBag === DEALLOC");
    for (ObservableObject *object in self.observables.allObjects) {
        object.bag = nil;
    }
}

@end

@implementation ObservableObject

#pragma mark - Public funcs
- (instancetype)init {
    self = [super init];
    if (self) {
        self.objectID = [CleanBag getUUIDType1];
    }
    return self;
}

-(ObservableObject *)syncupWithObject:(ObservableObject *)object {
    if (![object isMemberOfClass:[self class]]) {
        NSLog(@"object not match");
        return self;
    }
    if ([self.syncupObject.objectID isEqualToString:object.objectID]) {
        NSLog(@"syncup with same object");
        return self;
    }
    dispatch_sync(self.excutionQueue, ^{
        if (self.syncupObject) {
            [self removeSyncupObservingProperties];
        }
        self.syncupObject = object;
        [self addSyncupObservingProperties];
    });
    return self;
}

-(ObservableObject *)removeSyncupObject {
    if (self.syncupObject) {
        [self removeSyncupObservingProperties];
        self.syncupObject = nil;
    }
    return self;
}

-(ObservableObject *_Nonnull)subcribe:(SubcribeBlock _Nonnull)subcriber {
    dispatch_sync(self.excutionQueue, ^{
        [self addObservingProperties];
        
        NSString *blockId = [CleanBag getUUIDType1];
        [self.subcriberById setObject:subcriber forKey:blockId];
        [self.observers addObject:blockId];
    });
    return self;
}

-(ObservableObject *_Nonnull)subcribeKeySelector:(SEL _Nonnull)propertySelector binding:(SubcribeBlock _Nonnull)subcriber {
    dispatch_sync(self.excutionQueue, ^{
        [self addObservingProperties];
        
        NSString *blockId = [CleanBag getUUIDType1];
        [self.subcriberById setObject:subcriber forKey:blockId];
        
        NSString *keyPath = NSStringFromSelector(propertySelector);
        NSMutableArray *subs = [self selectorSubcribingBlocks:keyPath];
        [subs addObject:blockId];
        [self.selectorObservers setObject:subs forKey:keyPath];
    });
    return self;
}

-(void)cleanupBy:(CleanBag *)bag {
    if ([bag.bagId isEqualToString:self.bag.bagId]) {
        NSLog(@"same bag");
        return;
    }
    if (self.bag) {
        [self removeObservingBag];
    }
    [self.bag removeAllObservables];
    self.bag = bag;
    [bag registerObservableObject:self];
    [self addObservingBag];
}

#pragma mark Subclass funs
-(void)didObserveKeypath:(NSString *)key {
    
}

#pragma mark - Private funcs
-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    NSLog(@"observed keypath: %@ from object: %@", object, keyPath);
    if ([object isKindOfClass:[ObservableObject class]] && [((ObservableObject *)object).objectID isEqualToString:self.syncupObject.objectID]) {
        NSLog(@"is syncup object");
        [self syncupValueForKeypath:keyPath];
        return;
    }
    
    if ([keyPath isEqualToString:NSStringFromSelector(@selector(bag))] && self.bag == nil) {
        [self cleanbagDealloc];
        [[NSNotificationCenter defaultCenter] postNotificationName:kCleanBagDealloc object:nil];
        return;
    }
    
    dispatch_sync(self.excutionQueue, ^{
        // fire keypath event
        NSMutableArray *propertySelectorSubcribers = self.selectorObservers[keyPath];
        for (NSString *blockId in propertySelectorSubcribers) {
            SubcribeBlock block = self.subcriberById[blockId];
            block([self valueForKey:keyPath]);
        }
        
        // fire main event
        for (NSString *subBlockId in self.observers) {
            SubcribeBlock block = self.subcriberById[subBlockId];
            block([self valueForKey:keyPath]);
        }
        
        [self didObserveKeypath:keyPath];
    });
}

-(void)syncupValues {
    unsigned int count;
    objc_property_t *props = class_copyPropertyList([self.syncupObject class], &count);
    
    NSString *keypath;
    for (int i = 0; i < count; ++i){
        keypath = [NSString stringWithUTF8String:property_getName(props[i])];
        [self syncupValueForKeypath:keypath];
    }
    
    free(props);
}

-(void)syncupValueForKeypath:(NSString *)keypath {
    id value = [self.syncupObject valueForKey:keypath];
    [self setValue:value forKey:keypath];
}

#pragma mark add/remove funcs
-(void)addObservingProperties {
    dispatch_sync(self.observerQueue, ^{
        if (_obsAdded) {
            return;
        }
        _obsAdded = YES;
        
        [self addObservingPropertiesForObject:self];
    });
}

-(void)addSyncupObservingProperties {
    dispatch_sync(self.observerQueue, ^{
        [self addObservingPropertiesForObject:self.syncupObject];
    });
}

-(void)addObservingPropertiesForObject:(NSObject *)object {
    unsigned int count;
    objc_property_t *props = class_copyPropertyList([object class], &count);
    
    NSString *keypath;
    for (int i = 0; i < count; ++i){
        keypath = [NSString stringWithUTF8String:property_getName(props[i])];
        [object addObserver:self forKeyPath:keypath options:(NSKeyValueObservingOptionNew /* | NSKeyValueObservingOptionInitial */) context:nil];
    }
    
    free(props);
}

-(void)removeObservingProperties {
    dispatch_sync(self.observerQueue, ^{
        if (_obsAdded) {
            [self removeObservingPropertiesForObject:self];
        }
        _obsAdded = NO;
    });
}

-(void)removeSyncupObservingProperties {
    dispatch_sync(self.observerQueue, ^{
        [self removeObservingPropertiesForObject:self.syncupObject];
    });
}

-(void)removeObservingPropertiesForObject:(NSObject *)object {
    unsigned int count;
    objc_property_t *props = class_copyPropertyList([object class], &count);
    
    NSString *keypath;
    for (int i = 0; i < count; ++i){
        keypath = [NSString stringWithUTF8String:property_getName(props[i])];
        @try {
            [object removeObserver:self forKeyPath:keypath];
        } @catch (NSException *exception) {
            NSLog(@"remove observe error: %@", exception);
        }
    }
    
    free(props);
}

-(void)removeSubcribers {
    dispatch_sync(self.excutionQueue, ^{
        [self.observers removeAllObjects];
        for (NSString *key in self.selectorObservers.allKeys) {
            [self.selectorObservers[key] removeAllObjects];
        }
        [self.selectorObservers removeAllObjects];
        [self.subcriberById removeAllObjects];
    });
}

-(void)addObservingBag {
    [self addObserver:self forKeyPath:NSStringFromSelector(@selector(bag)) options:NSKeyValueObservingOptionNew context:nil];
}

-(void)removeObservingBag {
    @try {
        [self removeObserver:self forKeyPath:NSStringFromSelector(@selector(bag)) context:nil];
    } @catch (NSException *exception) {
        NSLog(@"remove error: %@", exception);
    }
}

#pragma mark lazy loading
-(NSMutableArray *)observers {
    if (!_observers) {
        _observers = [[NSMutableArray alloc] init];
    }
    return _observers;
}

-(NSMutableDictionary<NSString *,NSMutableArray<NSString *> *> *)selectorObservers {
    if (!_selectorObservers) {
        _selectorObservers = [[NSMutableDictionary alloc] init];
    }
    return _selectorObservers;
}

-(NSMutableDictionary<NSString *,SubcribeBlock> *)subcriberById {
    if (!_subcriberById) {
        _subcriberById = [[NSMutableDictionary alloc] init];
    }
    return _subcriberById;
}

-(NSMutableArray *)selectorSubcribingBlocks:(NSString *)keyPath {
    NSMutableArray *subs = self.selectorObservers[keyPath];
    if (!subs) {
        subs = [[NSMutableArray alloc] init];
    }
    return subs;
}

-(dispatch_queue_t)excutionQueue {
    if (!_excutionQueue) {
        _excutionQueue = dispatch_queue_create("com.elearning.observable.excution", DISPATCH_QUEUE_SERIAL);
    }
    return _excutionQueue;
}

-(dispatch_queue_t)observerQueue {
    if (!_observerQueue) {
        _observerQueue = dispatch_queue_create("com.elearning.observable.observer", DISPATCH_QUEUE_SERIAL);
    }
    return _observerQueue;
}

#pragma mark - Dealloc
-(void)cleanbagDealloc {
    [self removeObservingProperties];
    [self removeSyncupObservingProperties];
    [self removeSubcribers];
}

- (void)dealloc {
    [self cleanbagDealloc];
}

@end
