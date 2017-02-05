//
//  TextViewController.m
//  Scan
//
//  Created by Иван Алексеев on 18.12.16.
//  Copyright © 2016 NETTRASH. All rights reserved.
//

#import "TextViewController.h"

@interface TextViewController ()

@property (nonatomic, retain) IBOutlet UITextView *tvText;

@end

@implementation TextViewController

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
    [self.tvText setText:self.CodeText];
}

- (IBAction)done:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)share:(id)sender {
    NSArray *objectsToShare = @[self.CodeText];
    
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:objectsToShare applicationActivities:nil];
    
    [self presentViewController:activity animated:YES completion:nil];
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
