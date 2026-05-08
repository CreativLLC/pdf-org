trigger TimeSheetAfterIUD on Time_Sheet__c (after delete, after insert, after update) {
	
	Map<Id,Time_Sheet__c> timeSheetMap;
	
	if(trigger.isDelete){
		timeSheetMap = trigger.oldMap;
	}
	else{
		timeSheetMap = trigger.newMap;
	}
	
	List<Time_Sheet__c> tempTimeSheets = 
		[select Id, Invoice__r.Support_Contract__c 
		from Time_Sheet__c 
		where Id in :timeSheetMap.keySet()];
		
	Map<Id, Time_Sheet__c> contractToTimeSheetMap = new Map<Id, Time_Sheet__c>{};
	
	for(Time_Sheet__c ts : tempTimeSheets)
	{
		if(ts.Invoice__r.Support_Contract__c != null)
			contractToTimeSheetMap.put(ts.Invoice__r.Support_Contract__c, ts);
	}
	
	List<Contract> contractsToUpdate = Logic_Contract.rollupTimeSheets(contractToTimeSheetMap.keySet());
	Database.update(contractsToUpdate);
	
}