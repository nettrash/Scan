//
//  ReceiptViewController.m
//  Scan
//
//  Created by Иван Алексеев on 29/10/2018.
//  Copyright © 2018 NETTRASH. All rights reserved.
//

#import "ReceiptViewController.h"

@interface ReceiptViewController ()

@end

@implementation ReceiptViewController

@synthesize CodeText;

- (void)viewDidLoad {
	[super viewDidLoad];
	[self.navigationItem setTitle:NSLocalizedString(@"CODE VALUE", @"CODE VALUE")];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
}

- (IBAction)done:(id)sender {
	[self dismissViewControllerAnimated:YES completion:nil];
}

/*
 #pragma mark - Navigation
 
 // In a storyboard-based application, you will often want to do a little preparation before navigation
 - (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
 // Get the new view controller using [segue destinationViewController].
 // Pass the selected object to the new view controller.
 }
 */

@end
