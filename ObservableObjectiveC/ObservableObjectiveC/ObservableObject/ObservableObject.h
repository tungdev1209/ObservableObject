//
//  ObservableObject.h
//  CoredataVIPER
//
//  Created by Tung Nguyen on 2/2/18.
//  Copyright © 2018 Tung Nguyen. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^SubcribeBlock)(NSString *_Nonnull keypath, id _Nullable value);

@interface CleanBag: NSObject
@end

@interface Subcriber: NSObject

@property (nonatomic, strong) SubcribeBlock subBlock;

-(void)cleanupBy:(CleanBag * _Nonnull)bag;

@end

@interface ObservableObject : NSObject

-(ObservableObject *_Nonnull)syncupWithObject:(ObservableObject *_Nonnull)object;
-(ObservableObject *_Nonnull)removeSyncupObject;
-(Subcriber *_Nonnull)subcribe:(SubcribeBlock _Nonnull)subcriber;
-(Subcriber *_Nonnull)subcribeKeySelector:(SEL _Nonnull)propertySelector binding:(SubcribeBlock _Nonnull)subcriber;

@end
