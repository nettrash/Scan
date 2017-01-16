//
//  SafariActivity.m
//  Scan
//
//  Created by Иван Алексеев on 11.12.16.
//  Copyright © 2016 NETTRASH. All rights reserved.
//

#import "SafariActivity.h"

@implementation SafariActivity
{
    NSURL *_URL;
}

- (NSString *)activityType
{
    return NSStringFromClass([self class]);
}

- (NSString *)activityTitle
{
    return NSLocalizedString(@"Open in Safari", @"Open in Safari");
}

- (UIImage *)activityImage
{
    if ([UIImage respondsToSelector:@selector(imageNamed:inBundle:compatibleWithTraitCollection:)]) {
        return [UIImage imageNamed:@"safari"];
    } else {
        return [UIImage imageNamed:@"safari-7"];
    }
}

- (BOOL)canPerformWithActivityItems:(NSArray *)activityItems
{
    for (id activityItem in activityItems) {
        if ([activityItem isKindOfClass:[NSURL class]] && [[UIApplication sharedApplication] canOpenURL:activityItem]) {
            return YES;
        }
    }
    
    return NO;
}

- (void)prepareWithActivityItems:(NSArray *)activityItems
{
    for (id activityItem in activityItems) {
        if ([activityItem isKindOfClass:[NSURL class]]) {
            _URL = activityItem;
        }
    }
}

- (void)performActivity
{
    NSDictionary<NSString *, id> *o = [[NSDictionary<NSString *, id> alloc] init];
    [[UIApplication sharedApplication] openURL:_URL options:o completionHandler:nil];
    [self activityDidFinish:YES];
}
@end
