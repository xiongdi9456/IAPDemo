//
//  IAPManager.m
//  IAPDemo
//
//  Created by Charles.Yao on 2016/10/31.
//  Copyright © 2016年 com.pico. All rights reserved.
//
#import <CommonCrypto/CommonDigest.h>
#import "IAPManager.h"
#import "APJKeyChain.h"
//#import "MBProgressHUD+XY.h"

static NSString * const receiptKey = @"receipt_key";
static NSString * const dateKey = @"date_key";
static NSString * const userIdKey = @"userId_key";
static NSString * const receiptIdKey = @"receiptId_key";
static NSString * const productIdKey = @"productId_key";
//static NSString * const transactionIdKey = @"transactionId_key";
static NSString * const receiptArrayInKeyChainKey = @"receipt_ikc_key";

dispatch_queue_t iap_queue() {
    static dispatch_queue_t as_iap_queue;
    static dispatch_once_t onceToken_iap_queue;
    dispatch_once(&onceToken_iap_queue, ^{
        as_iap_queue = dispatch_queue_create("com.apjiap.queue", DISPATCH_QUEUE_CONCURRENT);
    });
    
    return as_iap_queue;
}

@interface IAPManager ()<SKPaymentTransactionObserver, SKProductsRequestDelegate>
@property (nonatomic, assign) BOOL isIapProcessFinished; //判断一次请求是否完成
@property (nonatomic, copy) NSString *receipt; //交易成功后拿到的一个64编码字符串
@property (nonatomic, copy) NSString *date; //交易时间
@property (nonatomic, copy) NSString *userId; //交易人

@end

@implementation IAPManager

singleton_implementation(IAPManager)

- (void)startManager { //开启监听

    dispatch_async(iap_queue(), ^{
       
        self.isIapProcessFinished = YES;
        
        
        /***
         内购支付两个阶段：
         1.app直接向苹果服务器请求商品，支付阶段；
         2.苹果服务器返回凭证，app向公司服务器发送验证，公司再向苹果服务器验证阶段；
         */
        
        /**
         阶段一正在进中,app退出。
         在程序启动时，设置监听，监听是否有未完成订单，有的话恢复订单。
         */
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
        
        NSLog(@"[SKPaymentQueue defaultQueue].transactions.count=%lu.", (unsigned long)[SKPaymentQueue defaultQueue].transactions.count);
        [self readTransactionInQueue];
        
        /**
         阶段二正在进行中,app退出。
         在程序启动时，检测本地是否有receipt文件，有的话，去二次验证。
         不在这里检测本地环境，有逻辑bug：如果第二阶段处理时间较长同时玩家退出了并没有完成finishTransaction,如果在这里开启会导致发送两次请求。
         */
        //[self checkIAPFiles];
    });
}

//
#pragma mark -- 结束上次未完成的交易 防止串单-商店的第一阶段完成，但是第二阶段没完成可能
-(void)removeAllUncompleteTransactionBeforeStartNewTransaction{
    NSArray* transactions = [SKPaymentQueue defaultQueue].transactions;
    if (transactions.count > 0) {
        //检测是否有未完成的交易
        SKPaymentTransaction* transaction = [transactions firstObject];
        if (transaction.transactionState == SKPaymentTransactionStatePurchased) {
            [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
            return;
        }
    }
}

-(void)readTransactionInQueue{
    NSArray* transactions = [SKPaymentQueue defaultQueue].transactions;
    NSLog(@"readTransactionInQueue, transactions.count=%lu", (unsigned long)transactions.count);
    if (transactions.count > 0) {
        //检测是否有未完成的交易
        SKPaymentTransaction* transaction = [transactions firstObject];
        if (transaction.transactionState == SKPaymentTransactionStatePurchased) {
            NSLog(@"transaction.transactionIdentifier=%@,transaction.transactionState == SKPaymentTransactionStatePurchased", transaction.transactionIdentifier);
        }
    }
}

- (void)stopManager{

    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
    });
}

