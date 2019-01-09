//
//  ReceiptViewController.h
//  Scan
//
//  Created by Иван Алексеев on 29/10/2018.
//  Copyright © 2018 NETTRASH. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ReceiptViewController : UITableViewController <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, retain) NSString *CodeText;

@end
