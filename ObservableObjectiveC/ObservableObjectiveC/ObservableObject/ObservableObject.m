//
//  ObservableObject.m
//  ObservableObject
//
//  Created by Tung Nguyen on 2/2/18.
//  Copyright © 2018 Tung Nguyen. All rights reserved.
//

#import "ObservableObject.h"
#import "ObservableObject+Private.h"
#import <objc/runtime.h>

#define weakify(var) __weak typeof(var) weak_##var = var
#define strongify(var) \
_Pragma("clang diagnostic push") \
_Pragma("clang diagnostic ignored \"-Wshadow\"") \
__strong typeof(var) var = weak_##var \
_Pragma("clang diagnostic pop")

@interface NSUUID (Ext)

+(NSString *)createBaseTime;

@end

@implementation NSUUID (Ext)

static dispatch_queue_t UUIDQueue() {
    static dispatch_once_t onceToken;
    static dispatch_queue_t theQueue = nil;
    dispatch_once(&onceToken, ^{
        theQueue = dispatch_queue_create("com.observable.cleanbag", DISPATCH_QUEUE_SERIAL);
    });
    return theQueue;
}

+(NSString *)createBaseTime {
    __block NSString *uuid1;
    dispatch_sync(UUIDQueue(), ^{
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

@end

#pragma mark - ========== CleanBag ============

@implementation CleanBag

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.bagId = [NSUUID createBaseTime];
        self.subcriberQueue = dispatch_queue_create("com.obj.cleanbag.subs", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

-(NSHashTable *)subcribers {
    if (!_subcribers) {
        _subcribers = [[NSHashTable alloc] initWithOptions:NSPointerFunctionsWeakMemory capacity:20];
    }
    return _subcribers;
}

-(void)removeAllSubcribers {
    weakify(self);
    dispatch_sync(_subcriberQueue, ^{
        strongify(self);
        [self.subcribers removeAllObjects];
    });
}

-(void)registerSubcriberObject:(Subcriber *)sub {
    weakify(self);
    dispatch_sync(_subcriberQueue, ^{
        strongify(self);
        [self.subcribers addObject:sub];
    });
}

-(void)dealloc {
    NSLog(@"CleanBag === DEALLOC");
    for (Subcriber *sub in self.subcribers.allObjects) {
        sub.bag = nil;
    }
}

@end

#pragma mark - ========== Subcriber ============

@implementation Subcriber

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.subcriberId = [NSUUID createBaseTime];
        self.observeQueue = dispatch_queue_create("com.obj.subcriber.observe", DISPATCH_QUEUE_SERIAL);
    }
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
    self.bag = bag;
    [bag registerSubcriberObject:self];
    [self addObservingBag];
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

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    NSLog(@"Subcriber === observed keypath: %@ from object: %@", object, keyPath);
    if ([keyPath isEqualToString:NSStringFromSelector(@selector(bag))] && self.bag == nil) {
        [self removeObservingBag];
        [self.observableObj removeSubcriberWithId:self.subcriberId];
    }
}

@end

#pragma mark - ========== ObservableObject ============

@implementation ObservableObject

#pragma mark - Public funcs
- (instancetype)init {
    self = [super init];
    if (self) {
        self.objectID = [NSUUID createBaseTime];
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
    weakify(self);
    dispatch_sync(self.executionQueue, ^{
        strongify(self);
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

-(Subcriber *_Nonnull)subcribe:(SubcribeBlock _Nonnull)subBlock {
    __block Subcriber *subcriber;
    weakify(self);
    dispatch_sync(self.executionQueue, ^{
        strongify(self);
        subcriber = [self addSubcriberWithBlock:subBlock];
        [self.subcriberIds addObject:subcriber.subcriberId];
    });
    return subcriber;
}

-(Subcriber *_Nonnull)subcribeKeySelector:(SEL _Nonnull)propertySelector binding:(SubcribeBlock _Nonnull)subBlock {
    __block Subcriber *subcriber;
    weakify(self);
    dispatch_sync(self.executionQueue, ^{
        strongify(self);
        subcriber = [self addSubcriberWithBlock:subBlock];
        [self addSubcriber:subcriber forKeyPath:NSStringFromSelector(propertySelector)];
    });
    return subcriber;
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
    
    weakify(self);
    dispatch_sync(self.executionQueue, ^{
        strongify(self);
        dispatch_sync(self.subByIdsQueue, ^{
            strongify(self);
            NSMutableArray *propertySelectorSubcriberIds = self.selectorSubcribers[keyPath];
            if (propertySelectorSubcriberIds.count == 0) {return;}
            
            // fire keypath event
            dispatch_sync(self.selectorSubQueue, ^{
                strongify(self);
                for (NSString *subcriberId in propertySelectorSubcriberIds) {
                    SubcribeBlock block = self.subcriberById[subcriberId].subBlock;
                    block(keyPath, [self valueForKey:keyPath]);
                }
            });
            
            // fire main event
            dispatch_sync(self.subIdsQueue, ^{
                strongify(self);
                for (NSString *subcriberId in self.subcriberIds) {
                    SubcribeBlock block = self.subcriberById[subcriberId].subBlock;
                    block(keyPath, [self valueForKey:keyPath]);
                }
            });
        });
        
        [self didObserveKeypath:keyPath];
    });
}

-(Subcriber *)addSubcriberWithBlock:(SubcribeBlock)subBlock {
    [self addObservingProperties];
    
    Subcriber *subcriber = [[Subcriber alloc] init];
    subcriber.subBlock = subBlock;
    subcriber.observableObj = self;
    
    weakify(self);
    dispatch_sync(self.subByIdsQueue, ^{
        strongify(self);
        [self.subcriberById setObject:subcriber forKey:subcriber.subcriberId];
    });
    
    return subcriber;
}

-(void)addSubcriber:(Subcriber *)subcriber forKeyPath:(NSString *)keyPath {
    weakify(self);
    dispatch_sync(self.selectorSubQueue, ^{
        strongify(self);
        NSMutableArray *subs = self.selectorSubcribers[keyPath];
        if (!subs) {
            subs = [[NSMutableArray alloc] init];
        }
        [subs addObject:subcriber.subcriberId];
        [self.selectorSubcribers setObject:subs forKey:keyPath];
    });
}

-(void)removeSubcriberWithId:(NSString *)subcriberId {
    weakify(self);
    dispatch_sync(self.subIdsQueue, ^{
        strongify(self);
        [self.subcriberIds removeObject:subcriberId];
    });
    dispatch_sync(self.subByIdsQueue, ^{
        strongify(self);
        [self.subcriberById removeObjectForKey:subcriberId];
    });
    
    dispatch_sync(self.selectorSubQueue, ^{
        strongify(self);
        NSMutableArray *selectorSubcriberIds;
        for (NSString *keyPath in self.selectorSubcribers.allKeys) {
            selectorSubcriberIds = self.selectorSubcribers[keyPath];
            [selectorSubcriberIds removeObject:subcriberId];
        }
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
    if (![self.syncupObject respondsToSelector:NSSelectorFromString(keypath)]) {return;}
    if (![self respondsToSelector:NSSelectorFromString(keypath)]) {return;}
    id value = [self.syncupObject valueForKey:keypath];
    [self setValue:value forKey:keypath];
}

#pragma mark add/remove funcs
-(void)addObservingProperties {
    weakify(self);
    dispatch_sync(self.observerQueue, ^{
        strongify(self);
        if (self.obsAdded) {
            return;
        }
        self.obsAdded = YES;
        
        [self addObservingPropertiesForObject:self];
    });
}

-(void)addSyncupObservingProperties {
    weakify(self);
    dispatch_sync(self.observerQueue, ^{
        strongify(self);
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
    if (self.obsAdded) {
        [self removeObservingPropertiesForObject:self];
    }
    self.obsAdded = NO;
}

-(void)removeSyncupObservingProperties {
    [self removeObservingPropertiesForObject:self.syncupObject];
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
    [self.subcriberIds removeAllObjects];
    [self.selectorSubcribers removeAllObjects];
    [self.subcriberById removeAllObjects];
}

#pragma mark lazy loading
-(NSMutableArray<NSString *> *)subcriberIds {
    if (!_subcriberIds) {
        _subcriberIds = [[NSMutableArray alloc] init];
    }
    return _subcriberIds;
}

-(NSMutableDictionary<NSString *, Subcriber *> *)subcriberById {
    if (!_subcriberById) {
        _subcriberById = [[NSMutableDictionary alloc] init];
    }
    return _subcriberById;
}

-(NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *)selectorSubcribers {
    if (!_selectorSubcribers) {
        _selectorSubcribers = [[NSMutableDictionary alloc] init];
    }
    return _selectorSubcribers;
}

-(dispatch_queue_t)executionQueue {
    if (!_executionQueue) {
        _executionQueue = dispatch_queue_create("com.observable.excution", DISPATCH_QUEUE_SERIAL);
    }
    return _executionQueue;
}

-(dispatch_queue_t)observerQueue {
    if (!_observerQueue) {
        _observerQueue = dispatch_queue_create("com.observable.observer", DISPATCH_QUEUE_SERIAL);
    }
    return _observerQueue;
}

-(dispatch_queue_t)subByIdsQueue {
    if (!_subByIdsQueue) {
        _subByIdsQueue = dispatch_queue_create("com.observable.subbyids", DISPATCH_QUEUE_SERIAL);
    }
    return _subByIdsQueue;
}

-(dispatch_queue_t)selectorSubQueue {
    if (!_selectorSubQueue) {
        _selectorSubQueue = dispatch_queue_create("com.observable.selectorsub", DISPATCH_QUEUE_SERIAL);
    }
    return _selectorSubQueue;
}

-(dispatch_queue_t)subIdsQueue {
    if (!_subIdsQueue) {
        _subIdsQueue = dispatch_queue_create("com.observable.subids", DISPATCH_QUEUE_SERIAL);
    }
    return _subIdsQueue;
}

#pragma mark - Dealloc
- (void)dealloc {
    [self removeObservingProperties];
    [self removeSyncupObservingProperties];
    [self removeSubcribers];
}

@end
