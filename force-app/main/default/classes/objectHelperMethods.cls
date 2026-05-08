public with sharing class objectHelperMethods {

	public static Account newAccount()
	{
		Account testAccount = new Account();
		testAccount.Name = 'test';
		return testAccount;
	}
	
	public static Project__c newProject(Id accountId)
	{
		Project__c testProject = new Project__c();
		testProject.Account__c = accountId;
		return testProject;
	}
	
	public static Contract newContract(Id accountId)
	{
		Contract testContract = new Contract();
		testContract.AccountId = accountId;
		return testContract;
	}
	
	public static Invoice__c newInvoice(Id accountId)
	{
		Invoice__c testInvoice = new Invoice__c();
		testInvoice.Invoiced_To__c = accountId;
		testInvoice.Invoice_Total__c = 0;
		return testInvoice;
	}
	
	public static Requirement__c newRequirement(Id projectId)
	{
		Requirement__c testRequirement = new Requirement__c();
		testRequirement.Project__c = projectId;
		testRequirement.Subject__c = 'new requirement';
		return testRequirement;		
	}
	/*
	public static Time_Sheet__c newTimeSheet(Id requirementId)
	{
		Time_Sheet__c testTimeSheet = new Time_Sheet__c();
		//testTimeSheet.Requirement__c = requirementId;
		return testTimeSheet;		
	}
*/
}