//
//  PushViewController.m
//  HTKVO
//
//  Created by ht on 2020/10/29.
//

#import "PushViewController.h"
#import "HTPerson.h"
#import "NSObject+HTKVO.h"
#import <objc/runtime.h>

@interface PushViewController ()
@property (nonatomic, strong) HTPerson *person;
@end

@implementation PushViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.person = [HTPerson new];
    
    self.view.backgroundColor = UIColor.whiteColor;
    
    [self.person ht_addObserver:self forKeyPath:@"name" block:^(id  _Nonnull observer, NSString * _Nonnull keyPath, id  _Nonnull oldValue, id  _Nonnull newValue) {
        NSLog(@"回调响应：oldValue: %@, newValue:%@", oldValue, newValue);
    }];
    [self.person ht_addObserver:self forKeyPath:@"nickName" block:^(id  _Nonnull observer, NSString * _Nonnull keyPath, id  _Nonnull oldValue, id  _Nonnull newValue) {
        NSLog(@"回调响应：oldValue: %@, newValue:%@", oldValue, newValue);
    }];
    
    
    self.person.name = @"HT";
    self.person.nickName = @"nickName";
    
}

-(void)ht_observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    NSLog(@"--方法响应- %@",change);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    self.person.name = [NSString stringWithFormat:@"%@+", self.person.name];
    self.person.nickName = [NSString stringWithFormat:@"%@+", self.person.nickName];
    
    // 移除单个属性
//    [self.person ht_removeObserver:self forKeyPath:@"nickName"];
}

-(void)dealloc {
    NSLog(@"销毁");
}
@end
