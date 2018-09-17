//
//  ObservableObject.m
//  CoredataVIPER
//
//  Created by Tung Nguyen on 2/2/18.
//  Copyright © 2018 Tung Nguyen. All rights reserved.
//

#import "ObservableObject.h"
#import "ObservableObject+Private.h"
#import <objc/runtime.h>

#pragma mark - ========== CleanBag ============

@implementation CleanBag

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.bagId = [CleanBag getRunTimeId];
    }
    return self;
}

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

+(NSString *)getRunTimeId {
    return [CleanBag getUUIDType1];
}

-(NSHashTable *)subcribers {
    if (!_subcribers) {
        _subcribers = [[NSHashTable alloc] initWithOptions:NSPointerFunctionsWeakMemory capacity:20];
    }
    return _subcribers;
}

-(void)removeAllSubcribers {
    [self.subcribers removeAllObjects];
}

-(void)registerSubcriberObject:(Subcriber *)sub {
    [self.subcribers addObject:sub];
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
        self.subcriberId = [CleanBag getRunTimeId];
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
        self.objectID = [CleanBag getRunTimeId];
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

-(Subcriber *_Nonnull)subcribe:(SubcribeBlock _Nonnull)subBlock {
    __block Subcriber *subcriber;
    dispatch_sync(self.excutionQueue, ^{
        subcriber = [self addSubcriberWithBlock:subBlock];
        [self.subcriberIds addObject:subcriber.subcriberId];
    });
    return subcriber;
}

-(Subcriber *_Nonnull)subcribeKeySelector:(SEL _Nonnull)propertySelector binding:(SubcribeBlock _Nonnull)subBlock {
    __block Subcriber *subcriber;
    dispatch_sync(self.excutionQueue, ^{
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
    
    dispatch_sync(self.excutionQueue, ^{
        // fire keypath event
        NSMutableArray *propertySelectorSubcriberIds = self.selectorSubcribers[keyPath];
        for (NSString *subcriberId in propertySelectorSubcriberIds) {
            SubcribeBlock block = self.subcriberById[subcriberId].subBlock;
            block(keyPath, [self valueForKey:keyPath]);
        }
        
        // fire main event
        for (NSString *subcriberId in self.subcriberIds) {
            SubcribeBlock block = self.subcriberById[subcriberId].subBlock;
            block(keyPath, [self valueForKey:keyPath]);
        }
        
        [self didObserveKeypath:keyPath];
    });
}

-(Subcriber *)addSubcriberWithBlock:(SubcribeBlock)subBlock {
    [self addObservingProperties];
    
    Subcriber *subcriber = [[Subcriber alloc] init];
    subcriber.subBlock = subBlock;
    subcriber.observableObj = self;
    
    [self.subcriberById setObject:subcriber forKey:subcriber.subcriberId];
    return subcriber;
}

-(void)addSubcriber:(Subcriber *)subcriber forKeyPath:(NSString *)keyPath {
    NSMutableArray *subs = self.selectorSubcribers[keyPath];
    if (!subs) {
        subs = [[NSMutableArray alloc] init];
    }
    [subs addObject:subcriber.subcriberId];
    [self.selectorSubcribers setObject:subs forKey:keyPath];
}

-(void)removeSubcriberWithId:(NSString *)subcriberId {
    [self.subcriberIds removeObject:subcriberId];
    [self.subcriberById removeObjectForKey:subcriberId];
    NSMutableArray *selectorSubcriberIds;
    for (NSString *keyPath in self.selectorSubcribers.allKeys) {
        selectorSubcriberIds = self.selectorSubcribers[keyPath];
        [selectorSubcriberIds removeObject:subcriberId];
    }
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
        [self.subcriberIds removeAllObjects];
        [self.selectorSubcribers removeAllObjects];
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
- (void)dealloc {
    [self removeObservingProperties];
    [self removeSyncupObservingProperties];
    [self removeSubcribers];
}

@end
