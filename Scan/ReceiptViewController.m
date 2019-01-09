//
//  ReceiptViewController.m
//  Scan
//
//  Created by Иван Алексеев on 29/10/2018.
//  Copyright © 2018 NETTRASH. All rights reserved.
//

#import "ReceiptViewController.h"

@interface ReceiptViewController ()

@property (nonatomic, retain) NSMutableDictionary *receiptInfo;
@property (nonatomic, retain) NSNumber *code;

@property BOOL parsed;

@end

@implementation ReceiptViewController

@synthesize CodeText;

- (void)viewDidLoad {
	[super viewDidLoad];
	[self.navigationItem setTitle:NSLocalizedString(@"RECEIPT VALUE", @"RECEIPT VALUE")];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self parseReceiptData];
}

- (IBAction)done:(id)sender {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)parseReceiptData {
	NSData *receiptData = [self.CodeText dataUsingEncoding:NSUTF8StringEncoding];
	if (NSClassFromString(@"NSJSONSerialization")) {
		NSError *error = nil;
		id object = [NSJSONSerialization JSONObjectWithData:receiptData options:0 error:&error];
		if (error) {
			NSLog(@"%@", [error localizedDescription]);
		} else {
			if([object isKindOfClass:[NSDictionary class]])
			{
				NSDictionary *results = object;
				NSDictionary *document = [results objectForKey:@"document"];
				NSDictionary *receipt = [document objectForKey:@"receipt"];
				
				self.receiptInfo = [[NSMutableDictionary alloc] initWithCapacity:0];
				
				id obj = [receipt objectForKey:@"userInn"];
				if (obj) {
					[self.receiptInfo setObject:obj forKey:@"userInn"];
				}
				
				obj = [receipt objectForKey:@"operationType"];
				if (obj) {
					[self.receiptInfo setObject:obj forKey:NSLocalizedString(@"operationType", @"operationType")];
				}
				
				obj = [receipt objectForKey:@"taxationType"];
				if (obj) {
					[self.receiptInfo setObject:obj forKey:NSLocalizedString(@"taxationType", @"taxationType")];
				}
				
				obj = [receipt objectForKey:@"kktRegId"];
				if (obj) {
					[self.receiptInfo setObject:obj forKey:NSLocalizedString(@"kktRegId", @"kktRegId")];
				}
				
				obj = [receipt objectForKey:@"fiscalDocumentNumber"];
				if (obj) {
					[self.receiptInfo setObject:obj forKey:NSLocalizedString(@"fiscalDocumentNumber", @"fiscalDocumentNumber")];
				}
				
				obj = [receipt objectForKey:@"retailPlaceAddress"];
				if (obj) {
					[self.receiptInfo setObject:obj forKey:NSLocalizedString(@"retailPlaceAddress", @"retailPlaceAddress")];
				}
				
				obj = [receipt objectForKey:@"cashTotalSum"];
				if (obj) {
					[self.receiptInfo setObject:obj forKey:NSLocalizedString(@"cashTotalSum", @"cashTotalSum")];
				}
				
				obj = [receipt objectForKey:@"totalSum"];
				if (obj) {
					[self.receiptInfo setObject:obj forKey:NSLocalizedString(@"totalSum", @"totalSum")];
				}
				
				obj = [receipt objectForKey:@"receiptCode"];
				if (obj) {
					self.code = (NSNumber *)obj;
					[self.receiptInfo setObject:obj forKey:NSLocalizedString(@"receiptCode", @"receiptCode")];
				}
				
				obj = [receipt objectForKey:@"fiscalDriveNumber"];
				if (obj) {
					[self.receiptInfo setObject:obj forKey:NSLocalizedString(@"fiscalDriveNumber", @"fiscalDriveNumber")];
				}
				
				obj = [receipt objectForKey:@"dateTime"];
				if (obj) {
					[self.receiptInfo setObject:obj forKey:NSLocalizedString(@"dateTime", @"dateTime")];
				}
				
				obj = [receipt objectForKey:@"shiftNumber"];
				if (obj) {
					[self.receiptInfo setObject:obj forKey:NSLocalizedString(@"shiftNumber", @"shiftNumber")];
				}
				
				obj = [receipt objectForKey:@"ecashTotalSum"];
				if (obj) {
					[self.receiptInfo setObject:obj forKey:NSLocalizedString(@"ecashTotalSum", @"ecashTotalSum")];
				}
				
				obj = [receipt objectForKey:@"fiscalSign"];
				if (obj) {
					[self.receiptInfo setObject:obj forKey:NSLocalizedString(@"fiscalSign", @"fiscalSign")];
				}
				
				obj = [receipt objectForKey:@"user"];
				if (obj) {
					[self.receiptInfo setObject:obj forKey:NSLocalizedString(@"user", @"user")];
				}
				
				obj = [receipt objectForKey:@"operator"];
				if (obj) {
					[self.receiptInfo setObject:obj forKey:NSLocalizedString(@"operator", @"operator")];
				}
				
				obj = [receipt objectForKey:@"items"];
				if (obj) {
					NSArray *items = (NSArray *)obj;
					for (int i = 0; i < [items count]; i++) {
						NSDictionary *itm = (NSDictionary *)[items objectAtIndex:i];
						NSString *name = (NSString *)[itm objectForKey:@"name"];
						NSNumber *quantity = (NSNumber *)[itm objectForKey:@"quantity"];
						NSNumber *sum = (NSNumber *)[itm objectForKey:@"sum"];
						NSNumber *price = (NSNumber *)[itm objectForKey:@"price"];
						NSString *descr = [NSString stringWithFormat:@"%.2f * %.2f = %.2f", [quantity doubleValue] / 100.00, [price doubleValue] / 100.00, [sum doubleValue] / 100.00];
						[self.receiptInfo setObject:descr forKey:name];
					}
				}
				
				self.parsed = YES;
			}
			else
			{
				self.parsed = NO;
			}
		}
	} else {
		self.parsed = NO;
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

#pragma mark UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	switch (section) {
		case 0: {
			return self.receiptInfo.count;
		}
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
			NSString *key = (NSString *)[[self.receiptInfo allKeys] objectAtIndex:indexPath.row];
			NSString *value = [self.receiptInfo objectForKey:key];
			[cell.textLabel setText:key];
			[cell.detailTextLabel setText:value];
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
			switch ([self.code intValue]) {
				case 3:
					return NSLocalizedString(@"ReceiptCodeReceipt", @"ReceiptCodeReceipt");
				default:
					return @"";
			}
		default:
			return @"";
	}
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return @"";
}

