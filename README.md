# HTKVO
简单实现KVO原理

1. `addObserver`时:

    1.1 `验证`setter方法`是否存在`
    
    1.2 `注册`KVO派生类
    
    1.3  派生类添加`setter`、`class`、`dealloc`方法
    
    1.4  `isa指向`派生类
    
    1.5  保存信息
    
 2. 触发`setter`方法时：
 
    2.1 `willChange`
    
    2.1 消息转发（设置原类的属性值）
    
    2.2 `didChange`
    
3. `removeObserver`：

   3.1 手动移除
   
   3.2 自动移除

> 为了简化步骤，本示例忽略了以下内容：
> 1. `NSKeyValueObservingOptions` 监听类型
> 2. `observeValueForKeyPath`响应类型
> 3. `context`上下文识别值

> 本示例中:
> - `ViewController`：`有导航控制器`的`根视图`，点击`Push按钮`可跳转`PushViewController`；
> - `PushViewController`：测试控制器，实现`HTPerson`属性的`添加观察者`、`触发属性变化`、`移除观察者`等功能；
> - `HTPerosn`：继承自`NSObject`，具备`name`和`nickName`属性的类
> - `NSObject+HTKVO`：重写KVO的相关功能
>  [ 👉 代码下载 ]()

- 准备好了，我们就开始吧 🏃🏃🏃

---
## 1. 添加`addObserver`

```
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
```

#### 1.1 `验证`setter方法`是否存在`
- 因为我们`监听`的是`setter`方法，所以当前`被监听属性`必须具备`setter`方法。(`排除成员变量`)
```
//MARK: -  验证是否存在setter方法
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
```

> - 1. `HTKVO`类的`命名前缀`，`关联属性`的`key`：
> ```
> static NSString * const HTKVOPrefix = @"HTKVONotifying_";
> static NSString * const HTKVOAssiociakey = @"HTKVO_AssiociaKey";
> ```
> - 2.  从`getter`名称中`读取setter` ， `key => setKey`:
>```
>static NSString * setterForGetter(NSString * getter) {
>    
>    if (getter.length <= 0) return nil;
>    
>    NSString * setterFirstChar = [getter substringToIndex:1].uppercaseString;
>    
>    return [NSString stringWithFormat:@"set%@%@:", setterFirstChar, [getter substringFromIndex:1]];
>    
>}
>```
> - 3. 从`getter`名称中`读取setter`  ，`setKey: => key`：
>```
>static NSString * getterForSetter(NSString * setter) {
>    
>    if (setter.length <= 0 || ![setter hasPrefix:@"set"] || ![setter hasSuffix:@":"]) return nil;
>    
>    //去除set，获取首字母，设置小写
>    NSRange range = NSMakeRange(3, 1);
>    NSString * getterFirstChar = [setter substringWithRange:range].lowercaseString;
>    
>    //去除set和首字母，取后部分
>    range = NSMakeRange(4, setter.length - 5);
>    return [NSString stringWithFormat:@"%@%@",getterFirstChar,[setter substringWithRange:range]];
>}
>```

####   1.2 `注册`KVO派生类
- 1. 获取类名 -> 2. 生成类 (注册类、重写方法)

**重写方法： `方法名sel`和`类型编码TypeEncoding`必须和父类一样，但`imp`是使用`自己`的`实现内容`**
```
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
```
####  1.3  派生类添加`setter`、`class`、`dealloc`方法
###### 1.3.1 `setter`方法
```
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
    
    // 3. didChange在此处触发
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
```
`外部赋值`，触发`setter`时，有3个需要注意的点：

- 1. `赋值前`： 本案例没实现`赋值前`的`willChange`事件。因为与下面的`didChange`方式一样，只是状态不同；

