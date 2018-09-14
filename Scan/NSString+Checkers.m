//
//  NSString+Checkers.m
//  Scan
//
//  Created by Иван Алексеев on 11.12.16.
//  Copyright © 2016 NETTRASH. All rights reserved.
//

#import "NSString+Checkers.h"
#import "NSString+RegEx.h"
#import "CryptoCurrency.h"

@implementation NSString (Checkers)

- (BOOL)isVCARD
{
    return ([self hasPrefix:@"BEGIN:VCARD"] && [self hasSuffix:@"END:VCARD"]);
}

- (BOOL)isURL
{
    NSDataDetector *detector = [[NSDataDetector alloc] initWithTypes:NSTextCheckingTypeLink error:nil];
    NSArray *matches = [detector matchesInString:self options:0 range:NSMakeRange(0, [self length])];
    for (NSTextCheckingResult *match in matches) {
        if ([match resultType] == NSTextCheckingTypeLink) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)isHTML
{
    return
    (
     ([self rangeOfString:@"<a" options:NSCaseInsensitiveSearch].location != NSNotFound) ||
     ([self rangeOfString:@"<b" options:NSCaseInsensitiveSearch].location != NSNotFound) ||
     ([self rangeOfString:@"<h" options:NSCaseInsensitiveSearch].location != NSNotFound) ||
     ([self rangeOfString:@"<i" options:NSCaseInsensitiveSearch].location != NSNotFound)
     ) &&
    (
     ([self rangeOfString:@"</" options:NSCaseInsensitiveSearch].location != NSNotFound) ||
     ([self rangeOfString:@"/>" options:NSCaseInsensitiveSearch].location != NSNotFound)
     );
}

- (NSString *)HTMLWithSystemFont
{
    return [NSString stringWithFormat:@"<font face=\"Gotham, Helvetica Neue, Helvetica, Arial, sans-serif\" size=\"+4\">%@</font>", self];
}

- (BOOL)isPossibleMoscowGKU
{
    return self && self != nil && [self length] == 28 && [self checkFormat:@"^\\d{28}$"];
}

- (BOOL)isPossibleMGTS
{
    return self && self != nil && [self length] == 21 && [self checkFormat:@"^\\d{21}$"];
}

- (BOOL)isPossibleMosenergosbut
{
    return self && self != nil && [self length] == 25 && [self checkFormat:@"^\\d{25}$"];
}

- (BOOL)isPossibleGIBDD
{
    return self && self != nil && [self length] == 20 && [self checkFormat:@"^\\d{20}$"];
}

- (BOOL)isST00011
{
    return [self hasPrefix:@"ST00011|"];
}

- (BOOL)isST00012
{
    return [self hasPrefix:@"ST00012|"];
}

- (BOOL)isPD4Nalog
{
    return [self hasPrefix:@"PD4Nalog|"];
}

- (BOOL)isBTC {
	CryptoCurrency *cc = [[CryptoCurrency alloc] init];
	return [cc isBTC:self];
}

- (BOOL)isBIO {
	CryptoCurrency *cc = [[CryptoCurrency alloc] init];
	return [cc isBIO:self];

}

- (BOOL)isSIB {
	CryptoCurrency *cc = [[CryptoCurrency alloc] init];
	return [cc isSIB:self];
}

- (BOOL)isFiscalDocumentLink {
	return [self containsString:@"t="] && [self containsString:@"s="] && [self containsString:@"fn="] && [self containsString:@"i="] && [self containsString:@"fp="] && [self containsString:@"n="];
}

@end
