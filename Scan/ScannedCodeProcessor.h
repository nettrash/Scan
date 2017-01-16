//
//  ScannedCodeProcessor.h
//  Scan
//
//  Created by Иван Алексеев on 11.12.16.
//  Copyright © 2016 NETTRASH. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum { atVCard, atPayment, atURL, atGoods, atUnknown } ScanResultActionType;

@interface ScannedCodeProcessor : NSObject

- (void)initWithScanType:(NSString *)codeType andText:(NSString *)text;

@property (nonatomic, retain) NSString *codeType;
@property (nonatomic, retain) NSString *codeValue;
@property (nonatomic) ScanResultActionType actionType;
@property (nonatomic, retain) NSURL *Url;
@property (nonatomic, retain) NSMutableArray *Fields;

@end
