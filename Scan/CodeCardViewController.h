//
//  CodeCardViewController.h
//  Scan
//
//  Created by Иван Алексеев on 14.12.16.
//  Copyright © 2016 NETTRASH. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "ScannedCodeProcessor.h"

@interface CodeCardViewController : UITableViewController <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, retain) ScannedCodeProcessor *CodeProcessor;

@end
