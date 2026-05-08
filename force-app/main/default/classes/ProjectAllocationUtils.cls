public class ProjectAllocationUtils {
    public static void handleBeforeInsert(){

    }
    public static void handleBeforeUpdate(){
        // Get Contact Roles referenced by project allocations with updated hours
        Set<Id> referencedRoles = new Set<Id>();
        for(Project_Allocation__c projectAllocation : (List<Project_Allocation__c>) Trigger.new){
            Project_Allocation__c oldProjectAllocation = (Project_Allocation__c) Trigger.oldMap.get(projectAllocation.Id);
            if(projectAllocation.Hours__c != oldProjectAllocation.Hours__c){
                referencedRoles.add(projectAllocation.Contact_Role__c);
            }
        }

        // If there are any referenced Contact Roles
        if(referencedRoles.size() > 0){
            Map<Id, Contact_Role__c> contactRoleMap = new Map<Id, Contact_Role__c>([select Id, Hours_Per_Week__c from Contact_Role__c where Id in :referencedRoles]);

            for(Project_Allocation__c projectAllocation : (List<Project_Allocation__c>) Trigger.new){
                Project_Allocation__c oldProjectAllocation = (Project_Allocation__c) Trigger.oldMap.get(projectAllocation.Id);
                if(projectAllocation.Hours__c != oldProjectAllocation.Hours__c){
                    Contact_Role__c contactRole = contactRoleMap.get(projectAllocation.Contact_Role__c);
                    if(projectAllocation.Hours__c <> contactRole.Hours_Per_Week__c)
                        projectAllocation.Overridden__c = true;
                    else
                        projectAllocation.Overridden__c = false;
                }
            }
        }
    }
    public static void handleBeforeDelete(){

    }
    public static void handleAfterInsert(){

    }
    public static void handleAfterUpdate(){

    }
    public static void handleAfterDelete(){

    }
    public static void handleAfterUndelete(){

    }
    public static Project_Allocation__c generateProjectAllocation(Id contactRoleId, Date startDate, Integer hours, Boolean createRecord){
        Project_Allocation__c projAllocation = new Project_Allocation__c();
        projAllocation.Contact_Role__c = contactRoleId;
        projAllocation.Start_Date__c = startDate;
        projAllocation.Hours__c = hours;

        if(createRecord) insert projAllocation;
        return projAllocation;
    }
}