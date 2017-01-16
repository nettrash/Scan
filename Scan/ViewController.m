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

@interface ViewController ()

@property (nonatomic) BOOL configured;
@property (nonatomic, retain) AVCaptureDevice *device;
@property (nonatomic, retain) AVCaptureDeviceInput *input;
@property (nonatomic, retain) AVCaptureSession *session;
@property (nonatomic, retain) AVCaptureMetadataOutput *output;
@property (nonatomic, retain) AVCaptureVideoPreviewLayer *preview;

@property (nonatomic, retain) IBOutlet UILabel *lblTitle;
@property (nonatomic, retain) IBOutlet UIImageView *ivFlash;

@end

@implementation ViewController

@synthesize configured, device, input, session, output, preview, lblTitle;

- (void)viewDidLoad {
    [super viewDidLoad];
    self.configured = NO;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshTorchStatus];
    [self beginWork];
}

- (void)beginWork {
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

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
    AVCaptureConnection *con = self.preview.connection;
    switch (toInterfaceOrientation) {
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
}

- (void)setupScanner
{
    if (self.configured) return;
    
    self.device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    self.input = [AVCaptureDeviceInput deviceInputWithDevice:self.device error:nil];
    self.session = [[AVCaptureSession alloc] init];
    
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
    
    self.preview = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    self.preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.preview.frame = CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height);
    
    AVCaptureConnection *con = self.preview.connection;
    
    con.videoOrientation = AVCaptureVideoOrientationPortrait;
    
    [self.view.layer insertSublayer:self.preview atIndex:0];
    /*
    [self.view bringSubviewToFront:self.btnCancel];
    [self.view bringSubviewToFront:self.btnInfo];
    [self.view bringSubviewToFront:self.btnTorch];
    [self.view bringSubviewToFront:self.lblInfoText];
    
    self.btnTorch.hidden = !self.device.torchAvailable;*/
    
    [self.view bringSubviewToFront:self.lblTitle];
    
    [self.ivFlash setHidden:![self.device isTorchAvailable]];
    [self.ivFlash setHighlighted:[self.device torchMode] == AVCaptureTorchModeOn];
    
    self.configured = YES;
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

    if ([(AppDelegate *)[[UIApplication sharedApplication] delegate] modeTextOnly]) {
        [self performSegueWithIdentifier:@"MText" sender:scp.codeValue];
        return;
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

- (void)refreshTorchStatus {
    if (![self.device isTorchAvailable]) return;
    [self.ivFlash setHighlighted:[self.device isTorchActive]];
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
        [(TextViewController *)[segue destinationViewController] setCodeText:(NSString *)sender];
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

@end
