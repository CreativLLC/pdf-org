public with sharing class Logic_Contract {

	public static List<Contract> rollupTimeSheets(Set<Id> contractIds) {
		// Declare a map of Ids and Contract records
		Map<Id, Contract> contractsMap = new Map<Id, Contract>{};
		
		// Query for the list of Time Sheet records attached
		// 	to specified Ids
		List<Time_Sheet__c> timeSheetRecords = 
			[select Id, Total_Hours__c, Invoice__r.Support_Contract__r.Id 
			from Time_Sheet__c 
			where Invoice__r.Support_Contract__r.Id in :contractIds];
		
		// Iterate through the Time Sheet records and total up hours
		for(Time_Sheet__c ts : timeSheetRecords)
		{
			Contract tempContract = contractsMap.get(ts.Invoice__r.Support_Contract__r.Id);
			
			if(tempContract != null)
			{
				tempContract.Contract_Hours_Used__c = tempContract.Contract_Hours_Used__c + ts.Total_Hours__c;
				contractsMap.put(tempContract.Id, tempContract);
			}
			else
			{
				tempContract = new Contract(Id = ts.Invoice__r.Support_Contract__r.Id);
				tempContract.Contract_Hours_Used__c = ts.Total_Hours__c;
				contractsMap.put(tempContract.Id, tempContract);
			}
		}
		
		// Return the Contract records in the Map
		if(contractsMap.values() != null)
			return contractsMap.values();
		else
			return null;
	}
}