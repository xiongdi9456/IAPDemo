//
//  APJKeyChain.h
//  GameSDK
//
//  Created by sheldon on 2021/07/30.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface APJKeyChain : NSObject

+ (BOOL)setData:(id)data serviceDomain:(NSString *)serviceDomain;

+ (id)getDataWithServiceDomain:(NSString *)serviceDomain;

+ (BOOL)deleteDataWithServiceDomain:(NSString *)serviceDomain;

@end

NS_ASSUME_NONNULL_END
