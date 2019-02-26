//
//  ObservableObject+Private.h
//  CoredataVIPER
//
//  Created by Tung Nguyen on 2/5/18.
//  Copyright © 2018 Tung Nguyen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ObservableObject.h"

#define kCleanBagDealloc @"CleanBag_Dealloc"
#define kCleanBagObjectId @"CleanBag_ObjectId"

@interface CleanBag()

@property (nonatomic, copy) NSString * _Nullable bagId;
@property (nonatomic, strong) NSHashTable *_Nullable subcribers;
@property (nonatomic, strong) dispatch_queue_t subcriberQueue;

-(void)registerSubcriberObject:(Subcriber *)sub;

@end

@interface Subcriber()

@property (nonatomic, copy) NSString * _Nonnull subcriberId;
@property (nonatomic, weak) CleanBag * _Nullable bag;
@property (nonatomic, weak) ObservableObject * _Nullable observableObj;
@property (nonatomic, strong) dispatch_queue_t observeQueue;

@end

@interface ObservableObject()

@property (nonatomic, strong) NSMutableArray <NSString *> * _Nullable subcriberIds;
@property (nonatomic, strong) NSMutableDictionary <NSString *, NSMutableArray <NSString *> *> * _Nullable selectorSubcribers;
@property (nonatomic, strong) NSMutableDictionary <NSString *, Subcriber *> * _Nullable subcriberById;
@property (nonatomic, strong) dispatch_queue_t subIdsQueue;
@property (nonatomic, strong) dispatch_queue_t subByIdsQueue;
@property (nonatomic, strong) dispatch_queue_t selectorSubQueue;
@property (nonatomic, strong) dispatch_queue_t _Nullable observerQueue;
@property (nonatomic, strong) dispatch_queue_t _Nullable excutionQueue;
@property (nonatomic, assign) BOOL obsAdded;

@property (nonatomic, weak) ObservableObject * _Nullable syncupObject;
@property (nonatomic, copy) NSString * _Nullable objectID;

-(void)removeSubcriberWithId:(NSString *)subcriberId;
-(void)didObserveKeypath:(NSString *_Nonnull)key;

@end
