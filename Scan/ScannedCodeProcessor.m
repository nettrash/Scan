//
//  ScannedCodeProcessor.m
//  Scan
//
//  Created by Иван Алексеев on 11.12.16.
//  Copyright © 2016 NETTRASH. All rights reserved.
//

#import "ScannedCodeProcessor.h"
#import "NSString+Checkers.h"
#import "Field.h"

@implementation ScannedCodeProcessor

@synthesize codeType, codeValue, actionType, Url, Fields;

- (void)initWithScanType:(NSString *)type andText:(NSString *)text
{
    self.codeType = type;
    self.codeValue = text;
    self.actionType = atUnknown;
    
    self.Url = [NSURL URLWithString:[NSString stringWithFormat:@"https://google.com/search?ie=UTF-8&hl=ru&q=%@", self.codeValue]];
    if ([self.codeType isEqualToString:@"org.iso.QRCode"]) {
        [self processQR];
    }
    if ([self.codeType isEqualToString:@"org.iso.Aztec"]) {
        [self processAztec];
    }
    if ([self.codeType isEqualToString:@"org.iso.Code39"]) {
        [self processCode39];
    }
    if ([self.codeType isEqualToString:@"org.iso.Code128"]) {
        [self processCode128];
    }
    if ([self.codeType isEqualToString:@"org.iso.PDF417"]) {
        [self processPDF417];
    }
    if ([self.codeType isEqualToString:@"org.gs1.EAN-13"]) {
        self.actionType = atGoods;
        self.Url = [NSURL URLWithString:[NSString stringWithFormat:@"https://google.com/search?ie=UTF-8&hl=ru&q=%@", self.codeValue]];
    }
}

