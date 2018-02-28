//
//  ObservableObject+Private.h
//  ReactiveObject
//
//  Created by Tung Nguyen on 2/5/18.
//  Copyright © 2018 Tung Nguyen. All rights reserved.
//

#import <Foundation/Foundation.h>
#define kCleanBagDealloc @"CleanBag_Dealloc"
#define kCleanBagObjectId @"CleanBag_ObjectId"

@interface CleanBag()

@property (nonatomic, strong) NSString * _Nullable bagId;
@property (nonatomic, strong) NSHashTable *_Nullable observables;

@end

@interface ObservableObject()

@property (nonatomic, strong) NSMutableArray <NSString /* blockId */ *> * _Nullable observers;
@property (nonatomic, strong) NSMutableDictionary <NSString *, NSMutableArray <NSString /* blockId */ *> *> * _Nullable selectorObservers;
@property (nonatomic, strong) NSMutableDictionary <NSString *, SubcribeBlock> * _Nullable subcriberById;
@property (nonatomic, strong) dispatch_queue_t _Nullable observerQueue;
@property (nonatomic, strong) dispatch_queue_t _Nullable excutionQueue;
@property (nonatomic, assign) BOOL obsAdded;

@property (nonatomic, weak) CleanBag * _Nullable bag;
@property (nonatomic, weak) ObservableObject * _Nullable syncupObject;
@property (nonatomic, copy) NSString * _Nullable objectID;

-(void)didObserveKeypath:(NSString *_Nonnull)key;

@end