#pragma mark 查询
- (void)purchaseWithProductId:(NSString *)productId AndCpOrderId:(NSString *)cpOrderId{

    [self readTransactionInQueue];
    // && [SKPaymentQueue defaultQueue].transactions.count == 0
    if (self.isIapProcessFinished) {
       
        if ([SKPaymentQueue canMakePayments]) {
            //用户允许app内购
            if (productId.length) {
                //[MBProgressHUD showActivityMessageInView:@"GameSDK开始从商店获取商品信息..."];
                NSLog(@"GameSDK开始从商店获取%@的商品信息....", productId);
               
                self.isIapProcessFinished = NO; //正在请求
               
                NSArray *product = [[NSArray alloc] initWithObjects:productId, nil];
                
                NSSet *set = [NSSet setWithArray:product];
               
                SKProductsRequest *productRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:set];
               
                productRequest.delegate = self;
               
                [productRequest start];
            
            } else {
                NSLog(@"GameSDK要购买的商品ID非法");
                [self failedWithErrorCode:IAP_FILEDCOED_EMPTYGOODS error:nil];
                self.isIapProcessFinished = YES; //完成请求
            }
        
        } else { //没有权限
            
            [self failedWithErrorCode:IAP_FILEDCOED_NORIGHT error:nil];
            self.isIapProcessFinished = YES; //完成请求
        }
    
    } else {

        NSLog(@"GameSDK上次请求还未完成，请稍等(有一单正在进行中)");
    }
}

#pragma mark SKProductsRequestDelegate 查询成功后的回调
- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {

    NSArray *product = response.products;
    
    if (product.count == 0) {
        
        NSLog(@"GameSDK无法从商店中获取商品信息，请重试");
        
        [self failedWithErrorCode:IAP_FILEDCOED_CANNOTGETINFORMATION error:nil];
        self.isIapProcessFinished = YES; //失败，请求完成

    } else {
        NSLog(@"GameSDK从商店获取商品信息成功，开始进行购买.....");
        //发起购买请求-因为只传入了一个商品，所以可以使用第一个item就可以
        SKMutablePayment *payment = [SKMutablePayment paymentWithProduct:product[0]];
        payment.applicationUsername = @"sheldon123456";
        [[SKPaymentQueue defaultQueue] addPayment:payment];
    }
}

#pragma mark SKProductsRequestDelegate 查询失败后的回调
- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    NSLog(@"GameSDK从商店获取商品信息失败，原因是%@", [error localizedDescription]);
    [self failedWithErrorCode:IAP_FILEDCOED_APPLECODE error:[error localizedDescription]];
    self.isIapProcessFinished = YES; //失败，请求完成
}

#pragma mark 购买操作后的回调
- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(nonnull NSArray<SKPaymentTransaction *> *)transactions {

    for (SKPaymentTransaction *transaction in transactions) {
       
        switch (transaction.transactionState) {
           
            case SKPaymentTransactionStatePurchasing://正在交易
                break;
            case SKPaymentTransactionStatePurchased://交易完成
                
                NSLog(@"GameSDK开始获取交易成功后的购买凭证, transactionId=%@", transaction.transactionIdentifier);
                NSLog(@"transaction.payment.applicationUsername=%@", transaction.payment.applicationUsername);
                NSLog(@"transaction.payment.productId=%@", transaction.payment.productIdentifier);
                
                //[self getReceipt]; //获取交易成功后的购买凭证
               
//                NSLog(@"GameSDK开始存储交易凭证");
//                [self saveReceiptWithTransactionId:transaction.transactionIdentifier AndProductId:transaction.payment.productIdentifier]; //存储交易凭证
               
                //NSLog(@"GameSDK开始把self.receipt发送到服务器验证是否有效");
                //[self checkIAPFiles];//把self.receipt发送到服务器验证是否有效
                
                [self completeTransaction:transaction];
                
                
                break;

            case SKPaymentTransactionStateFailed://交易失败
               
                [self failedTransaction:transaction];
                
                break;

            case SKPaymentTransactionStateRestored://已经购买过该商品
                
                [self restoreTransaction:transaction];
                
                break;
           
            default:
               
                break;
        }
    }
}

