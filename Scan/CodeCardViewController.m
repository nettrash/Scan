//
//  CodeCardViewController.m
//  Scan
//
//  Created by Иван Алексеев on 14.12.16.
//  Copyright © 2016 NETTRASH. All rights reserved.
//

#import "CodeCardViewController.h"
#import "Field.h"
#import "WebViewController.h"
#import "TextViewController.h"
#import "WalletViewController.h"
#import "ReceiptViewController.h"

@interface CodeCardViewController ()

@property (nonatomic, retain) IBOutlet UIView *vWait;
@property (nonatomic, retain) IBOutlet UIActivityIndicatorView *aiWait;

@end

@implementation CodeCardViewController

@synthesize CodeProcessor;

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.navigationItem.title = NSLocalizedString(@"CODE CARD", @"CODE CARD");

	self.vWait = [[UIView alloc] initWithFrame:self.tableView.frame];
	self.vWait.hidden = YES;
	self.vWait.backgroundColor = [UIColor blackColor];
	self.vWait.alpha = .8;
	self.aiWait = [[UIActivityIndicatorView alloc] init];
	[self.aiWait setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhiteLarge];
	[self.vWait addSubview:self.aiWait];
	[self.aiWait startAnimating];
	[self.view addSubview:self.vWait];
	[self.view bringSubviewToFront:self.vWait];
}

- (void)viewWillAppear:(BOOL)animated {
	self.vWait.frame = CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height);
	self.aiWait.frame = CGRectMake(self.view.frame.size.width/2 - 16, self.view.frame.size.height/2 - 16, 32, 32);
	[super viewWillAppear:animated];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (IBAction)done:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"Web"]) {
        [(WebViewController *)[segue destinationViewController] setUrl:(NSURL *)sender];
    }
	if ([segue.identifier isEqualToString:@"Text"]) {
		[(TextViewController *)[segue destinationViewController] setCodeText:(NSString *)sender];
	}
	if ([segue.identifier isEqualToString:@"Receipt"]) {
		[(ReceiptViewController *)[segue destinationViewController] setCodeText:(NSString *)sender];
	}
    if ([segue.identifier isEqualToString:@"Wallet"]) {
        [(WalletViewController *)[segue destinationViewController] setCodeProcessor:(ScannedCodeProcessor *)sender];
    }
}