- 2. `赋值`： 调用`父类`的`setter`方法，我们是通过`objc_msgSendSuper`进行调用。我们重写`objc_super`的结构体并完成`receiver`和`super_class`的赋值。
> 此处有2种写法：
> - 1.  直接使用`objc_msgSendSuper`调用，会报`参数错误`：
> ![image.png](https://upload-images.jianshu.io/upload_images/12857030-3a353829f6150776.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
>
>  我们在`Build Setting`中关闭`objc_msgSend`的编译检查，即可通过 
> ![image.png](https://upload-images.jianshu.io/upload_images/12857030-174c52ddad7a27cb.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
>
> - 2. 新创建一个`ht_msgSendSuper`引用`objc_msgSendSuper`，这样`编译`就`不会报错`，不需要关闭编译检查：
> ![image.png](https://upload-images.jianshu.io/upload_images/12857030-9d388f6add6a2f37.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

- 3. `赋值后`： 我们有2种方法可以实现didChange事件，告知外部：
> - 方式一: 和苹果官方一样，`NSObject+HTKVO.h`文件中对外公开`ht_observeValueForKeyPath`函数：
> ![image.png](https://upload-images.jianshu.io/upload_images/12857030-b02d0b4560e1fad3.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
> 外部`PushViewController.m`文件中，必须实现`ht_observeValueForKeyPath`函数:
> ![image.png](https://upload-images.jianshu.io/upload_images/12857030-498311144d7b8a44.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
> 但是此方法方式让代码很分散，开发者需要在2个地方同时实现`ht_addObserver`和`ht_observeValueForKeyPath`两个函数。 所以我们引进了第二种方法：
>
> - 方式二： `响应式 + 函数式` ,直接在`ht_addObserver`中添加`Block`回调代码块，需要响应的时候，我们直接`响应block`即可。
>
>  在`NSObject+HTKVO.h`中只需要对外声明`ht_addObserver`一个函数即可。其中包含`HTKVOBlock`回调类型：
>![image.png](https://upload-images.jianshu.io/upload_images/12857030-b4d5739d848f949e.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
> 
> - `NSObject+HTKVO.m`中响应`block`:
> ![image.png](https://upload-images.jianshu.io/upload_images/12857030-1b7666e5e6980281.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
>
> 外部`PushViewController.m`文件中，在实现`ht_addObserver`函数时，直接实现`block`响应就行。这样完成了`代码的内聚`。
>![image.png](https://upload-images.jianshu.io/upload_images/12857030-5aa93a55cf7f48de.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

>**补充`关联对象`相关内容：**
>- 1. 我们创建`HTInfo`类，用于记录`observer被观察对象`、`keyPath属性名`和`hanldBlock`回调。
>(为了简化研究，我们省略了`观察类型`、`context`)
>```
>//MARK: - HTInfo 信息Model
>@interface HTInfo : NSObject
>@property (nonatomic, weak) NSObject *observer;
>@property (nonatomic, copy) NSString *keyPath;
>@property (nonatomic, copy) HTKVOBlock hanldBlock;
>@end
>
>@implementation HTInfo
>- (instancetype) initWithObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath handleBlock:(HTKVOBlock) block {
>    if (self = [super init]) {
>        self.observer = observer;
>        self.keyPath = keyPath;
>        self.hanldBlock = block;
>    }
>    return self;
>}
>- (BOOL)isEqual:(HTInfo *)object {
>    return[self.observer isEqual:object.observer] && [self.keyPath isEqualToString:object.keyPath];
>}
>@end
>```
>- 2. 为了快速理解，我们使用了`NSMutableArray`数组进行存储。
>（事实上，`NSMapTable`更合适，文末分析`FBKVOController`时，我们进行拓展）
>- 3. 我们动态添加`关联属性`，用于`数据存储` (类型为`NSMutableArray`)。

###### 1.3.2 `class`方法
- `class`方法，主要是让`外界读取`时，`看不到KVO派生类`，输出的是`原来的类`
```
Class ht_class(id self, SEL _cmd) {
    return class_getSuperclass(object_getClass(self)); // 返回当前类的父类（原来的类）
}
```

###### 1.3.3 `dealloc`方法
重写了`dealloc`方法，并将`isa`从`KVO衍生类`指回了`原来的类`。 

- **在`isa指回`的同时，`KVO衍生类`会被释放，相应的`关联属性`也`被释放`。从而达到了`自动移除观察者`的效果**
```
void ht_dealloc(id self, SEL _cmd) {
    NSLog(@"%s KVO派生类移除了",__func__);
    Class superClass = [self class];
    object_setClass(self, superClass);
}
```

#### 1.4 `isa指向`派生类
```
// 1.4 isa的指向： HTKVONotifying_HTPerosn
object_setClass(self, newClass);
```

#### 1.5 保存信息：
- 创建`Info`实例保存`观察数据` 
-> 读取`关联属性`数组(当前所有观察对象)
-> 如果`关联属性`数组不存在，就创建一个
(使用`OBJC_ASSOCIATION_RETAIN_NONATOMIC`没关系，因为`关联属性不存在强引用`，只是`记录类名`和`属性名`)
-> 如果被监听对象`已存在`，直接`跳出`
-> `添加`监听对象

```
HTInfo * info = [[HTInfo alloc]initWithObserver:observer forKeyPath:keyPath handleBlock:block];
[self associatedObjectAddObject:info];
```
- 关联属性添加对象
```
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
```

## 2. 触发`setter`方法时
 在`1.3.1 setter方法`中已描述清晰。
主要是三步：`willChange` -> `设置原类属性` -> `didChange`

## 3. `removeObserver`：
#### 3.1 手动移除：
- 移除指定`被监听属性`，如果都被移除了，就将`isa`指回`父类`。
```
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
```
> **Q：`手动`把所有`被监听属性`都`移除`，触发`isa指回本类`，那`dealloc`触发`ht_dealloc`触发时，`isa`会不会指向`父类的父类`了？** 
> - 不会。因为`isa指回本类`后，`KVO派生类`对象已被释放。不会再进入`ht_dealloc`。
> 这也是为什么将`isa指回本类`，会`自动移除观察者`。因为`派生类对象`已被释放，他记录的`关联属性`也`自动被释放`。