#pragma mark 购买完成
- (void)completeTransaction:(SKPaymentTransaction *)transaction {

    //获取收据信息
    NSURL *receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptUrl];
    self.receipt = [receiptData base64EncodedStringWithOptions:0];
    
    
    self.date = [NSDate chindDateFormate:[NSDate date]];
    self.userId = @"UserID12345";
   
    NSMutableDictionary *dic =[NSMutableDictionary dictionaryWithObjectsAndKeys:
                        self.receipt,                           receiptKey,
                        self.date,                              dateKey,
                        self.userId,                            userIdKey,
                        transaction.transactionIdentifier,      receiptIdKey,
                        transaction.payment.productIdentifier,  productIdKey,
                        nil];

    ///keychain
    NSString* oneReceiptdata = [self apjDictionaryToJsonString:dic];
    if (oneReceiptdata == nil) {
        NSLog(@"dictionary转化string失败");
        return;
    }
    NSLog(@"开始将数据写入keychain,数据=%@", oneReceiptdata);
    
    NSMutableDictionary* receiptDectionary = [APJKeyChain getDataWithServiceDomain:receiptArrayInKeyChainKey];
    NSLog(@"现有keychain中 receiptDectionary=%@.", receiptDectionary);
    if([self isNullDictionary:receiptDectionary])
    {
        //创建字典数据并且写入
        receiptDectionary = [NSMutableDictionary dictionaryWithObject:oneReceiptdata forKey:transaction.transactionIdentifier];
        NSLog(@"创建字典数据并且写入keychain")
    } else {
        //存在旧的收据
        [receiptDectionary setValue:oneReceiptdata forKey:transaction.transactionIdentifier];
        NSLog(@"存在旧的收据并且写入keychain")
    }
    [APJKeyChain setData:receiptDectionary serviceDomain:receiptArrayInKeyChainKey];
    
    [APJKeyChain setData:@"good" serviceDomain:@"mTest"];
    NSString* res = [APJKeyChain getDataWithServiceDomain:@"mTest"];
    NSLog(@"res=%@", res);
    
    NSMutableDictionary* receiptDictionary = [APJKeyChain getDataWithServiceDomain:receiptArrayInKeyChainKey];
    NSLog(@"从keychain中获取到了收据字,开始处理...");
    
    if ([self isNullDictionary:receiptDictionary]) {
        NSLog(@"Keychain中读取收据失败了");
        return;
    }
    
    NSArray *keys = [receiptDictionary allKeys];
    for (NSString *key in keys) {
        NSString* oneReceiptStringData = [receiptDictionary objectForKey:key];
        NSLog(@"%@ is %@",key, oneReceiptStringData);
        NSMutableDictionary *oneReceiptDictData = [self apjJsonStringToDictionary:oneReceiptStringData];
        if (oneReceiptDictData != nil) {
            NSLog(@"GameSDK获取到oneReceiptDictData[dateKey] = %@", [oneReceiptDictData objectForKey:dateKey]);
            NSLog(@"GameSDK获取到oneReceiptDictData[receiptIdKey] = %@", [oneReceiptDictData objectForKey:receiptIdKey]);
            NSLog(@"GameSDK获取到oneReceiptDictData[receiptKey] = %@", [oneReceiptDictData objectForKey:receiptKey]);
            NSString* receiptId = [oneReceiptDictData objectForKey:receiptIdKey];
            NSLog(@"receiptId=%@", receiptId)
            [self readTransactionInQueue];
            [NSThread sleepForTimeInterval:5.0];
            //HTTP请求
            //HTTP请求处理成功了
            if(true) {
                [receiptDictionary removeObjectForKey:key];
                //测试用，暂时先不做finish模拟掉单
                [[SKPaymentQueue defaultQueue] finishTransaction: transaction];
            }
        }
    }
    
    NSLog(@"从keychain中获取到收据字典处理完成后变成=%@", receiptDictionary);
    [APJKeyChain setData:receiptDictionary serviceDomain:receiptArrayInKeyChainKey];
    
    self.isIapProcessFinished = YES; //成功，请求完成
}


