//
//  Field.m
//  Scan
//
//  Created by Иван Алексеев on 11.12.16.
//  Copyright © 2016 NETTRASH. All rights reserved.
//

#import "Field.h"

@implementation Field

@synthesize Name, Value;

+(Field *)fieldWithName:(NSString*) name andValue:(NSString *)value {
    Field *f = [[Field alloc] init];
    f.Name = name;
    f.Value = value;
    return f;
}

@end
