//
//  NSObject+HTKVO.m
//  HTKVO
//
//  Created by ht on 2020/10/30.
//

#import "NSObject+HTKVO.h"
#import <objc/message.h>

// 自定义KVO
// 1. 模拟系统流程
// 2. 自动移除观察者
// 3. 响应式 + 函数式 整合

/**
 1. `addObserver`时:
     1.1 `验证`setter方法`是否存在`
     1.2 `注册`KVO派生类
     1.3  派生类添加`class`、`setter`、`dealloc`方法
     1.4  `isa指向`派生类
     1.5  保存信息
  2. 触发`setter`方法时：
     2.1 `willChange`
     2.1 消息转发（设置原类的属性值）
     2.2 `didChange`
 3. `removeObserver`：
    3.1 手动移除
    3.2 自动移除
 
 */

static NSString * const HTKVOPrefix = @"HTKVONotifying_";
static NSString * const HTKVOAssiociakey = @"HTKVO_AssiociaKey";

//MARK: - HTInfo 信息Model
@interface HTInfo : NSObject
@property (nonatomic, weak) NSObject *observer;
@property (nonatomic, copy) NSString *keyPath;
@property (nonatomic, copy) HTKVOBlock hanldBlock;

@end

@implementation HTInfo

- (instancetype) initWithObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath handleBlock:(HTKVOBlock) block {
    if (self = [super init]) {
        self.observer = observer;
        self.keyPath = keyPath;
        self.hanldBlock = block;
    }
    return self;
}

- (BOOL)isEqual:(HTInfo *)object {
    return[self.observer isEqual:object.observer] && [self.keyPath isEqualToString:object.keyPath];
}

@end

//MARK: - NSObject (HTKVO)
@implementation NSObject (HTKVO)

// 添加观察者
- (void)ht_addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath block:(HTKVOBlock)block {
    
    // 1.1 验证setter方法是否存在
    [self judgeSetterMethodFromKeyPath:keyPath];
    // 1.2 + 1.3 注册KVO派生类(动态生成子类) 添加方法
    Class newClass = [self creatChildClassWithKeyPath:keyPath];
    // 1.4 isa的指向： HTKVONotifying_HTPerosn
    object_setClass(self, newClass);
    // 1.5. 保存信息
    HTInfo * info = [[HTInfo alloc]initWithObserver:observer forKeyPath:keyPath handleBlock:block];
    [self associatedObjectAddObject:info];
}