#pragma mark 购买失败
- (void)failedTransaction:(SKPaymentTransaction *)transaction {

    NSLog(@"GameSDK购买商品失败,transaction.error.code = %ld, 错误信息=%@", transaction.error.code, transaction.error.localizedDescription);

    if(transaction.error.code != SKErrorPaymentCancelled) {
        NSLog(@"GameSDK因为某种原因购买失败了,错误信息=%@.", transaction.error.localizedDescription);
        [self failedWithErrorCode:IAP_FILEDCOED_BUYFILED error:nil];

    } else {
        NSLog(@"GameSDK用户自己取消了购买....");
        [self failedWithErrorCode:IAP_FILEDCOED_USERCANCEL error:nil];
    }

    [[SKPaymentQueue defaultQueue] finishTransaction: transaction];
    self.isIapProcessFinished = YES; //失败，请求完成
}

#pragma mark restore购买完成
- (void)restoreTransaction:(SKPaymentTransaction *)transaction {
    [[SKPaymentQueue defaultQueue] finishTransaction: transaction];
    self.isIapProcessFinished = YES; //恢复购买，请求完成
}

#pragma mark 获取交易成功后的购买凭证

- (void)getReceipt {
    NSURL *receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptUrl];
    self.receipt = [receiptData base64EncodedStringWithOptions:0];
}

#pragma mark  持久化存储用户购买凭证(这里最好还要存储当前日期，用户id等信息，用于区分不同的凭证)
-(void)saveReceiptWithTransactionId:(NSString*) transactionId AndProductId:(NSString*) productId{

    self.date = [NSDate chindDateFormate:[NSDate date]];
    
//    NSString *fileName = [NSString uuid];
//    NSString *fileName = [self md5HexDigest:self.receipt];
//    NSLog(@"will save fileName=%@.", fileName);
    
    self.userId = @"UserID12345";
   
    //NSString *savedPath = [NSString stringWithFormat:@"%@/%@.plist", [SandBoxHelper iapReceiptPath], fileName];
    
    NSMutableDictionary *dic =[NSMutableDictionary dictionaryWithObjectsAndKeys:
                        self.receipt,                           receiptKey,
                        self.date,                              dateKey,
                        self.userId,                            userIdKey,
                               transactionId,                               receiptIdKey,
                               productId, productIdKey,
                        nil];
   
//    NSLog(@"%@",savedPath);
//    [dic writeToFile:savedPath atomically:YES];
//
//    //保存收据信息到文件
//    NSLog(@"将收据保存到文件%@完成了", savedPath);
//
    ///keychain
    
    NSString* oneReceiptdata = [self apjDictionaryToJsonString:dic];
    if (oneReceiptdata == nil) {
        NSLog(@"dictionary转化string失败");
        return;
    }
    NSLog(@"开始将数据写入keychain,数据=%@", oneReceiptdata);
    
    NSMutableDictionary* receiptDectionary = [APJKeyChain getDataWithServiceDomain:receiptArrayInKeyChainKey];
    NSLog(@"现有keychain中 receiptDectionary=%@.", receiptDectionary);
    if([self isNullDictionary:receiptDectionary])
    {
        //创建字典数据并且写入
        receiptDectionary = [NSMutableDictionary dictionaryWithObject:oneReceiptdata forKey:transactionId];
        //[APJKeyChain setData:receiptDectionary serviceDomain:receiptArrayInKeyChainKey];
        
        NSLog(@"创建字典数据并且写入keychain")
    } else {
        //存在旧的收据
        [receiptDectionary setValue:oneReceiptdata forKey:transactionId];
        NSLog(@"存在旧的收据并且写入keychain")

    }
    [APJKeyChain setData:receiptDectionary serviceDomain:receiptArrayInKeyChainKey];
    NSLog(@"写入keychain完成,receiptDectionary=%@", receiptDectionary);
    
}

