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

@interface CodeCardViewController ()

@end

@implementation CodeCardViewController

@synthesize CodeProcessor;

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.navigationItem.title = NSLocalizedString(@"CODE CARD", @"CODE CARD");
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
    if ([segue.identifier isEqualToString:@"Wallet"]) {
        [(WalletViewController *)[segue destinationViewController] setCodeProcessor:(NSString *)sender];
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

#pragma mark UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if (self.CodeProcessor.actionType == atPayment)
        return 3;
    return 2;
}

- (NSInteger)actionRows {
    switch (self.CodeProcessor.actionType) {
        case atPayment:
            return 1;
        case atURL:
            return 2;
        case atGoods:
            return 5;
        case atVCard:
            return 1;
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

@end
