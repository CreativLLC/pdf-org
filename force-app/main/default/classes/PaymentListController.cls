public with sharing class PaymentListController {
	
	public Acct__c currentAccount {get; set;}
	
	private List<Transaction__c> transQuery {get; set;}
	public List<RollupTransaction> transactions {get; set;}
	private Map<Id, Transaction__c> origTransactions {get; set;}
	
	public PaymentListController(ApexPages.StandardController stdController)
	{
        Map<String, RecordTypeInfo> transactionRecTypeMap = Schema.Sobjecttype.Transaction__c.getRecordTypeInfosByName();
        String recurringRecTypeId = transactionRecTypeMap.get('Recurring').getRecordTypeId();
        
		currentAccount = (Acct__c)stdController.getRecord();
		
		transQuery = new List<Transaction__c> ([select Id, Amount__c, Date__c, To__r.Name, From__r.Name, From__c, Status__c, 
						Budget__c, Name, Instance_Of__r.Name, Instance_Of__r.Id, Confirmation_Number__c, Auto_pay_calc__c
						from Transaction__c 
						where (From__c = :currentAccount.Id 
						or To__c = :currentAccount.Id)
                        and RecordTypeId != :recurringRecTypeId
						and Status__c != 'Cleared' 
						and Status__c != 'Cancelled'
						Order By Date__c]);
		
		Decimal accountBalance = currentAccount.Current_Balance__c;
		transactions = new List<RollupTransaction>{};
		origTransactions = new Map<Id, Transaction__c>();
		
		for(Transaction__c trans : transQuery)
		{
			origTransactions.put(trans.Id, trans.clone(true, true, true, true));
			
			if(trans.From__c == currentAccount.Id)
				accountBalance = accountBalance - trans.Amount__c;
			else
				accountBalance = accountBalance + trans.Amount__c;
            
            String rowLabel = '';
            String rowId = null;
            // If this is an income transaction
            if(trans.To__c == currentAccount.Id){
                rowLabel = trans.From__r.Name;
                rowId = trans.From__c;
            }
            else{
                rowLabel = trans.To__r.Name;
                rowId = trans.To__c;
            }
				
			transactions.add(new RollupTransaction(trans, rowLabel, rowId, accountBalance));
		}	
	}
	
	public PageReference saveTransactions(){
		List<Transaction__c> transactionsToSave = new List<Transaction__c>();
		for(RollupTransaction rt : transactions){
			Transaction__c origTransaction = origTransactions.get(rt.trans.Id);
			
			if(origTransaction == rt.trans){
				
			}
			else{
				transactionsToSave.add(rt.trans);
			}
			
		}
		
		System.debug(LoggingLevel.Error, 'CH: transactionsToSave ' + transactionsToSave);
		Database.update(transactionsToSave);
		
		return null;
	}
}