#pragma mark UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    switch (indexPath.section) {
        case 0:
            return;
            
        case 1:
            switch (self.CodeProcessor.actionType) {
				case atPayment:
					return;
				case atFiscalDocumentLink:
					return;

                default:
                    break;
            }
            
        case 2:
            break;
            
        default:
            return;
    }
    
    switch (self.CodeProcessor.actionType) {
		case atPayment: {
			// Goto web tinkoff.ru
			[[UIApplication sharedApplication] openURL:self.CodeProcessor.Url options:@{} completionHandler:nil];
			//[self performSegueWithIdentifier:@"Web" sender:url];
			break;
		}
		case atFiscalDocumentLink: {
			switch (indexPath.row) {
				case 0: //Check
					switch ([self checkReceiptExists]) {
						case found: {
							NSLog(@"Exists");
							UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Check Receipt", @"Check Receipt") message:NSLocalizedString(@"Receipt exists", @"Receipt exists") preferredStyle:UIAlertControllerStyleActionSheet];
							
							UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
																				  handler:^(UIAlertAction * action) {}];
							
							[alert addAction:defaultAction];
							
							[self presentViewController:alert animated:YES completion:nil];
							break;
						}
						case notfound: {
							NSLog(@"Not Exists");
							UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Check Receipt", @"Check Receipt") message:NSLocalizedString(@"Receipt not exists", @"Receipt not exists") preferredStyle:UIAlertControllerStyleActionSheet];
							
							UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
																				  handler:^(UIAlertAction * action) {}];
							
							[alert addAction:defaultAction];
							
							[self presentViewController:alert animated:YES completion:nil];
							break;
						}
						case finderror: {
							NSLog(@"Not Exists");
							UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Check Receipt", @"Check Receipt") message:NSLocalizedString(@"Receipt find error", @"Receipt find error") preferredStyle:UIAlertControllerStyleActionSheet];
							
							UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
																				  handler:^(UIAlertAction * action) {}];
							
							[alert addAction:defaultAction];
							
							[self presentViewController:alert animated:YES completion:nil];
							break;
						}
						default:
							break;
					}
					break;
				case 1: //Get
					switch ([self checkReceiptExists]) {
						case found: {
							NSLog(@"Exists");
							[self performSelectorOnMainThread:@selector(showWait:) withObject:nil waitUntilDone:YES];
							[self performSelectorOnMainThread:@selector(getReceipt:) withObject:nil waitUntilDone:NO];
							break;
						}
						case notfound: {
							NSLog(@"Not Exists");
							UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Check Receipt", @"Check Receipt") message:NSLocalizedString(@"Receipt not exists", @"Receipt not exists") preferredStyle:UIAlertControllerStyleActionSheet];
							
							UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
																				  handler:^(UIAlertAction * action) {}];
							
							[alert addAction:defaultAction];
							
							[self presentViewController:alert animated:YES completion:nil];
							break;
						}
						case finderror: {
							NSLog(@"Not Exists");
							UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Check Receipt", @"Check Receipt") message:NSLocalizedString(@"Receipt find error", @"Receipt find error") preferredStyle:UIAlertControllerStyleActionSheet];
							
							UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
																				  handler:^(UIAlertAction * action) {}];
							
							[alert addAction:defaultAction];
							
							[self presentViewController:alert animated:YES completion:nil];
							break;
						}
						default:
							break;
					}
					break;

				default:
					break;
			}
			break;
		}
        case atURL: {
            switch (indexPath.row) {
                case 0: {
                    // Goto web
                    [[UIApplication sharedApplication] openURL:self.CodeProcessor.Url options:@{} completionHandler:nil];
                    //[self performSegueWithIdentifier:@"Web" sender:self.CodeProcessor.Url];
                    break;
                }
                case 1: {
                    //Goto text view
                    [self performSegueWithIdentifier:@"Text" sender:self.CodeProcessor.codeValue];
                    break;
                }
                default:
                    break;
            }
            break;
        }
        case atGoods: {
            switch (indexPath.row) {
                case 0:
                    //Goto web for search
                    [[UIApplication sharedApplication] openURL:self.CodeProcessor.Url options:@{} completionHandler:nil];
                    //[self performSegueWithIdentifier:@"Web" sender:self.CodeProcessor.Url];
                    break;
                case 1: {
                    //Ozon.ru
                    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://google.com/search?ie=UTF-8&hl=ru&q=site:ozon.ru%%20%@", self.CodeProcessor.codeValue]];
                    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
                    //[self performSegueWithIdentifier:@"Web" sender:url];
                    break;
                }
                case 2: {
                    //Amazon.com
                    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://google.com/search?ie=UTF-8&hl=ru&q=site:amazon.com%%20%@", self.CodeProcessor.codeValue]];
                    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
                    //[self performSegueWithIdentifier:@"Web" sender:url];
                    break;
                }
                case 3: {
                    //mvideo.ru
                    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://google.com/search?ie=UTF-8&hl=ru&q=site:mvideo.ru%%20%@", self.CodeProcessor.codeValue]];
                    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
                    //[self performSegueWithIdentifier:@"Web" sender:url];
                    break;
                }
                case 4: {
                    //Goto text view
                    [self performSegueWithIdentifier:@"Text" sender:self.CodeProcessor.codeValue];
                    break;
                }
                default:
                    break;
            }
            break;
        }
		case atVCard: {
			break;
		}
        case atUnknown: {
            switch (indexPath.row) {
                case 0:
                    //Goto web for search
                    [[UIApplication sharedApplication] openURL:self.CodeProcessor.Url options:@{} completionHandler:nil];
                    //[self performSegueWithIdentifier:@"Web" sender:self.CodeProcessor.Url];
                    break;
                case 1:
                    //Goto text view
                    [self performSegueWithIdentifier:@"Text" sender:self.CodeProcessor.codeValue];
                    break;
                case 2:
                    //Add to Wallet
                     [self performSegueWithIdentifier:@"Wallet" sender:self.CodeProcessor];
                    break;
                default:
                    break;
            }
            break;
        }
        default:
            break;
    }
}

