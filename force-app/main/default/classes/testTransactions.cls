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
private class testTransactions {

   static testMethod void testTransactionAfterSave()
   {
       	// Look up a couple of Transaction record types
		Map<String, RecordTypeInfo> transactionRecTypeMap = Schema.Sobjecttype.Transaction__c.getRecordTypeInfosByName(); 
		String recurringRecTypeId = transactionRecTypeMap.get('Recurring').getRecordTypeId();
		String instanceRecTypeId = transactionRecTypeMap.get('Instance').getRecordTypeId();
       	String budgetRecTypeId = transactionRecTypeMap.get('Budget').getRecordTypeId();
       
   		Acct__c account1 = new Acct__c();
   		Acct__c account2 = new Acct__c();
   		
   		Database.insert(new List<Acct__c>{account1, account2});
   	
   		Transaction__c newRecord1 = new Transaction__c(
   			Amount__c = 10,
	   		RecordTypeId = recurringRecTypeId,
	   		Recurrence_Period__c = 'Day',
	   		Recurrence_Number__c = 1,
	   		Status__c = 'Planned',
	   		Date__c = System.today(),
	   		End_Date__c = System.today().addDays(1),
	   		To__c = account1.Id,
	   		From__c = account2.Id
   		);
   		
   		Transaction__c newRecord2 = new Transaction__c(
   			Amount__c = 10,
	   		RecordTypeId = recurringRecTypeId,
	   		Recurrence_Period__c = 'Week',
	   		Recurrence_Number__c = 1,
	   		Status__c = 'Planned',
	   		Date__c = System.today(),
	   		End_Date__c = System.today().addDays(1),
	   		To__c = account1.Id,
	   		From__c = account2.Id
   		);
       
   		Transaction__c newRecord3 = new Transaction__c(
   			Amount__c = 10,
	   		RecordTypeId = budgetRecTypeId,
	   		Recurrence_Period__c = 'Day',
	   		Recurrence_Number__c = 1,
	   		Status__c = 'Planned',
	   		Date__c = System.today(),
	   		End_Date__c = System.today().addDays(1),
	   		To__c = account1.Id,
	   		From__c = account2.Id
   		);

   		Database.insert(new List<Transaction__c> {newRecord1, newRecord2, newRecord3});
   		
   		Test.setCurrentPage(new PageReference('/apex/AccountForecast?Id=' + account1.Id));
		AccountForecastController theController = new AccountForecastController();
		
		Test.setCurrentPage(new PageReference('/apex/AccountForecast?Id=' + account2.Id));
		theController = new AccountForecastController();
		
		newRecord1.Budget__c = 'Test';
		
   		Database.update(new List<Transaction__c> {newRecord1});		
   		
   }
   
   static testMethod void testAccountForecast() 
   {

   }
}