// 移除观察者
- (void)ht_removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath {
    
    NSMutableArray * observerArr = objc_getAssociatedObject(self, (__bridge const void * _Nonnull)HTKVOAssiociakey);
    
    if (observerArr.count <= 0) return;
    
    for (HTInfo * info in observerArr) {
        if ([info.keyPath isEqualToString:keyPath]) {
            // 移除当前info
            [observerArr removeObject:info];
            // 重新设置关联对象的值
            objc_setAssociatedObject(self, (__bridge const void * _Nonnull)HTKVOAssiociakey, observerArr, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            break;
        }
    }
    
    // 全部移除后，isa指回父类
    if (observerArr.count <= 0) {
        Class superClass = [self class];
        object_setClass(self, superClass);
    }
    
}

//MARK: - 1.1 验证是否存在setter方法
- (void)judgeSetterMethodFromKeyPath:(NSString *) keyPath {
    Class class    = object_getClass(self);
    SEL setterSelector  = NSSelectorFromString(setterForGetter(keyPath));
    Method setterMethod = class_getInstanceMethod(class, setterSelector);
    if (!setterMethod) {
        @throw [NSException exceptionWithName: NSInvalidArgumentException
                                       reason:[NSString stringWithFormat:@"当前%@没有setter方法", keyPath]
                                     userInfo:nil];
    }
}

//MARK: - 1.2 + 1.3 注册KVO派生类(动态生成子类) 添加方法
- (Class)creatChildClassWithKeyPath: (NSString *) keyPath {
    
    // 1. 类名
    NSString * oldClassName = NSStringFromClass([self class]);
    NSString * newClassName = [NSString stringWithFormat:@"%@%@",HTKVOPrefix,oldClassName];
    
    // 2. 生成类
    Class newClass = NSClassFromString(newClassName);
    
    // 2.1 不存在，创建类
    if (!newClass) {
        
        // 2.2.1 申请内存空间 （参数1：父类，参数2：类名，参数3：额外大小）
        newClass = objc_allocateClassPair([self class], newClassName.UTF8String, 0);
        
        // 2.2.2 注册类
        objc_registerClassPair(newClass);
        
    }
    
    // 2.2.3 动态添加set函数
    SEL setterSel = NSSelectorFromString(setterForGetter(keyPath));
    Method setterMethod = class_getInstanceMethod([self class], setterSel); //为了保证types和原来的类的Imp保持一致，所以从[self class]提取
    const char * setterTypes = method_getTypeEncoding(setterMethod);
    class_addMethod(newClass, setterSel, (IMP)ht_setter, setterTypes);
    
    // 2.2.4 动态添加class函数 （为了让外界调用class时，看到的时原来的类，isa需要指向原来的类）
    SEL classSel = NSSelectorFromString(@"class");
    Method classMethod = class_getInstanceMethod([self class], classSel);
    const char * classTypes = method_getTypeEncoding(classMethod);
    class_addMethod(newClass, classSel, (IMP)ht_class, classTypes);
    
    // 2.2.5 动态添加dealloc函数
    SEL deallocSel = NSSelectorFromString(@"dealloc");
    Method deallocMethod = class_getInstanceMethod([self class], deallocSel);
    const char * deallocTypes = method_getTypeEncoding(deallocMethod);
    class_addMethod(newClass, deallocSel, (IMP)ht_dealloc, deallocTypes);
    
    return newClass;
}

//MARK: - 关联属性添加对象
- (void)associatedObjectAddObject:(HTInfo *)info {
    
    NSMutableArray * mArray = objc_getAssociatedObject(self, (__bridge const void * _Nonnull)HTKVOAssiociakey);
    if (!mArray) {
        mArray = [NSMutableArray arrayWithCapacity:1];
        objc_setAssociatedObject(self,  (__bridge const void * _Nonnull)HTKVOAssiociakey, mArray, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    for (HTInfo * tempInfo in mArray) {
        if ([tempInfo isEqual:info]) return;
    }
    
    [mArray addObject:info];
}

//MARK: - 动态添加的函数
// 1.3.1 setter方法
static void ht_setter(id self, SEL _cmd, id newValue) {
    NSLog(@"新值：%@", newValue);
    // 读取getter方法（属性名）
    NSString * keyPath = getterForSetter(NSStringFromSelector(_cmd));
    // 获取旧值
    id oldValue = [self valueForKey:keyPath];

    // 1. willChange在此处触发（本示例省略）

    // 2. 调用父类的setter方法(消息转发)
    // 修改objc_super的值，强制将super_class设置为父类
    void(* ht_msgSendSuper)(void *, SEL, id) = (void *)objc_msgSendSuper;

    // 创建并赋值
    struct objc_super superStruct = {
        .receiver = self,
        .super_class = class_getSuperclass(object_getClass(self)),
    };

    ht_msgSendSuper(&superStruct, _cmd, newValue);
    
//    objc_msgSendSuper(&superStruct, _cmd, newValue);
    
    // 3. didChange在此处触发（本示例省略）
    NSMutableArray * array = objc_getAssociatedObject(self, (__bridge const void * _Nonnull) HTKVOAssiociakey);
    
    for (HTInfo * info in array) {
        if([info.keyPath isEqualToString:keyPath] && info.observer){
            // 3.1 block回调的方式
            if (info.hanldBlock) {
                info.hanldBlock(info.observer, keyPath, oldValue, newValue);
            }
//            // 3.2 调用方法的方式
//            if([info.observer respondsToSelector:@selector(ht_observeValueForKeyPath: ofObject: change: context:)]) {
//                [info.observer ht_observeValueForKeyPath:keyPath ofObject:self change:@{keyPath: newValue} context:NULL];
//            }
        }
    }
    
}

// 1.3.2 改写class的imp实现
Class ht_class(id self, SEL _cmd) {
    return class_getSuperclass(object_getClass(self)); // 返回当前类的父类（原来的类）
}

// 1.3.3 重写dealloc方法
void ht_dealloc(id self, SEL _cmd) {
    
    NSLog(@"%s KVO派生类移除了",__func__);
    
    Class superClass = [self class];
    object_setClass(self, superClass);
}

//MARK: - 静态函数。从getter名称中读取setter   key => setKey:
static NSString * setterForGetter(NSString * getter) {
    
    if (getter.length <= 0) return nil;
    
    NSString * setterFirstChar = [getter substringToIndex:1].uppercaseString;
    
    return [NSString stringWithFormat:@"set%@%@:", setterFirstChar, [getter substringFromIndex:1]];
    
}

//MARK: - 静态函数。从getter名称中读取setter   setKey: => key
static NSString * getterForSetter(NSString * setter) {
    
    if (setter.length <= 0 || ![setter hasPrefix:@"set"] || ![setter hasSuffix:@":"]) return nil;
    
    //去除set，获取首字母，设置小写
    NSRange range = NSMakeRange(3, 1);
    NSString * getterFirstChar = [setter substringWithRange:range].lowercaseString;
    
    //去除set和首字母，取后部分
    range = NSMakeRange(4, setter.length - 5);
    return [NSString stringWithFormat:@"%@%@",getterFirstChar,[setter substringWithRange:range]];
}


@end
