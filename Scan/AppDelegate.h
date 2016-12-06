//
//  AppDelegate.h
//  Scan
//
//  Created by Иван Алексеев on 06.12.16.
//  Copyright © 2016 NETTRASH. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (readonly, strong) NSPersistentContainer *persistentContainer;

- (void)saveContext;


@end

