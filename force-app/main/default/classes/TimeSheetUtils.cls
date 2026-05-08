public class TimeSheetUtils {

    public static void beforeInsert() {
        // Try to populate the Done_By__c field based on Done_By_Name__c
        // Try to populate the Project__c field based on Project_Name__c
        // Format and populate the Date__c field based on Work_Date__c
        
        // Iterate through trigger records
        Set<String> matchingKeySet = new Set<String>();
        for(Time_Sheet__c ts : (List<Time_Sheet__c>) trigger.new){
            matchingKeySet.add(ts.Done_By_Name__c + '-' + ts.Project_Name__c);
        }
        
        // Query Contact Role records based on constructed keys for Done By and Project
        Map<String, Contact_Role__c> contactRoleMap = new Map<String, Contact_Role__c>();
        for(Contact_Role__c contactRole : [select Id, Contact__c, Project__c, Jira_Matching_Key__c 
                                           from Contact_Role__c 
                                           where Jira_Matching_Key__c in :matchingKeySet
                                          and Status__c = 'Active' 
                                          order by CreatedDate desc]){
            contactRoleMap.put(contactRole.Jira_Matching_Key__c, contactRole);
        }
        
        // Match Timesheets to Contact Roles and populate lookup fields
        for(Time_Sheet__c ts : (List<Time_Sheet__c>) trigger.new){
            Contact_Role__c cr = contactRoleMap.get(ts.Done_By_Name__c + '-' + ts.Project_Name__c);
            System.debug('Contact_Role__c: ' + cr);
            if(cr != null){
                ts.Contact_Role__c = cr.Id;
                ts.Done_By__c = cr.Contact__c;
            	ts.Project__c = cr.Project__c;
            }
            if(ts.Date__c == null) ts.Date__c = UtilNinja.convertTempoDateString(ts.Work_Date__c);
            System.debug('ts.Done_By__c ' + ts.Done_By__c);
            System.debug('ts.Project__c ' + ts.Project__c);
            System.debug('ts.Hours__c ' + ts.Hours__c);
            System.debug('ts.Date__c ' + ts.Date__c);
            System.debug('ts.Done_By__c ' + ts.Done_By__c);
        }
    }
    
    public static void beforeUpdate() {
        
        // Iterate through trigger records
        Set<String> matchingKeySet = new Set<String>();
        for(Time_Sheet__c ts : (List<Time_Sheet__c>) trigger.new){
            Time_Sheet__c oldTS = (Time_Sheet__c) trigger.oldMap.get(ts.Id);
            if(ts.Done_By_Name__c != oldTS.Done_By_Name__c || ts.Project_Name__c != oldTS.Project_Name__c || ts.Contact_Role__c == null){
                matchingKeySet.add(ts.Done_By_Name__c + '-' + ts.Project_Name__c);
            }
        }
        
        // Query Contact Role records based on constructed keys for Done By and Project
        Map<String, Contact_Role__c> contactRoleMap = new Map<String, Contact_Role__c>();
        for(Contact_Role__c contactRole : [select Id, Contact__c, Project__c, Jira_Matching_Key__c 
                                           from Contact_Role__c 
                                           where Jira_Matching_Key__c in :matchingKeySet
                                          and Status__c = 'Active'
                                          order by CreatedDate desc]){
            contactRoleMap.put(contactRole.Jira_Matching_Key__c, contactRole);
        }
        
        // Match Timesheets to Contact Roles and populate lookup fields
        for(Time_Sheet__c ts : (List<Time_Sheet__c>) trigger.new){
            Time_Sheet__c oldTS = (Time_Sheet__c) trigger.oldMap.get(ts.Id);
            if(ts.Done_By_Name__c != oldTS.Done_By_Name__c || ts.Project_Name__c != oldTS.Project_Name__c || ts.Contact_Role__c == null){
                Contact_Role__c cr = contactRoleMap.get(ts.Done_By_Name__c + '-' + ts.Project_Name__c);
                if(cr != null){
                    ts.Contact_Role__c = cr.Id;
                    ts.Done_By__c = cr.Contact__c;
                    ts.Project__c = cr.Project__c;
                }
            }
            if(ts.Work_Date__c != oldTS.Work_Date__c || ts.Date__c == null) ts.Date__c = UtilNinja.convertTempoDateString(ts.Work_Date__c);
        }
    }

    //public static void beforeDelete(Map<Id, SObject> newSObjects, Map<Id, SObject> oldSObjects) { }
    
    //public static void afterInsert(Map<Id, SObject> newSObjects) { }

    //public static void afterUpdate(Map<Id, SObject> newSObjects, Map<Id, SObject> oldSObjects) { }

    //public static void afterDelete(Map<Id, SObject> oldSObjects) { }

    //public static void afterUnDelete(Map<Id, SObject> newSObjects) { }

   
    
    /*public static Time_Sheet__c createRecord(Boolean insertRecord){
        Time_Sheet__c newTimeSheet = new Time_Sheet__c();
        if(insertRecord) insert newTimeSheet;
        return newTimeSheet;
    }*/
    
    public static Time_Sheet__c createRecord(Boolean insertRecord){
        return createRecord(null, null, Date.today(), insertRecord);
    }
    
    public static Time_Sheet__c createRecord(String doneByName, String projectName, Date workDate, Boolean insertRecord){
        Time_Sheet__c newTimeSheet = new Time_Sheet__c();
        newTimeSheet.Done_By_Name__c = doneByName;
        newTimeSheet.Project_Name__c = projectName;
        newTimeSheet.Date__c = workDate;
        if(insertRecord) insert newTimeSheet;
        return newTimeSheet;
    }
}