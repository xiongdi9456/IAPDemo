//
//  IAPManager.h
//  IAPDemo
//
//  Created by Charles.Yao on 2016/10/31.
//  Copyright © 2016年 com.pico. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <StoreKit/StoreKit.h>

#ifdef DEBUG
#define NSLog(FORMAT, ...) fprintf(stderr, "[%s %s %s %s-第%d行] %s\n", __DATE__ , __TIME__, __func__, [[[NSString stringWithUTF8String: __FILE__] lastPathComponent] UTF8String], __LINE__, [[[NSString alloc] initWithData:[[NSString stringWithFormat:FORMAT, ##__VA_ARGS__] dataUsingEncoding:NSUTF8StringEncoding] encoding:NSNonLossyASCIIStringEncoding] UTF8String]?[[[NSString alloc] initWithData:[[NSString stringWithFormat:FORMAT, ##__VA_ARGS__] dataUsingEncoding:NSUTF8StringEncoding] encoding:NSNonLossyASCIIStringEncoding] UTF8String]:[[NSString stringWithFormat: FORMAT, ## __VA_ARGS__] UTF8String]);
#define NSFunc() NSLog(@"%s 第%d行",__func__,__LINE__);
#else
#define NSLog(FORMAT, ...) nil;
#define NSFunc(...);
#endif


typedef NS_ENUM(NSInteger, IAPFiledCode) {
    /**
     *  苹果返回错误信息
     */
    IAP_FILEDCOED_APPLECODE = 0,
    
    /**
     *  用户禁止应用内付费购买
     */
    IAP_FILEDCOED_NORIGHT = 1,
    
    /**
     *  商品为空
     */
    IAP_FILEDCOED_EMPTYGOODS = 2,
    /**
     *  无法获取产品信息，请重试
     */
    IAP_FILEDCOED_CANNOTGETINFORMATION = 3,
    /**
     *  购买失败，请重试
     */
    IAP_FILEDCOED_BUYFILED = 4,
    /**
     *  用户取消交易
     */
    IAP_FILEDCOED_USERCANCEL = 5
    
};

///前置条件说
///1.必须一单一单的进行充值，不能并行多单
///2.如果返回结果之前玩家就卸载了游戏，认为掉单，SDK客户端不可挽救

@protocol IApRequestResultsDelegate <NSObject>

- (void)failedWithErrorCode:(NSInteger)errorCode andError:(NSString *)error; //失败

@end

@interface IAPManager : NSObject

singleton_interface(IAPManager)

@property (nonatomic, weak)id<IApRequestResultsDelegate>delegate;

/**
 启动工具
 */
- (void)startManager;

/**
 结束工具
 */
- (void)stopManager;

/**
 购买商品
 */
- (void)purchaseWithProductId:(NSString *)productId AndCpOrderId:(NSString *)cpOrderId;


@end
