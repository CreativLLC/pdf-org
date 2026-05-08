public with sharing class AccountForecastController {

	Id accountId;
	public Acct__c currentAccount {get; set;}
	Double currentAmount;
	List<Transaction__c> transactionList = new List<Transaction__c>{};
	public List<dataTableRow> transactionTable {get; set;}

	public AccountForecastController()
	{
		accountId = ApexPages.currentPage().getParameters().get('Id');
		transactionTable = new List<dataTableRow>();
		
		// Query for Account's current balance
		currentAccount = [select Id, Name, Current_Balance__c from Acct__c where Id = :accountId];
		currentAmount = currentAccount.Current_Balance__c;
		
		// Query for Transaction coming from or going into this Account
		transactionList = [select Id, Amount__c, Date__c, To__r.Name, From__r.Name, Status__c, 
							Budget__c 
							from Transaction__c 
							where (From__c = :accountId or To__c = :accountId) 
							and (Status__c = 'Planned' or Status__c = 'Paid') order by Date__c];
							
		for(Transaction__c trans : transactionList)
		{
			dataTableRow newRow = new dataTableRow();
			
			newRow.item1 = String.valueOf(trans.Date__c);
			
			if(trans.From__c == accountId)
			{
				if(trans.To__r.Name != null)
					newRow.item2 = trans.To__r.Name;
				else
					newRow.item2 = trans.Budget__c;
					
				trans.Amount__c = -trans.Amount__c;
				newRow.item8 = trans.To__c;
				newRow.item9 = 'FFFFFF';
				
				if(trans.Status__c == 'Paid')
					newRow.item10 = '00FF00';
				else
					newRow.item10 = 'FF0000';
			}
			else
			{
				newRow.item2 = trans.From__r.Name;
				newRow.item8 = trans.From__c;
				newRow.item9 = 'CCCCCC';
				newRow.item10 = '000000';
			}
			
			newRow.item3 = String.valueOf(trans.Amount__c);
			
			currentAmount = currentAmount + trans.Amount__c;
			newRow.item4 = String.valueOf(currentAmount);
			
			//newRow.item5 = String.valueOf(currentAmount/(Date.today().daysBetween(trans.Date__c)+1));
			
			transactionTable.add(newRow);
		}
	}

}