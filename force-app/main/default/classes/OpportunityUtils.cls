public class OpportunityUtils {
    public static Integer uniqueNumber = 0;
    public static void handleBeforeInsert(){
        for(Opportunity record : (List<Opportunity>) Trigger.new)
		{
            // Set the Quote Valid Until date value
            if(record.Quote_Valid_For__c == '30 Days')
                record.Quote_Valid_Until__c = Date.today().addDays(30);
            else if(record.Quote_Valid_For__c == '60 Days')
                record.Quote_Valid_Until__c = Date.today().addDays(60);
            else if(record.Quote_Valid_For__c == '90 Days')
                record.Quote_Valid_Until__c = Date.today().addDays(90);
            else if(record.Quote_Valid_For__c == '6 Months')
                record.Quote_Valid_Until__c = Date.today().addMonths(6);
            else if(record.Quote_Valid_For__c == '1 Year')
                record.Quote_Valid_Until__c = Date.today().addYears(1);
            else
                record.Quote_Valid_Until__c = Date.today().addDays(30);
            
            record.Lead__c = record.Lead_Id_Passable__c;
    	}
    }
    public static void handleBeforeUpdate(){
        
    }
    public static void handleBeforeDelete(){
        
    }
    public static void handleAfterInsert(){
        // Query Leads to create a list of Referral Contacts that need Contact Roles created
        Set<Id> leadsToQuery = new Set<Id>();
        for(Opportunity record : (List<Opportunity>) Trigger.new)
		{
            if(record.Lead__c != null) 
                leadsToQuery.add(record.Lead__c);
    	}
        
        Map<Id, Lead> leadMap = new Map<Id, Lead>([select Id, Referral_Contact__c from Lead where Id in :leadsToQuery]);
        
        // If there are any Lead records with Referral Contacts
        if(leadMap != null && leadMap.values().size() > 0){
            List<Contact_Role__c> contactRolesToCreate = new List<Contact_Role__c>();
            Id referralRecordTypeId = ContactRoleUtils.getRecordTypeId('Referral');
        	for(Opportunity record : (List<Opportunity>) Trigger.new)
			{
            	if(record.Lead__c != null){
                	Lead referencedLead = leadMap.get(record.Lead__c);
                	if(referencedLead.Referral_Contact__c != null){
                    	contactRolesToCreate.add(new Contact_Role__c(
                                                    Lead__c = referencedLead.Id,
                            						Contact__c = referencedLead.Referral_Contact__c, 
                            						Opportunity__c = record.Id, 
                            						RecordTypeId = referralRecordTypeId,
                        							Fee_Commission_Type__c = 'Percentage',
                        							Fee_Commission_Rate__c = 3.00,
                        							Status__c = 'Active',
                        							Title__c = 'Referral Source'));
                	}
            	}
    		}
            
            if(contactRolesToCreate.size() > 0){
                Database.insert(contactRolesToCreate);
            }
		}
    }
    public static void handleAfterUpdate(){
        
    }
    public static void handleAfterDelete(){
        
    }
    public static void handleAfterUndelete(){
        
    }

    public static Opportunity generateOpportunity(Id accountId, Boolean createRecord){
        return generateOpportunity(null, accountId, null, null, createRecord);
    }
    public static Opportunity generateOpportunity(String name, Id accountId, Boolean createRecord){
        return generateOpportunity(name, accountId, null, null, createRecord);
    }
    public static Opportunity generateOpportunity(String name, Id accountId, String stageName, Date closeDate, Boolean createRecord){
        OpportunityUtils.uniqueNumber = OpportunityUtils.uniqueNumber + 1;
        String uniqueVal = String.valueOf(OpportunityUtils.uniqueNumber);
        Opportunity newOpportunity = new Opportunity();
        newOpportunity.Name = name != null ? name : 'TestOppName' + uniqueVal;
        newOpportunity.AccountId = accountId;
        newOpportunity.StageName = stageName != null ? stageName : 'Prospecting';
        newOpportunity.CloseDate = closeDate != null ? closeDate : Date.today().addDays(10);

        if(createRecord) insert newOpportunity;
        return newOpportunity;
    }
}