#pragma mark 将存储到本地的IAP文件发送给服务端 验证receipt失败,App启动后再次验证
- (void)checkIAPFiles{
    NSLog(@"开始读取缓存的收据信息");
    
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
   
    //搜索该目录下的所有文件和目录
    NSArray *cacheFileNameArray = [fileManager contentsOfDirectoryAtPath:[SandBoxHelper iapReceiptPath] error:&error];
    if (error == nil) {
        for (NSString *name in cacheFileNameArray) {
            if ([name hasSuffix:@".plist"]){ //如果有plist后缀的文件，说明就是存储的购买凭证
                //开始有购买流程
                self.isIapProcessFinished = NO;
               
                NSString *filePath = [NSString stringWithFormat:@"%@/%@", [SandBoxHelper iapReceiptPath], name];
                NSLog(@"GameSDK将存储到本地的信息发送到服务器，找到了文件%@", filePath);
                NSDictionary *dic = [NSDictionary dictionaryWithContentsOfFile:filePath];

                //这里的参数请根据自己公司后台服务器接口定制，但是必须发送的是持久化保存购买凭证
                NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                               [dic objectForKey:receiptKey],          receiptKey,
                                               [dic objectForKey:dateKey],             dateKey,
                                               [dic objectForKey:userIdKey],           userIdKey,
                                               nil];
                
                [self sendAppStorePurchaseRequestWithReceiptData:params];
            }
        }
    
    } else {
       
        NSLog(@"GameSDK AppStoreInfoLocalFilePath error:%@", error.localizedDescription);
        
        
    }
}

-(void) checkIAPDataInKeychain {
    ///检查keychain
    NSMutableDictionary* receiptDictionary = [APJKeyChain getDataWithServiceDomain:receiptArrayInKeyChainKey];
    if ([self isNullDictionary:receiptDictionary]) {
        NSLog(@"Keychain中读取收据失败了");
        return;
    }
    
    NSArray *keys = [receiptDictionary allKeys];
    for (NSString *key in keys) {
        NSString* oneReceiptStringData = [receiptDictionary objectForKey:key];
        NSLog(@"%@ is %@",key, oneReceiptStringData);
        NSMutableDictionary *oneReceiptDictData = [self apjJsonStringToDictionary:oneReceiptStringData];
        if (oneReceiptDictData != nil) {
            [self sendAppStorePurchaseRequestWithReceiptData:oneReceiptDictData];
        }
    }
    
}

-(void)sendAppStorePurchaseRequestWithReceiptData:(NSMutableDictionary*) params {
    //[MBProgressHUD showActivityMessageInView:@"订单验证中..."];
    
    //NSLog(@"GameSDK将存储到本地的信息发送到服务器，找到了文件并且从文件中读取了信息, params[receiptKey] = %@", params[receiptKey]);
    NSLog(@"GameSDK获取到params[dateKey] = %@", [params objectForKey:dateKey]);
    NSLog(@"GameSDK获取到params[userIdKey] = %@", [params objectForKey:userIdKey]);
    NSLog(@"GameSDK获取到params[receiptIdKey] = %@", [params objectForKey:receiptIdKey]);
    NSString* receiptId = [params objectForKey:receiptIdKey];

    [self readTransactionInQueue];
//    [[AFHTTPSessionManager manager]GET:@"后台服务器地址"  parameters:params  success:^(NSURLSessionDataTask * _Nonnull task, id  _Nonnull responseObject) {
//        if(凭证有效){
//            [self removeReceipt]
//        }else{//凭证无效
//            //你要做的事
//        }
//    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
//    }];
    
//    if(@"凭证有效"){
//
//        [self removeReceipt];
//
//    } else {//凭证无效
//
//        //做你想做的
//    }
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//            if (@"凭证有效")
//            {
//                [self removeReceipt];
//                [MBProgressHUD showSuccessMessage:@"支付成功"];
//
//            }
//            else
//            {
//                //凭证无效
//                [MBProgressHUD showErrorMessage:@"支付失败"];
//                //做你想做的
//            }
//        });
    [NSThread sleepForTimeInterval:5.0];
    
    //在服务器处理完成返回数据之后-设定订单购买流程结束
    
    
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"GameSDK服务器操作完成了，这里进行结果处理.....");
            
                if (true)
                {
//                    [self removeReceipt];
                    //[self removeReceiptWithPlistPath:plistPath];
                    //[MBProgressHUD showSuccessMessage:@"支付成功"];
                    //self.isIapProcessFinished = YES;
                    
                    //[[SKPaymentQueue defaultQueue] finishTransaction: transaction];
                    
                    [self removeReceiptInLocalPlistFileWithFileName:receiptId];
                    
                    
                    
                }
                else
                {
                    //凭证无效
                    //[MBProgressHUD showErrorMessage:@"支付失败"];
                    //做你想做的
                   
                }
            });
}



