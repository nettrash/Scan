//
//  NSString+Checkers.h
//  Scan
//
//  Created by Иван Алексеев on 11.12.16.
//  Copyright © 2016 NETTRASH. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (Checkers)

- (BOOL)isVCARD;
- (BOOL)isURL;
- (BOOL)isHTML;
- (NSString *)HTMLWithSystemFont;
- (BOOL)isPossibleMoscowGKU;
- (BOOL)isPossibleMGTS;
- (BOOL)isPossibleMosenergosbut;
- (BOOL)isPossibleGIBDD;
- (BOOL)isST00011;
- (BOOL)isST00012;
- (BOOL)isPD4Nalog;
- (BOOL)isBTC;
- (BOOL)isBIO;
- (BOOL)isSIB;

@end
