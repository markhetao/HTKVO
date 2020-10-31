//
//  NSObject+HTKVO.h
//  HTKVO
//
//  Created by ht on 2020/10/30.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^HTKVOBlock)(id observer, NSString * keyPath, id oldValue, id newValue);

@interface NSObject (HTKVO)

// 添加观察者
- (void)ht_addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath block:(HTKVOBlock)block;

//// 外部响应
//- (void)ht_observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context;

// 手动移除观察者
- (void)ht_removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath;


@end

NS_ASSUME_NONNULL_END