//验证成功就从plist中移除凭证-整个文件夹
//-(void)removeReceipt{
//
//    NSFileManager *fileManager = [NSFileManager defaultManager];
//   //fileExistsAtPath Returns a Boolean value that indicates whether a file or directory exists at a specified path.
//    if ([fileManager fileExistsAtPath:[SandBoxHelper iapReceiptPath]]) {
//
//        [fileManager removeItemAtPath:[SandBoxHelper iapReceiptPath] error:nil];
//
//    }
//}

//验证成功就从plist中移除凭证-指定文件
-(void)removeReceiptInLocalPlistFileWithFileName:(NSString *)receiptId{
    NSString *plistPath = [NSString stringWithFormat:@"%@/%@", [SandBoxHelper iapReceiptPath], receiptId];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:plistPath]) {
        NSLog(@"GameSDK检测到%@文件存在,准备删除...", plistPath);
        NSError* err = nil;
        [fileManager removeItemAtPath:plistPath error:&err];
        if(err == nil) {
            NSLog(@"GameSDK删除文件%@成功", plistPath);
        } else {
            NSLog(@"GameSDK删除文件%@失败,err=%@", plistPath, err.localizedDescription);
        }
    } else {
        NSLog(@"GameSDK检测到%@文件不存在...", plistPath);
    }
}


#pragma mark 错误信息反馈
- (void)failedWithErrorCode:(NSInteger)code error:(NSString *)error {

    if (self.delegate && [self.delegate respondsToSelector:@selector(failedWithErrorCode:andError:)]) {
        switch (code) {
            case IAP_FILEDCOED_APPLECODE:
                [self.delegate failedWithErrorCode:IAP_FILEDCOED_APPLECODE andError:error];
                break;

                case IAP_FILEDCOED_NORIGHT:
                [self.delegate failedWithErrorCode:IAP_FILEDCOED_NORIGHT andError:nil];
                break;

            case IAP_FILEDCOED_EMPTYGOODS:
                [self.delegate failedWithErrorCode:IAP_FILEDCOED_EMPTYGOODS andError:nil];
                break;

            case IAP_FILEDCOED_CANNOTGETINFORMATION:
                 [self.delegate failedWithErrorCode:IAP_FILEDCOED_CANNOTGETINFORMATION andError:nil];
                break;

            case IAP_FILEDCOED_BUYFILED:
                 [self.delegate failedWithErrorCode:IAP_FILEDCOED_BUYFILED andError:nil];
                break;

            case IAP_FILEDCOED_USERCANCEL:
                 [self.delegate failedWithErrorCode:IAP_FILEDCOED_USERCANCEL andError:nil];
                break;

            default:
                break;
        }
    }
}

#pragma mark md5加密算法
- (NSString *)md5HexDigest:(NSString *)knownStr
{
    const char *original_str = [knownStr UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(original_str, (CC_LONG)strlen(original_str), result);
    NSMutableString *hash = [NSMutableString string];
    for (int i = 0; i < 16; i++)
        [hash appendFormat:@"%02X", result[i]];
    return [hash lowercaseString];
}

//dictionary to json string
- (NSString*) apjDictionaryToJsonString:(NSMutableDictionary *)dic
{
    NSError *parseError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dic options:0 error:&parseError];
    if(parseError != nil) {
        return nil;
    }
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

//json string to dictionary
- (NSMutableDictionary *) apjJsonStringToDictionary:(NSString *)jsonString
{
    if (jsonString == nil) { return nil; }
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err;
    NSMutableDictionary *dic = [NSJSONSerialization JSONObjectWithData:jsonData
                                                        options:NSJSONReadingMutableContainers
                                                          error:&err];
    if(err != nil){
        return nil;
    }
    return dic;
}

-(BOOL)isNullDictionary:(NSMutableDictionary *)dic{
    if (dic != nil && dic.count != 0 && ![dic isKindOfClass:[NSNull class]] ){
        return NO;
    }else{
        return YES;
    }
}

@end
