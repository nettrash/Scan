//
//  WalletViewController.h
//  Scan
//
//  Created by Иван Алексеев on 05.02.17.
//  Copyright © 2017 NETTRASH. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <PassKit/PassKit.h>
#import "ScannedCodeProcessor.h"

@interface WalletViewController : UIViewController <PKAddPassesViewControllerDelegate>

@property (nonatomic, retain) ScannedCodeProcessor *CodeProcessor;

@end
