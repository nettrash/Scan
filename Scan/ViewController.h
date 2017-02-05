//
//  ViewController.h
//  Scan
//
//  Created by Иван Алексеев on 06.12.16.
//  Copyright © 2016 NETTRASH. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Contacts/Contacts.h>
#import <ContactsUI/ContactsUI.h>
#import <AVFoundation/AVFoundation.h>

@interface ViewController : UIViewController <AVCaptureMetadataOutputObjectsDelegate, CNContactViewControllerDelegate, UIPickerViewDelegate, UIPickerViewDataSource>

- (void)beginWork;

@end