@end

/*
 
 {"document":{"receipt":{"rawData":"AwBSAREEEAA5Mjg5MDAwMTAwMDg3NzQ1DQQUADAwMDEzMzUzNjgwMjE2MTkgICAg+gMMADc3MzQ2NzU4MTAgIBAEBABAYQAA9AMEAPwa2Fs1BAYAMQT3J0z4DgQEAFUAAAASBAQALwAAAB4EAQAB/AMCABw+IwRGAAYEGwCJrqPj4OIg4qXgrK7h4qDireupIDMsNSUs6OI3BAIA+BH/AwIAAAITBAIA8COvBAEAArAEAgBEA7wEAQABvgQBAAQjBEoABgQfAIyu4K6mpa2upSAika6rpa2g7yCqoOCgrKWr7CIs6OI3BAIALBr/AwIAAAETBAIALBqvBAEAArAEAgBhArwEAQABvgQBAAQHBAEAADkEAgAcPr8EAQAAwAQBAADBBAEAAP0DGwCNpeilraquIJGipeKroK2gII2oqq6roKWiraAfBAEAAbkEAQACTwQCAKUF","nds10":1445,"fiscalDocumentNumber":24896,"taxationType":1,"userInn":"7734675810","operationType":1,"kktRegId":"0001335368021619","items":[{"sum":9200,"quantity":2,"price":4600,"name":"Йогурт термостатный 3,5%,шт"},{"sum":6700,"quantity":1,"price":6700,"name":"Мороженое \"Соленая карамель\",шт"}],"retailPlaceAddress":"","senderAddress":"","cashTotalSum":0,"addressToCheckFiscalSign":"","totalSum":15900,"receiptCode":3,"fiscalDriveNumber":"9289000100087745","dateTime":"2018-10-30T08:49:00","shiftNumber":85,"ecashTotalSum":15900,"requestNumber":47,"buyerAddress":"","fiscalSign":4146547960,"user":"","operator":"Нешенко Светлана Николаевна"}}}
 
 {"document":{"receipt":{"items":[{"sum":4484,"price":4484,"nds10":408,"modifiers":[],"quantity":1,"name":"4600605024225 ЙОГУРТ ТЕРМОСТ.ДАНОН"},{"sum":4484,"price":4484,"nds10":408,"modifiers":[],"quantity":1,"name":"4600605024225 ЙОГУРТ ТЕРМОСТ.ДАНОН"},{"sum":4484,"price":4484,"nds10":408,"modifiers":[],"quantity":1,"name":"4600605024225 ЙОГУРТ ТЕРМОСТ.ДАНОН"},{"sum":42848,"nds18":6536,"price":42848,"modifiers":[],"quantity":1,"name":"8000070019911 КОФЕ ЛАВАЦЦА ОРО ЗОЛ"}],"nds18":6536,"dateTime":"2018-10-31T07:50:00","stornoItems":[],"nds10":1224,"operator":"Касса самообслуживан","modifiers":[],"operationType":1,"receiptCode":3,"ecashTotalSum":56300,"requestNumber":162,"rawData":"//8AHKUDARAJhxAAAQFVdkEAm0hNEfdsOgCapgACAgADAPwBEQQQADg3MTAwMDAxMDE1NTc2NDENBBQAMDAwMTQ3MDE3NzA0NTIyNiAgICD6AwwANzczMTE2Mjc1NCAgEAQEAEibAAD0AwQAqF7ZWzUEBgAxBHrPn20OBAQAawEAABIEBACiAAAAHgQBAAH8AwIA7NsjBD8ABgQiADQ2MDA2MDUwMjQyMjUgiY6Dk5CSIJKFkIyOkZIuhICNjo03BAIAhBH/AwMAA+gDEwQCAIQRTwQCAJgBIwQ/AAYEIgA0NjAwNjA1MDI0MjI1IImOg5OQkiCShZCMjpGSLoSAjY6NNwQCAIQR/wMDAAPoAxMEAgCEEU8EAgCYASMEPwAGBCIANDYwMDYwNTAyNDIyNSCJjoOTkJIgkoWQjI6Rki6EgI2OjTcEAgCEEf8DAwAD6AMTBAIAhBFPBAIAmAEjBD8ABgQiADgwMDAwNzAwMTk5MTEgio6UhSCLgIKAlpaAII6QjiCHjos3BAIAYKf/AwMAA+gDEwQCAGCnTgQCAIgZ/QMUAIqg4eGgIOGgrK6uoeGr46aooqCtBwQBAAA5BAIA7NtOBAIAiBlPBAIAyAQYBBQAh4COICKSIKggiiCP4K6k46ri6yLxAy8AMTA5MDQ0LCCjLoyu4aqioCwgk6uo5qAggq7grq3mrqLhqqDvLCCkrqwg/CA0NC4fBAEAAYEGLvRV+JK6","userInn":"7731162754","shiftNumber":363,"kktRegId":"0001470177045226","totalSum":56300,"taxationType":1,"retailPlaceAddress":"109044, г.Москва, Улица Воронцовская, дом № 44.","fiscalDriveNumber":"8710000101557641","fiscalSign":2060427117,"fiscalDocumentNumber":39752,"user":"ЗАО \"Т и К Продукты\"","cashTotalSum":0}}}
 
 */
