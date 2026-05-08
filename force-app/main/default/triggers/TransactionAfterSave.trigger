trigger TransactionAfterSave on Transaction__c (after insert, after update) 
{
    // Initiate the set of records to be inserted or updated
    Map<String, RecordTypeInfo> transRecTypeMap = Schema.Sobjecttype.Transaction__c.getRecordTypeInfosByName();
    String transIdRecurring = transRecTypeMap.get('Recurring').getRecordTypeId();
    String transIdBudget = transRecTypeMap.get('Budget').getRecordTypeId();
    String transIdInstance = transRecTypeMap.get('Instance').getRecordTypeId();
    
    Set<Id> recurringTransIds = new Set<Id>{};
    
    List<Transaction__c> transactionsToUpsert = new List<Transaction__c>();
    
    // Iterate through the Transaction Records that are being saved
    for(Transaction__c trans : trigger.new){    
        // If this is a Budget or Recurring transaction
        if(trans.RecordTypeId == transIdBudget){
            // If we're inserting a new Recurring or Budget transaction
            if(Trigger.isInsert)
                transactionsToUpsert.addAll(TransactionLogic.generateNewInstances(trans));
            else // Otherwise it's an update
                transactionsToUpsert.addAll(TransactionLogic.updateUnpaidInstances(trans));
        } // End Record Type If
        else if(trans.RecordTypeId == transIdRecurring){
            recurringTransIds.add(trans.Id);
        }
        else if(trans.RecordTypeId == transIdInstance){
            if(trigger.isUpdate 
                && trigger.oldMap.get(trans.Id).Status__c != trans.Status__c 
                && (trans.Status__c == 'Cleared' 
                || trans.Status__c == 'Cancelled'))
            {
                recurringTransIds.add(trans.Instance_Of__c);
            }
        }
    }
    
    if(transactionsToUpsert.size() > 0){
        Database.upsert(transactionsToUpsert);
    }
    
    if(recurringTransIds.size() > 0){
        TransactionLogic.upsertInstances(recurringTransIds);        
    }
}