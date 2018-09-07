//
//  ViewController.m
//  Scan
//
//  Created by Иван Алексеев on 06.12.16.
//  Copyright © 2016 NETTRASH. All rights reserved.
//

#import "ViewController.h"
#import "ScannedCodeProcessor.h"
#import "WebViewController.h"
#import "CodeCardViewController.h"
#import "TextViewController.h"
#import "AppDelegate.h"
#import "WalletViewController.h"
#include "TargetConditionals.h"

@interface ViewController ()

@property (nonatomic) BOOL configured;
@property (nonatomic, retain) AVCaptureDevice *device;
@property (nonatomic, retain) AVCaptureDeviceInput *input;
@property (nonatomic, retain) AVCaptureSession *session;
@property (nonatomic, retain) AVCaptureMetadataOutput *output;
@property (nonatomic, retain) AVCaptureVideoPreviewLayer *preview;

@property (nonatomic, retain) IBOutlet UILabel *lblTitle;
@property (nonatomic, retain) IBOutlet UIImageView *ivFlash;
@property (nonatomic, retain) IBOutlet UITextView *lblInfo;
@property (nonatomic, retain) IBOutlet UIButton *btnInfo;

@property (nonatomic, retain) IBOutlet UIImageView *ivMode;
@property (nonatomic, retain) IBOutlet UIPickerView *pvMode;

@property (nonatomic, retain) IBOutlet UIImageView *ivModeIcon;

@end

@implementation ViewController

@synthesize configured, device, input, session, output, preview, lblTitle, lblInfo, btnInfo, ivMode, pvMode, ivModeIcon;

- (void)viewDidLoad {
    [super viewDidLoad];
    self.configured = NO;
    [self.lblInfo setHidden:YES];
    [self.pvMode setHidden:YES];
    [self.lblInfo setText:NSLocalizedString(@"InfoText", @"InfoText")];
    [self.ivModeIcon setImage:[UIImage imageNamed:@"SimpleMode.png"]];
	[self.pvMode setValue:[UIColor whiteColor] forKey:@"textColor"];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
	[self.pvMode setValue:[UIColor whiteColor] forKey:@"textColor"];
    [self refreshTorchStatus];
    [self beginWork];
}

- (void)beginWork {
#if !(TARGET_OS_SIMULATOR)
    switch([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo])
    {
        case AVAuthorizationStatusNotDetermined: {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                if (granted) {
                    [self setupScanner];
                    [self performSelector:@selector(startScanning) withObject:nil afterDelay:.5];
                } else {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Camera access", @"Camera access") message:NSLocalizedString(@"Camera access denied. Grant access to camera in iPhone Settings.", @"Camera access denied. Grant access to camera in iPhone Settings.") preferredStyle:UIAlertControllerStyleActionSheet];
                    [self presentViewController:alert animated:YES completion:nil];
                }
            }];
            break;
        }
        case AVAuthorizationStatusRestricted:
        case AVAuthorizationStatusDenied: {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Camera access", @"Camera access") message:NSLocalizedString(@"Camera access denied. Grant access to camera in iPhone Settings.", @"Camera access denied. Grant access to camera in iPhone Settings.") preferredStyle:UIAlertControllerStyleActionSheet];
            [self presentViewController:alert animated:YES completion:nil];
            break;
        }
        case AVAuthorizationStatusAuthorized: {
            [self setupScanner];
            [self performSelector:@selector(startScanning) withObject:nil afterDelay:.5];
            break;
        }
            
    }
#else
    self.configured = YES;