- (void)processQR
{
    if ([self.codeValue isVCARD]) {
        self.actionType = atVCard;
        return;
    }
    if ([self.codeValue isST00011] || [self.codeValue isST00012]) {
        self.Url = [NSURL URLWithString:@"https://www.tinkoff.ru/payments/"];
        
        NSString *resultText = self.codeValue;
        NSArray *parts = [resultText componentsSeparatedByString:@"|"];
        NSMutableDictionary *prms = [[NSMutableDictionary alloc] init];
        for (NSString *part in parts) {
            NSArray *a = [part componentsSeparatedByString:@"="];
            if (a && [a count] == 2) {
                [prms setValue:(NSString *)[a objectAtIndex:1] forKey:[(NSString *)[a objectAtIndex:0] uppercaseString]];
            }
        }
        
        //Платежка на реквизиты
        self.Fields = [[NSMutableArray alloc] initWithCapacity:0];

        //PayerLastName
        if ([prms objectForKey:@"LASTNAME"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Payer last name", @"Payer last name") andValue:(NSString *)[prms objectForKey:@"LASTNAME"]]];
        }
        //PayerName
        if ([prms objectForKey:@"FIRSTNAME"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Payer name", @"Payer name") andValue:(NSString *)[prms objectForKey:@"FIRSTNAME"]]];
        }
        //PayerSurName
        if ([prms objectForKey:@"MIDDLENAME"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Payer sure name", @"Payer sure name") andValue:(NSString *)[prms objectForKey:@"MIDDLENAME"]]];
        }
        //PayerAddressReg
        if ([prms objectForKey:@"PAYERADDRESS"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Payer address", @"Payer address") andValue:(NSString *)[prms objectForKey:@"PAYERADDRESS"]]];
        }
        //ReceiverAccount
        if ([prms objectForKey:@"PERSONALACC"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver account", @"Receiver account") andValue:(NSString *)[prms objectForKey:@"PERSONALACC"]]];
        }
        //ReceiverName
        if ([prms objectForKey:@"NAME"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver name", @"Receiver name") andValue:(NSString *)[prms objectForKey:@"NAME"]]];
        }
        //ReceiverBIK
        if ([prms objectForKey:@"BIC"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver BIC", @"Receiver BIC") andValue:(NSString *)[prms objectForKey:@"BIC"]]];
        }
        //ReceiverINN
        if ([prms objectForKey:@"PAYEEINN"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver INN", @"Receiver INN") andValue:(NSString *)[prms objectForKey:@"PAYEEINN"]]];
        }
        //ReceiverKPP
        if ([prms objectForKey:@"KPP"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver KPP", @"Receiver KPP") andValue:(NSString *)[prms objectForKey:@"KPP"]]];
        }
        //PurposeOfPayment
        if ([prms objectForKey:@"PURPOSE"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Purpose of payment", @"Purpose of payment") andValue:(NSString *)[prms objectForKey:@"PURPOSE"]]];
        } else {
            if ([prms objectForKey:@"RULEID"]) {
                [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Resolution number", @"Resolution number") andValue:(NSString *)[prms objectForKey:@"RULEID"]]];
                if ([prms objectForKey:@"QUITTDATE"]) {
                    [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Resolution date", @"Resolution date") andValue:(NSString *)[prms objectForKey:@"QUITTDATE"]]];
                    [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Purpose of payment", @"Purpose of payment") andValue:[NSString stringWithFormat:NSLocalizedString(@"PENALTY DECISION ADMINISTRATIVE LAW NUMBER %@ from %@", @"PENALTY DECISION ADMINISTRATIVE LAW NUMBER %@ from %@"), (NSString *)[prms objectForKey:@"RULEID"], (NSString *)[prms objectForKey:@"QUITTDATE"]]]]; //ШТРАФ ПО АДМИНИСТРАТИВНОМУ ПРАВОНАРУШЕНИЮ ПОСТАНОВЛЕНИЕ №%@ от%@
                } else {
                    [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Purpose of payment", @"Purpose of payment") andValue:[NSString stringWithFormat:NSLocalizedString(@"PENALTY DECISION ADMINISTRATIVE LAW NUMBER %@", @"PENALTY DECISION ADMINISTRATIVE LAW NUMBER %@"), (NSString *)[prms objectForKey:@"RULEID"]]]]; //ШТРАФ ПО АДМИНИСТРАТИВНОМУ ПРАВОНАРУШЕНИЮ ПОСТАНОВЛЕНИЕ №%@
                }
            } else {
                [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Purpose of payment", @"Purpose of payment") andValue:NSLocalizedString(@"Payment", @"Payment")]]; //Оплата начисления
            }
        }
        //ReceiverOKATO (OKTMO)
        if ([prms objectForKey:@"OKTMO"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver OKTMO", @"Receiver OKTMO") andValue:(NSString *)[prms objectForKey:@"OKTMO"]]];
        }
        //ReceiverKBK
        if ([prms objectForKey:@"CBC"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver CBC", @"Receiver CBC") andValue:(NSString *)[prms objectForKey:@"CBC"]]];
        }
        //BIStatus
        //BIPaymentType
        if ([prms objectForKey:@"TAXPAYTKIND"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Budget Index Payment Type", @"Budget Index Payment Type") andValue:(NSString *)[prms objectForKey:@"TAXPAYTKIND"]]];
        }
        //BIPurpose
        if ([prms objectForKey:@"PAYTREASON"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Budget Index Purpose", @"Budget Index Purpose") andValue:(NSString *)[prms objectForKey:@"PAYTREASON"]]];
        }
        //BITaxPeriod
        if ([prms objectForKey:@"TAXPERIOD"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Budget Index Tax Period", @"Budget Index Tax Period") andValue:(NSString *)[prms objectForKey:@"TAXPERIOD"]]];
        }
        //BITaxDocNumber
        if ([prms objectForKey:@"DOCNO"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Budget Index Tax Document Number", @"Budget Index Tax Document Number") andValue:(NSString *)[prms objectForKey:@"DOCNO"]]];
        }
        //BITaxDocDate
        if ([prms objectForKey:@"DOCDATE"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Budget Index Tax Document Date", @"Budget Index Tax Document Date") andValue:(NSString *)[prms objectForKey:@"DOCDATE"]]];
        }
        //gosSupplierBillId
        if ([prms objectForKey:@"UIN"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"UIN", @"UIN") andValue:(NSString *)[prms objectForKey:@"UIN"]]];
        }
        //SUM
        if ([prms objectForKey:@"SUM"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Summa", @"Summa") andValue:(NSString *)[prms objectForKey:@"SUM"]]];
        }
        self.actionType = atPayment;
        return;
    }
    //Проверяем на тип URL
    if ([self.codeValue isURL]) {
        self.actionType = atURL;
        self.Url = [NSURL URLWithString:self.codeValue];
		if ([self.Url.host isBTC]) {
			self.Url = [NSURL URLWithString:[NSString stringWithFormat:@"https://blockexplorer.com/address/%@", self.Url.host]];
			return;
		}
		if ([self.Url.host isBIO]) {
			self.Url = [NSURL URLWithString:[NSString stringWithFormat:@"http://block-explorer.biocoin.bio/address/%@", self.Url.host]];
			return;
		}
		if ([self.Url.host isSIB]) {
			self.Url = [NSURL URLWithString:[NSString stringWithFormat:@"https://sibexplorer.com/address/%@", self.Url.host]];
			return;
		}
        return;
    }
	//Проверяем на криптовалюты
	if ([self.codeValue isBTC]) {
		self.actionType = atURL;
		self.Url = [NSURL URLWithString:[NSString stringWithFormat:@"https://blockexplorer.com/address/%@", self.codeValue]];
		return;
	}
	if ([self.codeValue isBIO]) {
		self.actionType = atURL;
		self.Url = [NSURL URLWithString:[NSString stringWithFormat:@"http://block-explorer.biocoin.bio/address/%@", self.codeValue]];
		return;
	}
	if ([self.codeValue isSIB]) {
		self.actionType = atURL;
		self.Url = [NSURL URLWithString:[NSString stringWithFormat:@"https://sibexplorer.com/address/%@", self.codeValue]];
		return;
	}
	if ([[self.codeValue lowercaseString] hasPrefix:@"sibcoin:"] || [[self.codeValue lowercaseString] hasPrefix:@"biocoin:"] || [[self.codeValue lowercaseString] hasPrefix:@"bitcoin:"]) {
		NSString *v = [self.codeValue stringByReplacingOccurrencesOfString:@"oin:" withString:@"oin://"];
		if ([v isURL]) {
			self.actionType = atURL;
			self.Url = [NSURL URLWithString:v];
			if ([self.Url.host isBTC]) {
				self.Url = [NSURL URLWithString:[NSString stringWithFormat:@"https://blockexplorer.com/address/%@", self.Url.host]];
				return;
			}
			if ([self.Url.host isBIO]) {
				self.Url = [NSURL URLWithString:[NSString stringWithFormat:@"http://block-explorer.biocoin.bio/address/%@", self.Url.host]];
				return;
			}
			if ([self.Url.host isSIB]) {
				self.Url = [NSURL URLWithString:[NSString stringWithFormat:@"https://sibexplorer.com/address/%@", self.Url.host]];
				return;
			}
			return;
		}

	}
}

- (void)processAztec
{
    if ([self.codeValue isST00011] || [self.codeValue isST00012]) {
        self.Url = [NSURL URLWithString:@"https://www.tinkoff.ru/payments/"];
        
        NSData *data = [self.codeValue dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES];
        NSString *resultText = [[NSString alloc] initWithData:data encoding:NSWindowsCP1251StringEncoding];
        NSArray *parts = [resultText componentsSeparatedByString:@"|"];
        NSMutableDictionary *prms = [[NSMutableDictionary alloc] init];
        for (NSString *part in parts) {
            NSArray *a = [part componentsSeparatedByString:@"="];
            if (a && [a count] == 2) {
                [prms setValue:(NSString *)[a objectAtIndex:1] forKey:[(NSString *)[a objectAtIndex:0] uppercaseString]];
            }
        }
        
        //Платежка на реквизиты
        self.Fields = [[NSMutableArray alloc] initWithCapacity:0];
        
        //PayerLastName
        if ([prms objectForKey:@"LASTNAME"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Payer last name", @"Payer last name") andValue:(NSString *)[prms objectForKey:@"LASTNAME"]]];
        }
        //PayerName
        if ([prms objectForKey:@"FIRSTNAME"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Payer name", @"Payer name") andValue:(NSString *)[prms objectForKey:@"FIRSTNAME"]]];
        }
        //PayerSurName
        if ([prms objectForKey:@"MIDDLENAME"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Payer sure name", @"Payer sure name") andValue:(NSString *)[prms objectForKey:@"MIDDLENAME"]]];
        }
        //PayerAddressReg
        if ([prms objectForKey:@"PAYERADDRESS"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Payer address", @"Payer address") andValue:(NSString *)[prms objectForKey:@"PAYERADDRESS"]]];
        }
        //ReceiverAccount
        if ([prms objectForKey:@"PERSONALACC"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver account", @"Receiver account") andValue:(NSString *)[prms objectForKey:@"PERSONALACC"]]];
        }
        //ReceiverName
        if ([prms objectForKey:@"NAME"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver name", @"Receiver name") andValue:(NSString *)[prms objectForKey:@"NAME"]]];
        }
        //ReceiverBIK
        if ([prms objectForKey:@"BIC"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver BIC", @"Receiver BIC") andValue:(NSString *)[prms objectForKey:@"BIC"]]];
        }
        //ReceiverINN
        if ([prms objectForKey:@"PAYEEINN"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver INN", @"Receiver INN") andValue:(NSString *)[prms objectForKey:@"PAYEEINN"]]];
        }
        //ReceiverKPP
        if ([prms objectForKey:@"KPP"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver KPP", @"Receiver KPP") andValue:(NSString *)[prms objectForKey:@"KPP"]]];
        }
        //PurposeOfPayment
        if ([prms objectForKey:@"PURPOSE"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Purpose of payment", @"Purpose of payment") andValue:(NSString *)[prms objectForKey:@"PURPOSE"]]];
        } else {
            if ([prms objectForKey:@"RULEID"]) {
                [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Resolution number", @"Resolution number") andValue:(NSString *)[prms objectForKey:@"RULEID"]]];
                if ([prms objectForKey:@"QUITTDATE"]) {
                    [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Resolution date", @"Resolution date") andValue:(NSString *)[prms objectForKey:@"QUITTDATE"]]];
                    [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Purpose of payment", @"Purpose of payment") andValue:[NSString stringWithFormat:NSLocalizedString(@"PENALTY DECISION ADMINISTRATIVE LAW NUMBER %@ from %@", @"PENALTY DECISION ADMINISTRATIVE LAW NUMBER %@ from %@"), (NSString *)[prms objectForKey:@"RULEID"], (NSString *)[prms objectForKey:@"QUITTDATE"]]]]; //ШТРАФ ПО АДМИНИСТРАТИВНОМУ ПРАВОНАРУШЕНИЮ ПОСТАНОВЛЕНИЕ №%@ от%@
                } else {
                    [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Purpose of payment", @"Purpose of payment") andValue:[NSString stringWithFormat:NSLocalizedString(@"PENALTY DECISION ADMINISTRATIVE LAW NUMBER %@", @"PENALTY DECISION ADMINISTRATIVE LAW NUMBER %@"), (NSString *)[prms objectForKey:@"RULEID"]]]]; //ШТРАФ ПО АДМИНИСТРАТИВНОМУ ПРАВОНАРУШЕНИЮ ПОСТАНОВЛЕНИЕ №%@
                }
            } else {
                [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Purpose of payment", @"Purpose of payment") andValue:NSLocalizedString(@"Payment", @"Payment")]]; //Оплата начисления
            }
        }
        //ReceiverOKATO (OKTMO)
        if ([prms objectForKey:@"OKTMO"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver OKTMO", @"Receiver OKTMO") andValue:(NSString *)[prms objectForKey:@"OKTMO"]]];
        }
        //ReceiverKBK
        if ([prms objectForKey:@"CBC"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver CBC", @"Receiver CBC") andValue:(NSString *)[prms objectForKey:@"CBC"]]];
        }
        //BIStatus
        //BIPaymentType
        if ([prms objectForKey:@"TAXPAYTKIND"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Budget Index Payment Type", @"Budget Index Payment Type") andValue:(NSString *)[prms objectForKey:@"TAXPAYTKIND"]]];
        }
        //BIPurpose
        if ([prms objectForKey:@"PAYTREASON"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Budget Index Purpose", @"Budget Index Purpose") andValue:(NSString *)[prms objectForKey:@"PAYTREASON"]]];
        }
        //BITaxPeriod
        if ([prms objectForKey:@"TAXPERIOD"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Budget Index Tax Period", @"Budget Index Tax Period") andValue:(NSString *)[prms objectForKey:@"TAXPERIOD"]]];
        }
        //BITaxDocNumber
        if ([prms objectForKey:@"DOCNO"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Budget Index Tax Document Number", @"Budget Index Tax Document Number") andValue:(NSString *)[prms objectForKey:@"DOCNO"]]];
        }
        //BITaxDocDate
        if ([prms objectForKey:@"DOCDATE"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Budget Index Tax Document Date", @"Budget Index Tax Document Date") andValue:(NSString *)[prms objectForKey:@"DOCDATE"]]];
        }
        //gosSupplierBillId
        if ([prms objectForKey:@"UIN"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"UIN", @"UIN") andValue:(NSString *)[prms objectForKey:@"UIN"]]];
        }
        //SUM
        if ([prms objectForKey:@"SUM"]) {
            [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Summa", @"Summa") andValue:(NSString *)[prms objectForKey:@"SUM"]]];
        }
        self.actionType = atPayment;
        return;
    }
}

- (void)processCode39
{
    if ([self.codeValue isPossibleMGTS]) {
        self.Url = [NSURL URLWithString:@"https://www.tinkoff.ru/payments/kommunalnie-platezhi/"];
        /*
         МГТС
         
         Label QiwiS31
         Name МГТС
         P5918_account Номер телефона
         
         OutPossibleValue сумма через ;
         
         Пример 495420050901250048100
         
         Номер 4954200509
         Квартира 0125
         Сумма 0048100
         */
        self.Fields = [[NSMutableArray alloc] initWithCapacity:0];
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Provider", @"Provider") andValue:NSLocalizedString(@"MGTS", @"MGTS")]];
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Account", @"Account") andValue:[self.codeValue substringWithRange:NSMakeRange(0, 10)]]];
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Summa", @"Summa") andValue:[NSString stringWithFormat:@"%i.%@;", [[self.codeValue substringWithRange:NSMakeRange(14, 5)] intValue], [self.codeValue substringWithRange:NSMakeRange(19, 2)]]]];
        self.actionType = atPayment;
        
        return;
    }
    if ([self.codeValue isPossibleMosenergosbut]) {
        self.Url = [NSURL URLWithString:@"https://www.tinkoff.ru/payments/kommunalnie-platezhi/"];
        /*
         МОСЭНЕРГОСБЫТ
         
         Label QiwiS330
         Name Мосэнергосбыт
         P86259_account Номер лицевого счета
         
         OutPossibleValues сумма через ;
         
         Пример 1996120112505301371110649
         
         Код РР 199
         Лицевой счет 61201125
         
         053 - Не ясно что это
         
         Рубли 01371
         Копейки 11
         Код платежа 06
         
         49 - не ясно что это такое
         */
        self.Fields = [[NSMutableArray alloc] initWithCapacity:0];
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Provider", @"Provider") andValue:NSLocalizedString(@"MOSENERGOSBYT", @"MOSENERGOSBYT")]];
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Account", @"Account") andValue:[self.codeValue substringWithRange:NSMakeRange(3, 8)]]];
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Summa", @"Summa") andValue:[NSString stringWithFormat:@"%i.%@;", [[self.codeValue substringWithRange:NSMakeRange(14, 5)] intValue], [self.codeValue substringWithRange:NSMakeRange(19, 2)]]]];
        self.actionType = atPayment;
        return;
    }
}

- (void)processCode128
{
    if ([self.codeValue isPossibleMoscowGKU]) {
        self.Url = [NSURL URLWithString:@"https://www.tinkoff.ru/payments/kommunalnie-platezhi/"];
        /*
         ЖКУ - Москва
         
         Labe QiwiS265
         Name ЖКУ Москва
         P5929_account[0] Код абонента
         P5929_account[1] ММГГ
         
         OutPossibleValues Суммы через ;
         
         Пример 2840914162091303581140367153
         Код абонента 2840914162 (с 0 по 9 символ)
         Период ММГГ 0913 (с 10 по 13)
         Сумма без страховки 0358114 3581.14
         Сумма со страховкой 0367153 3671.53
         */
        self.Fields = [[NSMutableArray alloc] initWithCapacity:0];
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Provider", @"Provider") andValue:NSLocalizedString(@"MOSCOW GKU", @"MOSCOW GKU")]];
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Account", @"Account") andValue:[self.codeValue substringWithRange:NSMakeRange(0, 10)]]];
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Period", @"Period") andValue:[self.codeValue substringWithRange:NSMakeRange(10, 4)]]];
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Summa", @"Summa") andValue:[NSString stringWithFormat:@"%i.%@", [[self.codeValue substringWithRange:NSMakeRange(14, 5)] intValue], [self.codeValue substringWithRange:NSMakeRange(19, 2)]]]];
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Summa with insurance", @"Summa with insurance") andValue:[NSString stringWithFormat:@"%i.%@", [[self.codeValue substringWithRange:NSMakeRange(21, 5)] intValue], [self.codeValue substringWithRange:NSMakeRange(26, 2)]]]];
        self.actionType = atPayment;
        return;
    }
    //    if ([self.codeValue isPossibleGIBDD]) {
    /*
     Штраф ГИБДД
     
     Label
     Name
     P...
     
     OutPossibleValues ...
     
     Пример 18810168140430001964
     */
    //    }
    if ([self.codeValue isPossibleMosenergosbut]) {
        self.Url = [NSURL URLWithString:@"https://www.tinkoff.ru/payments/kommunalnie-platezhi/"];
        /*
         МОСЭНЕРГОСБЫТ
         
         Label QiwiS330
         Name Мосэнергосбыт
         P86259_account Номер лицевого счета
         
         OutPossibleValues сумма через ;
         
         Пример 1996120112505301371110649
         
         Код РР 199
         Лицевой счет 61201125
         
         053 - Не ясно что это
         
         Рубли 01371
         Копейки 11
         Код платежа 06
         
         49 - не ясно что это такое
         */
        self.Fields = [[NSMutableArray alloc] initWithCapacity:0];
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Provider", @"Provider") andValue:NSLocalizedString(@"MOSENERGOSBYT", @"MOSENERGOSBYT")]];
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Account", @"Account") andValue:[self.codeValue substringWithRange:NSMakeRange(3, 8)]]];
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Summa", @"Summa") andValue:[NSString stringWithFormat:@"%i.%@;", [[self.codeValue substringWithRange:NSMakeRange(14, 5)] intValue], [self.codeValue substringWithRange:NSMakeRange(19, 2)]]]];
        self.actionType = atPayment;
        return;
    }
}

- (void)processPDF417
{
    self.Url = [NSURL URLWithString:@"https://www.tinkoff.ru/payments/"];
    if ([self.codeValue isPD4Nalog]) {
        NSData *data = [self.codeValue dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES];
        NSString *resultText = [[NSString alloc] initWithData:data encoding:NSWindowsCP1251StringEncoding];
        NSArray *a = [resultText componentsSeparatedByString:@"|"];
        
        NSString *fio = (NSString *)[a objectAtIndex:5];
        NSArray *b = [fio componentsSeparatedByString:@" "];
        self.Fields = [[NSMutableArray alloc] initWithCapacity:0];
        
        //PayerLastName
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Payer last name", @"Payer last name") andValue:(NSString *)[b objectAtIndex:0]]];
        //PayerName
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Payer name", @"Payer name") andValue:(NSString *)[b objectAtIndex:1]]];
        //PayerSurName
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Payer sure name", @"Payer sure name") andValue:(NSString *)[b objectAtIndex:2]]];
        //PayerAddressReg
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Payer address", @"Payer address") andValue:(NSString *)[a objectAtIndex:6]]];
        //ReceiverAccount
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver account", @"Receiver account") andValue:(NSString *)[a objectAtIndex:13]]];
        //ReceiverName
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver name", @"Receiver name") andValue:(NSString *)[a objectAtIndex:12]]];
        //ReceiverBIK
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver BIC", @"Receiver BIC") andValue:(NSString *)[a objectAtIndex:10]]];
        //ReceiverINN
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver INN", @"Receiver INN") andValue:(NSString *)[a objectAtIndex:14]]];
        //ReceiverKPP
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver KPP", @"Receiver KPP") andValue:(NSString *)[a objectAtIndex:15]]];
        //PurposeOfPayment
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Purpose of payment", @"Purpose of payment") andValue:NSLocalizedString(@"Payment", @"Payment")]]; //Оплата начисления
        //ReceiverOKATO (OKTMO)
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver OKTMO", @"Receiver OKTMO") andValue:(NSString *)[a objectAtIndex:17]]];
        //ReceiverKBK
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Receiver CBC", @"Receiver CBC") andValue:(NSString *)[a objectAtIndex:16]]];
        //BIStatus
        //BIPaymentType
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Budget Index Payment Type", @"Budget Index Payment Type") andValue:(NSString *)[a objectAtIndex:20]]];
        //BIPurpose
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Budget Index Purpose", @"Budget Index Purpose") andValue:(NSString *)[a objectAtIndex:18]]];
        //BITaxPeriod
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Budget Index Tax Period", @"Budget Index Tax Period") andValue:(NSString *)[a objectAtIndex:19]]];
        //BITaxDocNumber
        //[self.Fields setValue:(NSString *)[prms objectForKey:@"DOCNO"] forKey:@"Budget Index Tax Document Number"];
        //BITaxDocDate
        //[self.Fields setValue:(NSString *)[prms objectForKey:@"DOCDATE"] forKey:@"Budget Index Tax Document Date"];
        //gosSupplierBillId
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"UIN", @"UIN") andValue:(NSString *)[a objectAtIndex:3]]];
        //SUM
        [self.Fields addObject:[Field fieldWithName:NSLocalizedString(@"Summa", @"Summa") andValue:(NSString *)[a objectAtIndex:8]]];
        self.actionType = atPayment;
        return;
    }
}

@end
