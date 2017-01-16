//
//  PushSegue.m
//  Scan
//
//  Created by Иван Алексеев on 18.12.16.
//  Copyright © 2016 NETTRASH. All rights reserved.
//

#import "PushSegue.h"

@implementation PushSegue

- (void)perform {
    [[[self sourceViewController] navigationController] pushViewController:[self destinationViewController] animated:YES];
}

@end
