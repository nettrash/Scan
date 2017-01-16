//
//  WebViewController.h
//  Scan
//
//  Created by Иван Алексеев on 11.12.16.
//  Copyright © 2016 NETTRASH. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface WebViewController : UIViewController <UIWebViewDelegate>

@property (nonatomic, retain) NSURL *Url;

@end
