//
//  WalletViewController.m
//  Scan
//
//  Created by Иван Алексеев on 05.02.17.
//  Copyright © 2017 NETTRASH. All rights reserved.
//

#import "WalletViewController.h"

@interface WalletViewController ()

@property (nonatomic, retain) IBOutlet UILabel *lblCodeValue;
@property (nonatomic, retain) IBOutlet UITextField *tfCodeLabel;
@property (nonatomic, retain) IBOutlet UISegmentedControl *scCodeType;

@end

@implementation WalletViewController

@synthesize CodeProcessor, lblCodeValue, tfCodeLabel;

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationItem setTitle:NSLocalizedString(@"AddToWallet", @"AddToWallet")];    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addToWallet:)];
    if (self.navigationItem.backBarButtonItem == nil) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(done:)];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [self.lblCodeValue setText:self.CodeProcessor.codeValue];
    [self.tfCodeLabel setText:NSLocalizedString(@"Some Shop Card", @"Some Shop Card")];
}

- (IBAction)done:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)addToWallet:(id)sender {
    NSString *codeType = @"";
    switch (self.scCodeType.selectedSegmentIndex) {
        case 0: //Code128
            codeType = @"PKBarcodeFormatCode128";
            break;
        case 1: //QR
            codeType = @"PKBarcodeFormatQR";
            break;
        case 2: //PDF
            codeType = @"PKBarcodeFormatPDF417";
            break;
        case 3: //Aztec
            codeType = @"PKBarcodeFormatAztec";
            break;
            
        default:
            break;
    }
    NSCharacterSet *chars = [NSCharacterSet characterSetWithCharactersInString:@"!*'();:@&=+$,/?%#[]0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"];
    NSURL *passURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://nettrash.ru/Main/Pass?Code=%@&Label=%@&Description=%@&CodeType=%@", [self.CodeProcessor.codeValue stringByAddingPercentEncodingWithAllowedCharacters:chars], [self.tfCodeLabel.text stringByAddingPercentEncodingWithAllowedCharacters:chars], [NSLocalizedString(@"WalletCardDescription", @"WalletCardDescription") stringByAddingPercentEncodingWithAllowedCharacters:chars], codeType]];
    NSError *error;
    NSData *data = [NSData dataWithContentsOfURL:passURL options:NSDataReadingUncached error:&error];
    PKPass *pass = [[PKPass alloc] initWithData:data error:&error];
    PKPassLibrary* passLib = [[PKPassLibrary alloc] init];
    if (![passLib containsPass:pass]) {
        PKAddPassesViewController *apvc = [[PKAddPassesViewController alloc] initWithPass:pass];
        apvc.delegate = self;
        [self presentViewController:apvc animated:YES completion:nil];
    }
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

#pragma mark - 

-(void)addPassesViewControllerDidFinish:(PKAddPassesViewController *)controller {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
