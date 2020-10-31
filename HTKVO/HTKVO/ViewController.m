//
//  ViewController.m
//  HTKVO
//
//  Created by ht on 2020/10/29.
//

#import "ViewController.h"
#import "PushViewController.h"
#import "HTPerson.h"

#import <objc/runtime.h>

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
}

/// push
- (IBAction)pushVC:(id)sender {
    // 检验子类
    [self printClasses: [HTPerson class]];
    
    [self.navigationController pushViewController:[PushViewController new] animated:true];
}

/// 遍历本类及子类
-(void) printClasses: (Class)cls {
    
    // 注册类的总数
    int count = objc_getClassList(NULL, 0);
    // 创建1个数组
    NSMutableArray * mArray = [NSMutableArray arrayWithObject:cls];
    //获取所有已注册的类
    Class * classes = (Class *)malloc(sizeof(Class) * count);
    objc_getClassList(classes, count);
    for (int i = 0; i < count; i++) {
        if (cls == class_getSuperclass(classes[i])) {
            [mArray addObject:classes[i]];
        }
    }
    free(classes);
    NSLog(@"classes: %@",mArray);
}

@end