- (void)showWait:(id)sender {
	self.vWait.hidden = NO;
	[self.view bringSubviewToFront:self.vWait];
}

- (void)hideWait:(id)sender {
	self.vWait.hidden = YES;
}

- (void)getReceipt:(id)sender {
	sleep(1);
	NSString *receipt = [self receiptGet:0];
	[self performSelectorOnMainThread:@selector(hideWait:) withObject:nil waitUntilDone:NO];
	//[self performSegueWithIdentifier:@"Receipt" sender:receipt];
	[self performSegueWithIdentifier:@"Text" sender:receipt];
}

#pragma mark UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.CodeProcessor.actionType == atPayment || self.CodeProcessor.actionType == atFiscalDocumentLink)
        return 3;
    return 2;
}

- (NSInteger)actionRows {
    switch (self.CodeProcessor.actionType) {
		case atPayment:
			return 1;
		case atFiscalDocumentLink:
			return 2;
        case atURL:
            return 2;
        case atGoods:
            return 5;
        case atVCard:
            return 0;
        case atUnknown:
            return 3;
        default:
            return 0;
    }
}

- (UITableViewCell *)actionCell:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;
    switch (self.CodeProcessor.actionType) {
        case atPayment: {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ActionCell"];
            [cell.textLabel setText:NSLocalizedString(@"Pay", @"Pay")];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;
        }
		case atFiscalDocumentLink: {
			switch (indexPath.row) {
				case 0: {
					cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ActionCell"];
					[cell.textLabel setText:NSLocalizedString(@"CheckReceiptExists", @"CheckReceiptExists")];
					cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
					break;
				}
				case 1: {
					cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ActionCell"];
					[cell.textLabel setText:NSLocalizedString(@"GetReceipt", @"GetReceipt")];
					cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
					break;
				}
			}
			break;
		}
        case atURL: {
            switch (indexPath.row) {
                case 0: {
                    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ActionCell"];
                    [cell.textLabel setText:NSLocalizedString(@"Open", @"Open")];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                }
                case 1: {
                    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ActionCell"];
                    [cell.textLabel setText:NSLocalizedString(@"View", @"View")];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                }
            }
        }
        case atGoods: {
            switch (indexPath.row) {
                case 0:
                    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ActionCell"];
                    [cell.textLabel setText:NSLocalizedString(@"Search", @"Search")];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 1:
                    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ActionCell"];
                    [cell.textLabel setText:NSLocalizedString(@"Ozon.ru", @"Ozon.ru")];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 2:
                    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ActionCell"];
                    [cell.textLabel setText:NSLocalizedString(@"Amazon.com", @"Amazon.com")];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 3:
                    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ActionCell"];
                    [cell.textLabel setText:NSLocalizedString(@"mvideo.ru", @"mvideo.ru")];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 4:
                    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ActionCell"];
                    [cell.textLabel setText:NSLocalizedString(@"View", @"View")];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                default:
                    break;
            }
            break;
        }
		case atVCard: {
			break;
		}
        case atUnknown: {
            switch (indexPath.row) {
                case 0:
                    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ActionCell"];
                    [cell.textLabel setText:NSLocalizedString(@"Search", @"Search")];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 1:
                    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ActionCell"];
                    [cell.textLabel setText:NSLocalizedString(@"View", @"View")];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                case 2:
                    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"ActionCell"];
                    [cell.textLabel setText:NSLocalizedString(@"Wallet", @"Wallet")];
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    break;
                default:
                    break;
            }
            break;
        }
        default:
            break;
    }
    return cell;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return 3;

        case 1:
            switch (self.CodeProcessor.actionType) {
				case atPayment:
					return [self.CodeProcessor.Fields count];
				case atFiscalDocumentLink:
					return [self.CodeProcessor.Fields count];

                default:
                    return [self actionRows];
            }
        
        case 2:
            return [self actionRows];
            
        default:
            return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"CodeCardCell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell== nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
    }

    switch (indexPath.section) {
        case 0: {
            switch (indexPath.row) {
                case 0:
                    [cell.detailTextLabel setText:NSLocalizedString(@"Type", @"Type")];
                    [cell.textLabel setText:self.CodeProcessor.codeType];
                    break;
                    
                case 1:
                    [cell.detailTextLabel setText:NSLocalizedString(@"Value Type", @"Value Type")];
                    switch (self.CodeProcessor.actionType) {
                        case atVCard:
                            [cell.textLabel setText:NSLocalizedString(@"VCard", @"VCard")];
                            break;
							
						case atPayment:
							[cell.textLabel setText:NSLocalizedString(@"Payment", @"Payment")];
							break;
							
						case atFiscalDocumentLink:
							[cell.textLabel setText:NSLocalizedString(@"FiscalDocumentLink", @"FiscalDocumentLink")];
							break;

                        case atURL:
                            [cell.textLabel setText:NSLocalizedString(@"URL", @"URL")];
                            break;
                            
                        case atGoods:
                            [cell.textLabel setText:NSLocalizedString(@"Goods", @"Goods")];
                            break;
                            
                        default:
                            [cell.textLabel setText:NSLocalizedString(@"Unknown", @"Unknown")];
                            break;
                    }
                    [cell.detailTextLabel setNumberOfLines:1];
                    [cell.textLabel setNumberOfLines:1];
                    break;
                    
                case 2:
                    [cell.detailTextLabel setText:NSLocalizedString(@"Value", @"Value")];
                    [cell.textLabel setText:self.CodeProcessor.codeValue];
                    break;
                default:
                    break;
            }
            [cell.textLabel setTextColor:[UIColor darkGrayColor]];
            [cell.detailTextLabel setTextColor:[UIColor lightGrayColor]];
            break;
        }
        case 1: {
            switch (self.CodeProcessor.actionType) {
				case atPayment: {
					Field *f = (Field *)[self.CodeProcessor.Fields objectAtIndex:indexPath.row];
					[cell.detailTextLabel setText:[f Name]];
					[cell.textLabel setText:[f Value]];
					break;
				}
				case atFiscalDocumentLink: {
					Field *f = (Field *)[self.CodeProcessor.Fields objectAtIndex:indexPath.row];
					[cell.detailTextLabel setText:[f Name]];
					[cell.textLabel setText:[f Value]];
					break;
				}
                default: {
                    cell = [self actionCell:indexPath];
                    break;
                }
            }
            [cell.textLabel setTextColor:[UIColor darkGrayColor]];
            [cell.detailTextLabel setTextColor:[UIColor lightGrayColor]];
            break;
        }
        case 2: {
            cell = [self actionCell:indexPath];
            [cell.textLabel setTextColor:[UIColor darkGrayColor]];
            [cell.detailTextLabel setTextColor:[UIColor lightGrayColor]];
            break;
        }
        default:
            break;
    }
	[cell setBackgroundColor:[UIColor blackColor]];
	[cell.textLabel setTextColor:[UIColor colorWithRed:238.0/255.0 green:238.0/255.0 blue:238.0/255.0 alpha:1]];
	[cell.detailTextLabel setTextColor:[UIColor colorWithRed:238.0/255.0 green:238.0/255.0 blue:238.0/255.0 alpha:1]];
    return cell;
    
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return NSLocalizedString(@"Code Info", @"Code Info");
        case 1:
            switch (self.CodeProcessor.actionType) {
				case atPayment:
					return NSLocalizedString(@"Payment fields", @"Payment fields");
				case atFiscalDocumentLink:
					return NSLocalizedString(@"Fiscal Document fields", @"Fiscal Document fields");
                default:
                    return NSLocalizedString(@"Actions", @"Actions");
            }
        case 2:
            return NSLocalizedString(@"Actions", @"Actions");
        default:
            return @"";
    }
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"";
}

