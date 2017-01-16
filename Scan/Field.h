//
//  Field.h
//  Scan
//
//  Created by Иван Алексеев on 11.12.16.
//  Copyright © 2016 NETTRASH. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface Field : NSObject

@property (nonatomic, retain) NSString *Name;
@property (nonatomic, retain) NSString *Value;

+(Field *)fieldWithName:(NSString*) name andValue:(NSString *)value;

@end
