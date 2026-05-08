/**
 * This class contains unit tests for validating the behavior of Apex classes
 * and triggers.
 *
 * Unit tests are class methods that verify whether a particular piece
 * of code is working properly. Unit test methods take no arguments,
 * commit no data to the database, and are flagged with the testMethod
 * keyword in the method definition.
 *
 * All test methods in an organization are executed whenever Apex code is deployed
 * to a production organization to confirm correctness, ensure code
 * coverage, and prevent regressions. All Apex classes are
 * required to have at least 75% code coverage in order to be deployed
 * to a production organization. In addition, all triggers must have some code coverage.
 * 
 * The @isTest class annotation indicates this class only contains test
 * methods. Classes defined with the @isTest annotation do not count against
 * the organization size limit for all Apex scripts.
 *
 * See the Apex Language Reference for more information about Testing and Code Coverage.
 */
@isTest
private class PaymentListControllerTest {

    private static testMethod void testPaymentListController()
	{
		RecordTypeInfo recTypeInfoRecurring = 
			Schema.Sobjecttype.Transaction__c.getRecordTypeInfosByName().get('Recurring');
		RecordTypeInfo recTypeInfoFund = 
			Schema.Sobjecttype.Acct__c.getRecordTypeInfosByName().get('Fund');
		
		Acct__c testAccountFrom = 
			Standard_Logic_Acct.createFinancialAccount(
				'testAccountFrom',
				recTypeInfoFund.getRecordTypeId(),
				null,
				false);
		
		Acct__c testAccountTo = 
			Standard_Logic_Acct.createFinancialAccount(
				'testAccountTo',
				recTypeInfoFund.getRecordTypeId(),
				null,
				false);
				
		testAccountFrom.Current_Balance__c = 400;
		testAccountTo.Current_Balance__c = 0;
		
		Database.insert(new List<Acct__c>{testAccountFrom, testAccountTo});
		
		Transaction__c testTrans = new Transaction__c();
		testTrans.RecordTypeId = recTypeInfoRecurring.getRecordTypeId();
		testTrans.Source__c = testAccountFrom.Id;
		testTrans.Destination__c = testAccountTo.Id;
		testTrans.Recurrence_Period__c = 'Week';
		testTrans.Recurrence_Number__c = 1;
		testTrans.Date__c = Date.today();
		testTrans.End_Date__c = Date.today().addDays(8);
		testTrans.Amount__c = 100;
		Database.insert(testTrans);
		
		Test.startTest();
		
		ApexPages.Standardcontroller testStandCont = new ApexPages.Standardcontroller(testAccountFrom);
		PaymentListController testPayListCont = new PaymentListController(testStandCont);
		
		testPayListCont.saveTransactions();
		
		Test.stopTest();
		
	}
}