#pragma mark Receipts

- (ReceiptFindResultType)checkReceiptExists {
	NSString *t = @"";
	NSString *s = @"";
	NSString *fn = @"";
	NSString *i = @"";
	NSString *fp = @"";
	NSString *n = @"";
	
	for (NSString *param in [self.CodeProcessor.codeValue componentsSeparatedByString:@"&"]) {
		NSArray *elts = [param componentsSeparatedByString:@"="];
		if([elts count] < 2) continue;
		NSString *paramName = [[elts firstObject] lowercaseString];
		NSString *paramValue = [elts lastObject];
		if ([[paramName lowercaseString] isEqualToString:@"t"]) {
			NSString *year = [paramValue substringWithRange:NSMakeRange(0, 4)];
			NSString *month = [paramValue substringWithRange:NSMakeRange(4, 2)];
			NSString *day = [paramValue substringWithRange:NSMakeRange(6, 2)];
			NSString *hours = [paramValue substringWithRange:NSMakeRange(9, 2)];
			NSString *minutes = [paramValue substringWithRange:NSMakeRange(11, 2)];
			t = [NSString stringWithFormat:@"%@-%@-%@T%@:%@:00", year, month, day, hours, minutes];
		}
		if ([[paramName lowercaseString] isEqualToString:@"s"]) {
			s = [paramValue stringByReplacingOccurrencesOfString:@"." withString:@""];
		}
		if ([[paramName lowercaseString] isEqualToString:@"fn"]) {
			fn = paramValue;
		}
		if ([[paramName lowercaseString] isEqualToString:@"i"]) {
			i = paramValue;
		}
		if ([[paramName lowercaseString] isEqualToString:@"fp"]) {
			fp = paramValue;
		}
		if ([[paramName lowercaseString] isEqualToString:@"n"]) {
			n = paramValue;
		}
	}
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://proverkacheka.nalog.ru:9999/v1/ofds/*/inns/*/fss/%@/operations/%@/tickets/%@?fiscalSign=%@&date=%@&sum=%@", fn, n, i, fp, t, s]];
	
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
	[request setHTTPMethod:@"GET"];
	[request setURL:url];
	
	__block ReceiptFindResultType checkResult = notfound;
	
	dispatch_semaphore_t _Nonnull semaphore = dispatch_semaphore_create(0);
	NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
	sessionConfiguration.HTTPAdditionalHeaders = @{
												   @"Authorization": @"Basic Nzk2NTI0OTIxNTU6NTc3NzY5",
												   @"Device-Id": [[[UIDevice currentDevice] identifierForVendor] UUIDString],
												   @"Device-OS": [[UIDevice currentDevice] systemVersion],
												   @"Version": @"2",
												   @"ClientVersion": @"1.4.4.1",
												   @"User-Agent": @"okhttp/3.0.1",
												   @"Accept-Encoding": @"gzip"
												   //@"Content-Type": @"application/json; charset=UTF-8"
												   };
	NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration];
	
	[[session dataTaskWithRequest:request completionHandler:
	  ^(NSData * _Nullable data,
		NSURLResponse * _Nullable response,
		NSError * _Nullable error) {
		  
		  NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
		  if (httpResponse) {
			  if (httpResponse.statusCode == 204) {
				  checkResult = found;
			  }
			  if (httpResponse.statusCode == -1005) {
				  checkResult = finderror;
			  }
		  } else {
			  checkResult = finderror;
		  }
		  dispatch_semaphore_signal(semaphore);
		  
	  }] resume];
	
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
	return checkResult;
}