#endif
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotate
{
    return YES;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    return UIInterfaceOrientationPortrait;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
	[coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context)
	 {
		 UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
		 AVCaptureConnection *con = self.preview.connection;
		 self.preview.frame = CGRectMake(0, 0, size.width, size.height);
		 switch (orientation) {
			 case UIInterfaceOrientationLandscapeRight:
				 con.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
				 break;
			 case UIInterfaceOrientationLandscapeLeft:
				 con.videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
				 break;
			 case UIInterfaceOrientationPortrait:
				 con.videoOrientation = AVCaptureVideoOrientationPortrait;
				 break;
			 case UIInterfaceOrientationPortraitUpsideDown:
				 con.videoOrientation = AVCaptureVideoOrientationPortraitUpsideDown;
				 break;
			 default:
				 break;
		 }
	 } completion:^(id<UIViewControllerTransitionCoordinatorContext> context)
	 {
		 
	 }];
	
	[super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

- (void)setupScanner
{
#if !(TARGET_OS_SIMULATOR)
    if (self.configured) return;
    
    self.device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    self.input = [AVCaptureDeviceInput deviceInputWithDevice:self.device error:nil];
    self.session = [[AVCaptureSession alloc] init];
    self.session.sessionPreset = AVCaptureSessionPresetPhoto;
	
    self.output = [[AVCaptureMetadataOutput alloc] init];
    [self.session addOutput:self.output];
    [self.session addInput:self.input];
    
    [self.output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    self.output.metadataObjectTypes = @[AVMetadataObjectTypeUPCECode,
                                        AVMetadataObjectTypeCode39Code,
                                        AVMetadataObjectTypeCode39Mod43Code,
                                        AVMetadataObjectTypeEAN13Code,
                                        AVMetadataObjectTypeEAN8Code,
                                        AVMetadataObjectTypeCode93Code,
                                        AVMetadataObjectTypeCode128Code,
                                        AVMetadataObjectTypePDF417Code,
                                        AVMetadataObjectTypeQRCode,
                                        AVMetadataObjectTypeAztecCode];
	
	CGRect bounds = self.view.layer.bounds;
    self.preview = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    self.preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
	self.preview.bounds = bounds;
	self.preview.position = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
	self.preview.frame = self.view.frame;//CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height);
    
    AVCaptureConnection *con = self.preview.connection;
    
    con.videoOrientation = AVCaptureVideoOrientationPortrait;
    
    [self.view.layer insertSublayer:self.preview atIndex:0];
    
    [self.view bringSubviewToFront:self.ivFlash];
    [self.view bringSubviewToFront:self.lblTitle];
    [self.view bringSubviewToFront:self.lblInfo];
    [self.view bringSubviewToFront:self.btnInfo];
    [self.view bringSubviewToFront:self.pvMode];
    [self.view bringSubviewToFront:self.ivMode];
    
    [self.ivFlash setHidden:![self.device isTorchAvailable]];
    [self.ivFlash setHighlighted:[self.device torchMode] == AVCaptureTorchModeOn];
    
    self.configured = YES;
#endif
}

- (void)startScanning
{
    [self.session startRunning];
}

- (void)stopScanning
{
    [self.session stopRunning];
}

- (void)openURL:(NSURL *)url {
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)processResult:(AVMetadataMachineReadableCodeObject *)scanResult {
    /*
     EAN-13 - goods
     
     */
    NSLog(@"%@", [scanResult stringValue]);
    ScannedCodeProcessor *scp = [ScannedCodeProcessor alloc];
    [scp initWithScanType:scanResult.type andText:scanResult.stringValue];

    switch ([self.pvMode selectedRowInComponent:0]) {
        case 1:
            [self performSegueWithIdentifier:@"MWallet" sender:scp];
            return;
        case 2:
            [self performSegueWithIdentifier:@"Card" sender:scp];
            return;
        case 3:
            [self performSegueWithIdentifier:@"MText" sender:scp.codeValue];
            return;
            
        default:
            break;
    }

    switch (scp.actionType) {
        case atVCard: {
            [self actionVCard:scp.codeValue];
            break;
        }
        case atURL: {
            [self performSelector:@selector(openURL:) withObject:scp.Url afterDelay:.1];
            //[[UIApplication sharedApplication] openURL:scp.Url options:@{} completionHandler:nil];
            //[self performSegueWithIdentifier:@"MWeb" sender:scp.Url];
            break;
        }
        case atPayment: {
            [self performSegueWithIdentifier:@"Card" sender:scp];
            break;
        }
        case atGoods: {
            [self performSelector:@selector(openURL:) withObject:scp.Url afterDelay:.1];
            //[[UIApplication sharedApplication] openURL:scp.Url options:@{} completionHandler:nil];
            //[self performSegueWithIdentifier:@"MWeb" sender:scp.Url];
            break;
        }
        default:
            [self performSegueWithIdentifier:@"Card" sender:scp];
            break;
    }
}

- (void)actionVCard:(NSString *)vcardValue
{
    NSArray<CNContact *> *contacts = [CNContactVCardSerialization contactsWithData:[vcardValue dataUsingEncoding:NSUTF8StringEncoding] error:nil];
    CNContactViewController *cvc = [CNContactViewController viewControllerForNewContact:[contacts objectAtIndex:0]];
    cvc.allowsActions = YES;
    cvc.allowsEditing = YES;
    cvc.delegate = self;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:cvc];
    [self presentViewController:navigation animated:YES completion:nil];
}

- (IBAction)torchTap:(UITapGestureRecognizer *)sender {
    if (![self.device isTorchAvailable]) return;
    [self.device lockForConfiguration:nil];
    BOOL bHighlighted = NO;
    if ([self.device isTorchActive]) {
        [self.device setTorchMode:AVCaptureTorchModeOff];
        bHighlighted = NO;
    }
    else {
        [self.device setTorchMode:AVCaptureTorchModeOn];
        bHighlighted = YES;
    }
    [device unlockForConfiguration];
    [self.ivFlash setHighlighted:bHighlighted];
}

- (IBAction)modeTap:(UITapGestureRecognizer *)sender {
    [self.lblInfo setHidden:YES];
    BOOL bHighlighted = self.ivMode.highlighted;
    if (!bHighlighted) {
        [self.pvMode setHidden:NO];
		[self.pvMode setValue:[UIColor whiteColor] forKey:@"textColor"];
    } else {
        [self.pvMode setHidden:YES];
    }
    [self.ivMode setHighlighted:!bHighlighted];
}

- (void)refreshTorchStatus {
    if (![self.device isTorchAvailable]) return;
    [self.ivFlash setHighlighted:[self.device isTorchActive]];
}

- (IBAction)switchInfo:(id)sender {
    [self.pvMode setHidden:YES];
    [self.ivMode setHighlighted:NO];
    [self.lblInfo setHidden:!self.lblInfo.hidden];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [self.pvMode setHidden:YES];
    [self.ivMode setHighlighted:NO];
    [self.lblInfo setHidden:YES];
}

#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
    if ([segue.identifier isEqualToString:@"MWeb"]) {
        [(WebViewController *)[segue destinationViewController] setUrl:(NSURL *)sender];
    }
    if ([segue.identifier isEqualToString:@"MText"]) {
        [(TextViewController *)[(UINavigationController *)[segue destinationViewController] topViewController] setCodeText:(NSString *)sender];
    }
    if ([segue.identifier isEqualToString:@"MWallet"]) {
        [(WalletViewController *)[(UINavigationController *)[segue destinationViewController] topViewController] setCodeProcessor:(ScannedCodeProcessor *)sender];
    }
    if ([segue.identifier isEqualToString:@"Card"]) {
        [(CodeCardViewController *)[(UINavigationController *)[segue destinationViewController] topViewController] setCodeProcessor:(ScannedCodeProcessor *)sender];
    }
}

