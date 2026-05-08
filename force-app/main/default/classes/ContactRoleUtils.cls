public class ContactRoleUtils {
    public static Set<String> openStatuses = new Set<String>{'Active'};
    public static Set<String> closedStatuses = new Set<String>{'Completed','Cancelled'};

    public static Integer uniqueNumber = 0;
    private static Map<String, Schema.RecordTypeInfo> recordTypeMap {
        get{
            if(recordTypeMap == null)
                recordTypeMap = Schema.SObjectType.Contact_Role__c.getRecordTypeInfosByDeveloperName();
            
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

    public static void handleBeforeInsert(){

    }
    public static void handleBeforeUpdate(){

    }
    public static void handleBeforeDelete(){

    }
    public static void handleAfterInsert(){
        // For each new Contact Role
        for (Contact_Role__c contactRole : (List<Contact_Role__c>) Trigger.new) {
            // If the Contact Role is a Project Assignment
            if(contactRole.RecordTypeId == getRecordTypeId('Project_Assignment')){
                // Generate Project Allocation records for the specified time frame
                List<Project_Allocation__c> projectAllocationsToInsert = new List<Project_Allocation__c>();

                // Find the Monday that falls on or before the start date
                Date allocationStart = Date.valueOf(UtilNinja.findPreviousMonday(contactRole.Start_Date__c));
                Date contactRoleEnd = contactRole.End_Date__c != null ? contactRole.End_Date__c : contactRole.Start_Date__c.addDays(365);

                do {
                    Project_Allocation__c projAllocation = ProjectAllocationUtils.generateProjectAllocation(contactRole.Id, allocationStart, Integer.valueOf(contactRole.Hours_Per_Week__c), false);
                    projectAllocationsToInsert.add(projAllocation);
                    allocationStart = allocationStart.addDays(7);
                } while (allocationStart <= contactRoleEnd);

                if(projectAllocationsToInsert.size() > 0){
                    insert projectAllocationsToInsert;
                }
            }
        }
    }
    public static void handleAfterUpdate(){
        Set<Id> assignmentRolesToQuery = new Set<Id>();
        for (Contact_Role__c contactRole : (List<Contact_Role__c>) Trigger.new) {
            Contact_Role__c oldContactRole = (Contact_Role__c) Trigger.oldMap.get(contactRole.Id);

            // If the Contact Role is a Project Assignment
            if(contactRole.RecordTypeId == getRecordTypeId('Project_Assignment')) {
                // If hours, start date, or end date changed add the Contact Role to the
                //  list for querying with child Project Allocations
                if (contactRole.Hours_Per_Week__c != oldContactRole.Hours_Per_Week__c ||
                        contactRole.Start_Date__c != oldContactRole.Start_Date__c ||
                        contactRole.End_Date__c != oldContactRole.End_Date__c ||
                        contactRole.Status__c != oldContactRole.Status__c)
                {
                    assignmentRolesToQuery.add(contactRole.Id);
                }
            }
        }

        // If there are Project Assignment Contact Roles that had something important changed
        if(assignmentRolesToQuery.size() > 0){
            List<Contact_Role__c> changedContactRoles = [select Id, Hours_Per_Week__c, Start_Date__c, End_Date__c, Status__c,
                                                            (select Id, Hours__c, Overridden__c, Start_Date__c, End_Date__c
                                                                from Project_Allocations__r)
                                                            from Contact_Role__c
                                                            where Id in :assignmentRolesToQuery];

            List<Project_Allocation__c> PAsToUpsert = new List<Project_Allocation__c>();
            List<Project_Allocation__c> PAsToDelete = new List<Project_Allocation__c>();

            for(Contact_Role__c contactRole : changedContactRoles){
                Contact_Role__c oldContactRole = (Contact_Role__c) Trigger.oldMap.get(contactRole.Id);

                // If Start Date or End Date changed
                // then Create or Delete Project Allocation records to fit the new timeframe
                if(contactRole.Start_Date__c != oldContactRole.Start_Date__c ||
                    contactRole.End_Date__c != oldContactRole.End_Date__c){

                    Set<String> existingPAKeys = new Set<String>();

                    // Iterate through Project Allocations
                    for (Integer i = (contactRole.Project_Allocations__r.size()-1) ; i>= 0 ; i--){
                        Project_Allocation__c pa = contactRole.Project_Allocations__r[i];

                        // If the Start Date of the Project Allocation falls after the End Date of the Contact Role
                        // OR If the End Date of the Project Allocation falls before the Start Date of the Contact Role
                        //  then add the Project Allocation to the list to delete
                        if(pa.Start_Date__c > contactRole.End_Date__c || pa.End_Date__c < contactRole.Start_Date__c){
                            PAsToDelete.add(pa);
                        }
                        // Otherwise
                        else{
                            // Add a key for the Project Allocation to a Set for identifying existing allocations
                            existingPAKeys.add(String.valueOf(pa.Start_Date__c) + '|' + String.valueOf(pa.End_Date__c));
                        }
                    }

                    // Look for an existing Project Allocation
                    // If a Project Allocation is not found
                    //  then generate a new Project Allocation for the current target timeframe
                    // Start with the Monday on or before the Contact Role start date
                    Date allocationStart = Date.valueOf(UtilNinja.findPreviousMonday(contactRole.Start_Date__c));
                    Date contactRoleEnd = contactRole.End_Date__c != null ? contactRole.End_Date__c : contactRole.Start_Date__c.addDays(365);

                    do {
                        String dateRangeKey = String.valueOf(allocationStart) + '|' + String.valueOf(allocationStart.addDays(6));
                        if(!existingPAKeys.contains(dateRangeKey)){
                            Project_Allocation__c projAllocation = ProjectAllocationUtils.generateProjectAllocation(contactRole.Id, allocationStart, Integer.valueOf(contactRole.Hours_Per_Week__c), false);
                            PAsToUpsert.add(projAllocation);
                        }

                        // Step forward in time, week by week
                        allocationStart = allocationStart.addDays(7);
                    } while (allocationStart <= contactRoleEnd);
                }

                if(contactRole.Hours_Per_Week__c != oldContactRole.Hours_Per_Week__c){
                    // Then populate hours on Project Allocations that are not overridden
                    for(Project_Allocation__c pa : contactRole.Project_Allocations__r){
                        if(!pa.Overridden__c){
                            pa.Hours__c = contactRole.Hours_Per_Week__c;
                            PAsToUpsert.add(pa);
                        }
                    }
                }

                if(contactRole.Status__c != oldContactRole.Status__c){
                    System.debug('oldContactRole.Status__c ' + oldContactRole.Status__c);
                    System.debug('contactRole.Status__c ' + contactRole.Status__c);
                    System.debug('openStatuses.contains(oldContactRole.Status__c) ' + openStatuses.contains(oldContactRole.Status__c));
                    System.debug('closedStatuses.contains(contactRole.Status__c) ' + closedStatuses.contains(contactRole.Status__c));
                    // If the record is moving from an open status to a closed status
                    if(openStatuses.contains(oldContactRole.Status__c) && closedStatuses.contains(contactRole.Status__c)){
                        // Add project allocations to the list to remove
                        for(Project_Allocation__c pa : contactRole.Project_Allocations__r){
                            PAsToDelete.add(pa);
                        }
                    }
                    // If the record is moving from a closed status to an open status
                    else if(closedStatuses.contains(oldContactRole.Status__c) && openStatuses.contains(contactRole.Status__c)){

                    }
                }
            }

            upsert PAsToUpsert;
            delete PAsToDelete;
        }
    }
    public static void handleAfterDelete(){

    }
    public static void handleAfterUndelete(){

    }

    public static Contact_Role__c generateParticipantContactRole(Id contactId, Id leadId, Id opportunityId, Id projectId, Boolean createRecord){
        Id participantTypeId = ContactRoleUtils.getRecordTypeId('Other_Participants');
        Contact_Role__c newContactRole = generateContactRole(contactId, leadId, opportunityId, projectId, participantTypeId, null, null, null, 'Active', 'Test Other', createRecord);
        return newContactRole;
    }
    public static Contact_Role__c generateAssignmentContactRole(Id contactId, Id projectId, Date startDate, Date endDate, Integer hours, Boolean createRecord){
        Id assignmentTypeId = ContactRoleUtils.getRecordTypeId('Project_Assignment');
        return generateContactRole(contactId, null, null, projectId, assignmentTypeId, startDate, endDate, hours, 'Active', 'Test Assignment', createRecord);
    }
    public static Contact_Role__c generateSalesContactRole(Id contactId, Id leadId, Id opportunityId, Id projectId, String commissionType, Decimal commissionAmount, Decimal commissionRate, Boolean createRecord){
        Id salesTypeId = ContactRoleUtils.getRecordTypeId('Sales_Team');
        Contact_Role__c newContactRole = generateContactRole(contactId, leadId, opportunityId, projectId, salesTypeId, null, null,null,'Active', 'Sales Executive', false);
        newContactRole.Fee_Commission_Type__c = commissionType != null ? commissionType : 'Percentage';
        newContactRole.Fee_Commission_Rate__c = commissionRate;
        newContactRole.Fee_Commission_Amount__c = commissionAmount;

        if(createRecord) insert newContactRole;
        return newContactRole;
    }
    public static Contact_Role__c generateReferralContactRole(Id contactId, Id leadId, Id opportunityId, Id projectId, String commissionType, Decimal commissionAmount, Decimal commissionRate, Boolean createRecord){
        Id referralTypeId = ContactRoleUtils.getRecordTypeId('Referral');
        Contact_Role__c newContactRole = generateContactRole(contactId, leadId, opportunityId, projectId, referralTypeId, null, null, null, 'Active', 'Referral Source', false);
        newContactRole.Fee_Commission_Type__c = commissionType != null ? commissionType : 'Percentage';
        newContactRole.Fee_Commission_Rate__c = commissionRate;
        newContactRole.Fee_Commission_Amount__c = commissionAmount;

        if(createRecord) insert newContactRole;
        return newContactRole;
    }
    public static Contact_Role__c generateContactRole(Id contactId, Id leadId, Id opportunityId, Id projectId, Id recordTypeId, Date startDate, Date endDate, Integer hours, String status, String title, Boolean createRecord){
        ContactRoleUtils.uniqueNumber = ContactRoleUtils.uniqueNumber + 1;
        String uniqueVal = String.valueOf(ContactRoleUtils.uniqueNumber);
        Contact_Role__c newContactRole = new Contact_Role__c();
        newContactRole.Contact__c = contactId;
        newContactRole.Lead__c = leadId;
        newContactRole.Opportunity__c = opportunityId;
        newContactRole.Project__c = projectId;
        newContactRole.RecordTypeId = recordTypeId;
        newContactRole.Start_Date__c = startDate;
        newContactRole.End_Date__c = endDate;
        newContactRole.Hours_Per_Week__c = hours;
        newContactRole.Status__c = status;
        newContactRole.Title__c = title;

        if(createRecord) insert newContactRole;
        return newContactRole;
    }
}