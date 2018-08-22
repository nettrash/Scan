//
//  CryptoCurrency.h
//  Scan
//
//  Created by Иван Алексеев on 22.08.2018.
//  Copyright © 2018 NETTRASH. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface CryptoCurrency : NSObject

-(BOOL)verifyAddress:(NSString *)addressString;
-(BOOL)isBTC:(NSString *)addressString;
-(BOOL)isBIO:(NSString *)addressString;
-(BOOL)isSIB:(NSString *)addressString;

@end
