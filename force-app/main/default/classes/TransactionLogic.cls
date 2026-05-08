public with sharing class TransactionLogic {
	public static void upsertInstances(Set<Id> recurringTransactionIds)
	{
		// Look up a couple of Transaction record types
		Map<String, RecordTypeInfo> transactionRecTypeMap = Schema.Sobjecttype.Transaction__c.getRecordTypeInfosByName(); 
		String recurringRecType = transactionRecTypeMap.get('Recurring').getRecordTypeId();
		String instanceRecType = transactionRecTypeMap.get('Instance').getRecordTypeId();
		
		// Query Recurring Transaction Records
		Map<Id, Transaction__c> recTransactionsMap = new Map<Id, Transaction__c>(
			[select Id, Source__c, Destination__c, End_Date__c, 
			Amount__c, Date__c, Recurrence_Number__c, Recurrence_Period__c, Auto_pay__c
			from Transaction__c 
			where Id in :recurringTransactionIds
			and (End_Date__c > :Date.today()
			or End_Date__c = :NULL)
			and RecordTypeId = :recurringRecType]);
			
		// Create a new map for holding records to be upserted
		Map<String, Transaction__c> upsertMap = new Map<String, Transaction__c>{};
		List<Transaction__c> deleteList = new List<Transaction__c>{};
		Map<Id, Integer> indexMap = new Map<Id, Integer>{};
		
		// For each recurring transaction record
		for(Transaction__c recTrans : recTransactionsMap.values())
		{
			// If the recurring transaction doesn't have an end date
			if(recTrans.End_Date__c == null)
			{
				// Temporarily set the end date to be today plus one year
				recTrans.End_Date__c = Date.today().addYears(1);
			}
			
			Integer indexValue = 0;
			Date currentDate = recTrans.Date__c;
			// For each instance record that should exist
			while(currentDate <= recTrans.End_Date__c)
			{
				// If the current date would be after today
				if(currentDate >= Date.today())
				{
					// Create a template record
					Transaction__c newTrans = new Transaction__c();
					newTrans.To__c = recTrans.Destination__c;
					newTrans.From__c = recTrans.Source__c;
					newTrans.Instance_Of__c = recTrans.Id;
					newTrans.Amount__c = recTrans.Amount__c;
					newTrans.Auto_pay__c = recTrans.Auto_pay__c;
					newTrans.Date__c = currentDate;
					newTrans.RecordTypeId = instanceRecType; 
					//  put it in the upsert list with the parent id and index 
					//  	value as the key
					upsertMap.put(recTrans.Id + '.' + indexValue, newTrans);
					
					indexValue++;
				}
				
				if(recTrans.Recurrence_Period__c == 'Day')
					currentDate = currentDate.addDays(recTrans.Recurrence_Number__c.intValue());
				else if(recTrans.Recurrence_Period__c == 'Week')
					currentDate = currentDate.addDays(recTrans.Recurrence_Number__c.intValue() * 7);
				else
					currentDate = currentDate.addMonths(recTrans.Recurrence_Number__c.intValue());
			}
			// Initialize this recurring transaction to the index map
			indexMap.put(recTrans.Id, 0);
		}
		
		// Query Any Existing Transaction Records
		List<Transaction__c> instTransactions = [select Id, To__c, From__c, Amount__c, 
			Date__c, Instance_Of__c, Status__c  
			from Transaction__c
			where Instance_Of__c in :recurringTransactionIds
			and RecordTypeId = :instanceRecType
			and Date__c >= :Date.today()
			order by Date__c asc];
		
		// For each Instance record that exists
		for(Transaction__c instTransRec : instTransactions)
		{
			// Look up the current index value for its recurring transaction
			Integer indexValue = indexMap.get(instTransRec.Instance_Of__c);
			
			// Look up the corresponding template record in the upsert list
			Transaction__c templateRec = upsertMap.get(instTransRec.Instance_Of__c + '.' + indexValue);
			if(templateRec != null)
			{
				if(instTransRec.Status__c == 'Planned' || instTransRec.Status__c == 'Cancelled')
				{
					instTransRec.Amount__c = templateRec.Amount__c;
					instTransRec.Date__c = templateRec.Date__c;
					instTransRec.To__c = templateRec.To__c;
					instTransRec.From__c = templateRec.From__c;
				}
				upsertMap.put(instTransRec.Instance_Of__c + '.' + indexValue, instTransRec);
				indexMap.put(instTransRec.Instance_Of__c, indexValue+1);
			}
			else // If a template record is not found
			{
				// That means that there are too many instance records
				//  so add this one to the list to be deleted
				deleteList.add(instTransRec);	
			}
		}
		
		Database.upsert(upsertMap.values());
		Database.delete(deleteList);
	}
	
	public static List<Transaction__c> generateNewInstances(Transaction__c trans)
	{
        // Look up a couple of Transaction record types
		Map<String, RecordTypeInfo> transactionRecTypeMap = Schema.Sobjecttype.Transaction__c.getRecordTypeInfosByName(); 
		String recurringRecTypeId = transactionRecTypeMap.get('Recurring').getRecordTypeId();
		String instanceRecTypeId = transactionRecTypeMap.get('Instance').getRecordTypeId();
        
		List<Transaction__c> newInstances = new List<Transaction__c>{};
		// Set the beginning Instance date to the start date of the 
		// 	recurring or budget transaction
		Date currentDate = trans.Date__c;
		
		// Determine the end date for the instance transactions
		Date finalDate;
		if(trans.End_Date__c == null)
			finalDate = trans.Date__c.addYears(2);
		else
			finalDate = trans.End_Date__c;
		
		while(currentDate<=finalDate)
		{
			System.debug(currentDate);
			Transaction__c newTrans = new Transaction__c();
			newTrans.Amount__c = trans.Amount__c;
			newTrans.Date__c = currentDate;
			newTrans.From__c = trans.Source__c;
			newTrans.To__c = trans.Destination__c;
			newTrans.Instance_Of__c = trans.Id;
			newTrans.RecordTypeId = instanceRecTypeId;
			newTrans.Status__c = 'Planned';
			newTrans.Budget__c = trans.Budget__c;
			newTrans.Auto_pay__c = trans.Auto_pay__c;
			
			if(trans.Recurrence_Period__c == 'Day')
				currentDate = currentDate.addDays(trans.Recurrence_Number__c.intValue());
			else if(trans.Recurrence_Period__c == 'Week')
				currentDate = currentDate.addDays(trans.Recurrence_Number__c.intValue() * 7);
			else
				currentDate = currentDate.addMonths(trans.Recurrence_Number__c.intValue());
			
			newInstances.add(newTrans);
		}
		
		return newInstances;
	}
	
	public static List<Transaction__c> updateUnpaidInstances(Transaction__c trans)
	{
		List<Transaction__c> setToUpdate = new List<Transaction__c>{};
		
		// Query for Instances that have already been paid
		List<Transaction__c> paidRecords = [select Id, Date__c 
						from Transaction__c
						where Instance_Of__c = :trans.Id
						and Status__c != 'Planned' order by Date__c desc
						limit 1];
					
		// Query for records to be updated
		List<Transaction__c> instanceRecords = [select Id, Date__c, Amount__c, To__c, From__c
							from Transaction__c 
							where Instance_Of__c = :trans.Id 
							and Status__c = 'Planned' order by Date__c];
	 				
	 	// Begin counting dates forward from the start date of 
	 	// 	the recurring transaction
	 	Date startDate = trans.Date__c;
	 				
	 	// Figure out what the last date was that an instance was paid
	 	Date firstDate;
	 	if(paidRecords.size() > 0)
	 		firstDate = paidRecords[0].Date__c;
	 	else
	 		firstDate = trans.Date__c;
	 				
	 	// Start counting forward from the start of the recurring transaction until
	 	// 	we've passed the last date that an instance was paid
	 	while(startDate <= firstDate)
	 	{
	 		if(trans.Recurrence_Period__c == 'Day')
				startDate = startDate.addDays(trans.Recurrence_Number__c.intValue());
			else if(trans.Recurrence_Period__c == 'Week')
				startDate = startDate.addDays(trans.Recurrence_Number__c.intValue() * 7);
			else
				startDate = startDate.addMonths(trans.Recurrence_Number__c.intValue());
		}
	 				 				
	 	// Update remaining instance records that have not been paid yet
		for(Transaction__c inst : instanceRecords)
		{
			// Set values
			inst.Amount__c = trans.Amount__c;
			inst.From__c = trans.Source__c;
			inst.To__c = trans.Destination__c;
			inst.Date__c = startDate;
			inst.Budget__c = trans.Budget__c;
			inst.Status__c = trans.Status__c;
			inst.Auto_pay__c = trans.Auto_pay__c;
	
			// Add to the list to be updated
			setToUpdate.add(inst);
						
			// Advance the date to the next transaction that will be due
			if(trans.Recurrence_Period__c == 'Day')
				startDate = startDate.addDays(trans.Recurrence_Number__c.intValue());
			else if(trans.Recurrence_Period__c == 'Week')
				startDate = startDate.addDays(trans.Recurrence_Number__c.intValue() * 7);
			else
				startDate = startDate.addMonths(trans.Recurrence_Number__c.intValue());					
		}
		
		return setToUpdate;
	}
	
   	public static testMethod void testTransactionAfterSave() 
   	{
        // Look up a couple of Transaction record types
		Map<String, RecordTypeInfo> transactionRecTypeMap = Schema.Sobjecttype.Transaction__c.getRecordTypeInfosByName(); 
		String recurringRecTypeId = transactionRecTypeMap.get('Recurring').getRecordTypeId();
		String instanceRecTypeId = transactionRecTypeMap.get('Instance').getRecordTypeId();
        
   		Acct__c account1 = new Acct__c();
   		Acct__c account2 = new Acct__c();
   		
   		Database.insert(new List<Acct__c>{account1, account2});
   	
   		Transaction__c newRecord = new Transaction__c();
   		newRecord.Amount__c = 10;
   		newRecord.RecordTypeId = recurringRecTypeId;
   		newRecord.Recurrence_Period__c = 'Day';
   		newRecord.Recurrence_Number__c = 1;
   		newRecord.Status__c = 'Planned';
   		newRecord.Date__c = System.today();
   		newRecord.End_Date__c = System.today().addDays(1);
   		newRecord.To__c = account1.Id;
   		newRecord.From__c = account2.Id;
   		
   		Database.insert(new List<Transaction__c> {newRecord});
   		
   		// Directly test TransactionLogic methods
   		TransactionLogic.generateNewInstances(newRecord);
   		TransactionLogic.updateUnpaidInstances(newRecord);
   		TransactionLogic.upsertInstances(new Set<Id>{newRecord.Id});
   		
   		Test.setCurrentPage(new PageReference('/apex/AccountForecast?Id=' + account1.Id));
		AccountForecastController theController = new AccountForecastController();
		
		Test.setCurrentPage(new PageReference('/apex/AccountForecast?Id=' + account2.Id));
		theController = new AccountForecastController();
		
		newRecord.Budget__c = 'Test';
		
   		Database.update(new List<Transaction__c> {newRecord});
   	}
}