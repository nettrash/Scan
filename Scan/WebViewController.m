//
//  WebViewController.m
//  Scan
//
//  Created by Иван Алексеев on 11.12.16.
//  Copyright © 2016 NETTRASH. All rights reserved.
//

#import "WebViewController.h"
#import "SafariActivity.h"

@interface WebViewController ()

@property (nonatomic, retain) IBOutlet UIWebView *wvSearch;

@end

@implementation WebViewController

@synthesize wvSearch, Url;

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    if (self.Url)
        [self initWithUrl:self.Url];
}

- (IBAction)done:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)share:(id)sender {
    NSArray *objectsToShare = @[self.wvSearch.request.URL];
    
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:objectsToShare applicationActivities:@[[[SafariActivity alloc] init]]];
    
    [self presentViewController:activity animated:YES completion:nil];
}

#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}

- (void)initWithUrl:(NSURL *)url {
    NSURLRequest *rq = [NSURLRequest requestWithURL:url];
    [self.wvSearch loadRequest:rq];
}

#pragma mark - UIWebViewDelegate

- (void)webViewDidStartLoad:(UIWebView *)webView {
    [self.navigationItem setTitle:NSLocalizedString(@"Loading...", @"Loading...")];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    [self.navigationItem setTitle:[webView stringByEvaluatingJavaScriptFromString:@"document.title"]];
}

@end
