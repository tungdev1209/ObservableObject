//
//  ObservableObject.h
//  ReactiveObject
//
//  Created by Tung Nguyen on 2/2/18.
//  Copyright © 2018 Tung Nguyen. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^SubcribeBlock)(id _Nullable);

@interface CleanBag: NSObject

+(instancetype _Nonnull)bag;

@end

@interface ObservableObject : NSObject

-(ObservableObject *_Nonnull)syncupWithObject:(ObservableObject *_Nonnull)object;
-(ObservableObject *_Nonnull)removeSyncupObject;
-(ObservableObject *_Nonnull)subcribe:(SubcribeBlock _Nonnull)subcriber;
-(ObservableObject *_Nonnull)subcribeKeySelector:(SEL _Nonnull)propertySelector binding:(SubcribeBlock _Nonnull)subcriber;
-(void)cleanupBy:(CleanBag * _Nonnull)bag;

@end
