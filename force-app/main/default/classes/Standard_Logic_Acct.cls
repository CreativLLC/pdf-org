public with sharing class Standard_Logic_Acct {

	public static Acct__c createFinancialAccount(String acctName, String recTypeId, String acctType, Boolean insertAcct)
	{
		Acct__c newAcct = new Acct__c();
		newAcct.RecordTypeId = recTypeId;
		newAcct.Type__c = acctType;
		newAcct.Name = acctName;
		
		if(insertAcct)
			Database.insert(newAcct);
		
		return newAcct;
	}
	/*
	public static Acct__c createFinancialAccount(String acctName, String recTypeId, Boolean insertAcct)
	{
		return createFinancialAccount(acctName, recTypeId, null, insertAcct);
	}
	
	public static Acct__c createFinancialAccount(String acctName, Boolean insertAcct)
	{
		return createFinancialAccount(acctName, null, null, insertAcct);
	}
*/
}