#pragma mark AVCaptureMetadataOutputObjectsDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects
       fromConnection:(AVCaptureConnection *)connection
{
    for(AVMetadataObject *current in metadataObjects) {
        if([current isKindOfClass:[AVMetadataMachineReadableCodeObject class]]) {
            [self stopScanning];
            AudioServicesPlayAlertSound(1000);
            [self.view drawRect:current.bounds];
            [self processResult:(AVMetadataMachineReadableCodeObject *)current];
        }
    }
}

#pragma mark - CNContactViewContractDelegate

- (void)contactViewController:(CNContactViewController *)viewController didCompleteWithContact:(nullable CNContact *)contact {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UIPickerViewDelegate

- (NSAttributedString *)pickerView:(UIPickerView *)pickerView attributedTitleForRow:(NSInteger)row forComponent:(NSInteger)component
{
	switch (row) {
		case 0:
			return [[NSAttributedString alloc] initWithString:NSLocalizedString(@"ModeSimple", @"ModeSimple") attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}];
		case 1:
			return [[NSAttributedString alloc] initWithString:NSLocalizedString(@"ModeWallet", @"ModeWallet") attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}];
		case 2:
			return [[NSAttributedString alloc] initWithString:NSLocalizedString(@"ModeAdv", @"ModeAdv") attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}];
		case 3:
			return [[NSAttributedString alloc] initWithString:NSLocalizedString(@"ModeText", @"ModeText") attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}];
		default:
			return [[NSAttributedString alloc] initWithString:@"" attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}];
	}
}

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component {
    switch (row) {
        case 0:
            [self.ivModeIcon setImage:[UIImage imageNamed:@"SimpleMode.png"]];
            break;
        case 1:
            [self.ivModeIcon setImage:[UIImage imageNamed:@"WalletMode.png"]];
            break;
        case 2:
            [self.ivModeIcon setImage:[UIImage imageNamed:@"AdvMode.png"]];
            break;
        case 3:
            [self.ivModeIcon setImage:[UIImage imageNamed:@"TextMode.png"]];
            break;
            
        default:
            break;
    }
}

#pragma mark - UIPickerViewDataSource

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 1;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return 4;
}

@end
