//
//  CryptoCurrency.m
//  Scan
//
//  Created by Иван Алексеев on 22.08.2018.
//  Copyright © 2018 NETTRASH. All rights reserved.
//

#import "CryptoCurrency.h"
#import <CommonCrypto/CommonCrypto.h>

@interface CryptoCurrency ()

@end

@implementation CryptoCurrency

-(NSData *)decodeBase58:(const char *)addy bytes:(unsigned char *)bytes {
	static const char *base58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
	
	int i, j, c;
	const char *p;
	memset(bytes, 0, 25);
	
	for (i = 0; addy[i]; i++) {
		if (!(p = strchr(base58, addy[i]))) return nil;
		
		c = p - base58;
		for (j = 25; j--; ) {
			c += 58 * bytes[j];
			bytes[j] = c % 256;
			c /= 256;
		}
		if (c) return nil;
	}
	return [NSData dataWithBytes:(const void *)bytes length:25];
}

-(BOOL)verifyAddress:(NSString *)addressString {
	unsigned char bytes[32];
	NSData *unbased = [self decodeBase58:[addressString cStringUsingEncoding:NSASCIIStringEncoding] bytes:bytes];
	if (unbased != nil) {
		NSData *doubleSha = [self sha256:[unbased subdataWithRange:NSMakeRange(0, 21)]];
		NSData *first4 = [doubleSha subdataWithRange:NSMakeRange(0, 4)];
		NSData *last4 = [unbased subdataWithRange:NSMakeRange([unbased length]-4,4)];
		return [first4 isEqualToData:last4];
	}
	return false;
}

-(BOOL)isBTC:(NSString *)addressString {
	return [self verifyAddress:addressString] && ([addressString hasPrefix:@"1"] || [addressString hasPrefix:@"3"]);
}

-(BOOL)isBIO:(NSString *)addressString {
	return [self verifyAddress:addressString] && [addressString hasPrefix:@"B"];
}

-(BOOL)isSIB:(NSString *)addressString {
	return [self verifyAddress:addressString] && ([addressString hasPrefix:@"S"]);
}

- (NSData *)sha256:(NSData *)data {
	uint8_t digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
	
	NSData *firstHash = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
	
	uint8_t digest2[CC_SHA256_DIGEST_LENGTH];
	
	if (CC_SHA256(firstHash.bytes, (CC_LONG)firstHash.length, digest2)) {
		return [NSData dataWithBytes:digest2 length:CC_SHA256_DIGEST_LENGTH];
	}
	return nil;
}

@end
