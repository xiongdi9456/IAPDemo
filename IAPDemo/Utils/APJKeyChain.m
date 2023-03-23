//
//  APJKeyChain.m
//  GameSDK
//
//  Created by sheldon on 2021/07/30.
//

#import "APJKeyChain.h"
#import <Security/Security.h>

@implementation APJKeyChain

+ (NSMutableDictionary *)getKeychainQueryMap:(NSString *)serviceDomain {
    
    NSMutableDictionary *queryMap = [[NSMutableDictionary alloc] init];
    [queryMap setObject:serviceDomain forKey:(__bridge id<NSCopying>)kSecAttrAccount];
    [queryMap setObject:serviceDomain forKey:(__bridge id<NSCopying>)kSecAttrService];
    [queryMap setObject:(__bridge id)(kSecClassGenericPassword) forKey:(__bridge id<NSCopying>)kSecClass];
    [queryMap setObject:(__bridge id)kSecAttrAccessibleAfterFirstUnlock forKey:(__bridge id<NSCopying>)kSecAttrAccessible];
    return queryMap;
}

+ (BOOL)setData:(id)data serviceDomain:(NSString *)serviceDomain {
    NSMutableDictionary *queryMap = [self getKeychainQueryMap:serviceDomain];
    SecItemDelete((__bridge CFDictionaryRef)(queryMap));
    NSData *archivedData;
    if (@available(iOS 11.0, *)) {
        NSError *error;
        archivedData = [NSKeyedArchiver archivedDataWithRootObject:data requiringSecureCoding:YES error:&error];
        if (error) {
            NSLog(@"writeToKeychain,err=%@", error.localizedDescription);
            return NO;
        }
    } else {
        archivedData = [NSKeyedArchiver archivedDataWithRootObject:data];
    }
    [queryMap setObject:archivedData forKey:(__bridge id<NSCopying>)(kSecValueData)];
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)(queryMap), NULL);
    return status == errSecSuccess?YES:NO;
}

+ (id)getDataWithServiceDomain:(NSString *)serviceDomain {
    id data = nil;
    NSMutableDictionary *queryMap = [self getKeychainQueryMap:serviceDomain];
    [queryMap setObject:(id)kCFBooleanTrue forKey:(__bridge id<NSCopying>)(kSecReturnData)];
    [queryMap setObject:(__bridge id)(kSecMatchLimitOne) forKey:(__bridge id<NSCopying>)(kSecMatchLimit)];

    CFTypeRef result = NULL;
    CFDictionaryRef cfDicRef = (__bridge_retained CFDictionaryRef)queryMap;
    if (SecItemCopyMatching(cfDicRef, &result) == noErr) {
        
        if (@available(iOS 11.0, *)) {
            NSError *error;
//            data = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSString class] fromData:(__bridge NSData*)result error:&error];
            data = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithArray:@[NSArray.class,NSDictionary.class, NSString.class, UIFont.class, NSMutableArray.class, NSMutableDictionary.class, NSMutableString.class, UIColor.class, NSMutableData.class, NSData.class, NSNull.class, NSValue.class,NSDate.class]] fromData:(__bridge NSData*)result error:&error];
            if(error != nil) {
                NSLog(@"readFromKeyChainFailed, err=%@", error.localizedDescription);
            }
        }
        else {
            data = [NSKeyedUnarchiver unarchiveObjectWithData:(__bridge NSData*)result];
        }
        CFRelease(result);
    }
    return data;
}

+ (BOOL)deleteDataWithServiceDomain:(NSString *)serviceDomain {
    NSMutableDictionary *queryMap = [self getKeychainQueryMap:serviceDomain];
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)(queryMap));
    return status == errSecSuccess?YES:NO;
}


@end
