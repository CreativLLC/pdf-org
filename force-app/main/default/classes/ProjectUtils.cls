public class ProjectUtils {
    public static Integer uniqueNumber = 0;
    private static Map<String, Schema.RecordTypeInfo> recordTypeMap {
        get{
            if(recordTypeMap == null)
                recordTypeMap = Schema.SObjectType.Project__c.getRecordTypeInfosByDeveloperName();

            return recordTypeMap;
        }
        set;
    }
    public static Id getRecordTypeId(String developerName){
        Schema.RecordTypeInfo recordTypeInfo = recordTypeMap.get(developerName);
        if(recordTypeInfo == null)
            return null;
        else
            return recordTypeInfo.getRecordTypeId();
    }

    /* Trigger Handlers */
	public static void handleBeforeInsert(){
    }
    public static void handleBeforeUpdate(){
    }
    public static void handleBeforeDelete(){  
    }
    public static void handleAfterInsert(){ 
        // Collect the list of Opportunities to look for active Contact Roles
        Set<Id> opportunitiesToQuery = new Set<Id>();
        for(Project__c currentProject : (List<Project__c>) Trigger.new){
            if(currentProject.Opportunity__c != null){
                opportunitiesToQuery.add(currentProject.Opportunity__c);
            }
        }
        
        Map<Id, Opportunity> opportunityMap = new Map<Id, Opportunity>([select Id, (select Id from Contact_Role__r where Status__c = 'Active') from Opportunity where Id in :opportunitiesToQuery]);
        
        // Look up Contact Roles connected to related Opportunities to tie to the newly created Project
        List<Contact_Role__c> contactRolesToUpdate = new List<Contact_Role__c>();
        for(Project__c currentProject : (List<Project__c>) Trigger.new){
            if(currentProject.Opportunity__c != null){
                Opportunity opp = opportunityMap.get(currentProject.Opportunity__c);
                if(opp != null){
                    for(Contact_Role__c cr : opp.Contact_Role__r){
                        cr.Project__c = currentProject.Id;
                        contactRolesToUpdate.add(cr);
                    }
                }
            }
        }
        if(contactRolesToUpdate.size() > 0 ){
            Database.update(contactRolesToUpdate);
        }
    }
    public static void handleAfterUpdate(){ 
    }
    public static void handleAfterDelete(){  
    }
    public static void handleAfterUndelete(){  
    }
    public static Project__c generateProject(String name, Id accountId, Id opportunityId, Boolean createRecord){
        Id recordTypeId = getRecordTypeId('Active');
        return generateProject(name, accountId, recordTypeId, opportunityId, 'New', createRecord);
    }

    public static Project__c generateProject(String name, Id accountId, Id recordTypeId, Id opportunityId, String status, Boolean createRecord){
        ProjectUtils.uniqueNumber = ProjectUtils.uniqueNumber + 1;
        String uniqueVal = String.valueOf(ProjectUtils.uniqueNumber);
        Project__c newProject = new Project__c();
        newProject.Name = name == null ? 'ProjectName'+uniqueVal : name;
        newProject.Account__c = accountId;
        newProject.Opportunity__c = opportunityId;
        newProject.RecordTypeId = recordTypeId == null ? getRecordTypeId('Active') : recordTypeId;
        newProject.Status__c = status == null ? 'New' : status;

        if(createRecord) insert newProject;
        return newProject;
    }
}