- (NSString *)receiptGet:(int)iteration {
	
	if (iteration > 15) {
		return NSLocalizedString(@"Receipt getting error. Please try again.", @"Receipt getting error. Please try again.");
	}
	
	NSString *t = @"";
	NSString *s = @"";
	NSString *fn = @"";
	NSString *i = @"";
	NSString *fp = @"";
	NSString *n = @"";
	
	for (NSString *param in [self.CodeProcessor.codeValue componentsSeparatedByString:@"&"]) {
		NSArray *elts = [param componentsSeparatedByString:@"="];
		if([elts count] < 2) continue;
		NSString *paramName = [[elts firstObject] lowercaseString];
		NSString *paramValue = [elts lastObject];
		if ([[paramName lowercaseString] isEqualToString:@"t"]) {
			NSString *year = [paramValue substringWithRange:NSMakeRange(0, 4)];
			NSString *month = [paramValue substringWithRange:NSMakeRange(4, 2)];
			NSString *day = [paramValue substringWithRange:NSMakeRange(6, 2)];
			NSString *hours = [paramValue substringWithRange:NSMakeRange(9, 2)];
			NSString *minutes = [paramValue substringWithRange:NSMakeRange(11, 2)];
			t = [NSString stringWithFormat:@"%@-%@-%@T%@:%@:00", year, month, day, hours, minutes];
		}
		if ([[paramName lowercaseString] isEqualToString:@"s"]) {
			s = [paramValue stringByReplacingOccurrencesOfString:@"." withString:@""];
		}
		if ([[paramName lowercaseString] isEqualToString:@"fn"]) {
			fn = paramValue;
		}
		if ([[paramName lowercaseString] isEqualToString:@"i"]) {
			i = paramValue;
		}
		if ([[paramName lowercaseString] isEqualToString:@"fp"]) {
			fp = paramValue;
		}
		if ([[paramName lowercaseString] isEqualToString:@"n"]) {
			n = paramValue;
		}
	}
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://proverkacheka.nalog.ru:9999/v1/inns/*/kkts/*/fss/%@/tickets/%@?fiscalSign=%@&sendToEmail=no", fn, i, fp]];
	
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
	[request setHTTPMethod:@"GET"];
	[request setURL:url];
	
	__block NSString *checkResult = @"";
	
	dispatch_semaphore_t _Nonnull semaphore = dispatch_semaphore_create(0);
	NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
	sessionConfiguration.HTTPAdditionalHeaders = @{
												   @"Authorization": @"Basic Kzc5NjUyNDkyMTU1OjU3Nzc2OQ==",
												   @"Device-Id": [[[UIDevice currentDevice] identifierForVendor] UUIDString],
												   @"Device-OS": [[UIDevice currentDevice] systemVersion],
												   @"Version": @"2",
												   @"ClientVersion": @"1.4.4.1",
												   @"User-Agent": @"okhttp/3.0.1"
												   //@"Accept-Encoding": @"gzip"
												   //@"Content-Type": @"application/json; charset=UTF-8"
												   };
	NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration];
	
	[[session dataTaskWithRequest:request completionHandler:
	  ^(NSData * _Nullable data,
		NSURLResponse * _Nullable response,
		NSError * _Nullable error) {
		  
		  NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
		  if (httpResponse) {
			  NSLog(@"%li", (long)httpResponse.statusCode);
			  if (httpResponse.statusCode == 200) {
				  checkResult = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
				  NSLog(@"receipt: %@", checkResult);
				  if (!checkResult || [checkResult isEqualToString:@""]) {
					  if (iteration == 0) {
						  sleep(1);
						  checkResult = [self receiptGet:iteration+1];
					  } else {
						  checkResult = NSLocalizedString(@"Receipt getting error. Please try again.", @"Receipt getting error. Please try again.");
					  }
				  }
			  }
			  if (httpResponse.statusCode > 200 && httpResponse.statusCode < 300) {
				  sleep(1);
				  checkResult = [self receiptGet:iteration+1];
			  }
			  if (httpResponse.statusCode == -1005) {
				  checkResult = NSLocalizedString(@"Error get receipt", @"Error get receipt");
			  }
			  checkResult = NSLocalizedString(@"Receipt getting error. Please try again.", @"Receipt getting error. Please try again.");
		  } else {
			  checkResult = NSLocalizedString(@"Receipt data is empty", @"Receipt data is empty");
		  }
		  dispatch_semaphore_signal(semaphore);
		  
	  }] resume];
	
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
	return checkResult;
}

@end
