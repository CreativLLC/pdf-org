/**
 * Created by charl on 3/10/2023.
 */

@IsTest
public class ProjectAllocationUtilsTest {
    public static Account account1;
    public static Contact resourceContact;
    public static Opportunity opportunity1;
    public static Project__c project1;
    public static Contact_Role__c resourceRole;

    @testSetup static void generateData()
    {
        account1 = AccountUtils.generateAccount('Account1', true);
        resourceContact = ContactUtils.generateContact('Resource', 'Contact', account1.Id, true);
        opportunity1 = OpportunityUtils.generateOpportunity('Opportunity1', account1.Id, true);
        project1 = ProjectUtils.generateProject('Project1', account1.Id, null, opportunity1.Id, null, true);
        resourceRole = ContactRoleUtils.generateAssignmentContactRole(resourceContact.Id, project1.Id, Date.today(), null, null, true);
    }
    @isTest static void testOverriddenUpdating(){
        queryTestData();
        resourceRole.Hours_Per_Week__c = 6;
        update resourceRole;

        Project_Allocation__c projAllocation = new Project_Allocation__c();
        projAllocation.Contact_Role__c = resourceRole.Id;
        projAllocation.Hours__c = 6;
        projAllocation.Start_Date__c = Date.today();
        insert projAllocation;

        projAllocation.Hours__c = 4;
        update projAllocation;

        projAllocation = [select Id, Overridden__c, Hours__c from Project_Allocation__c where Id = :projAllocation.Id];
        System.assert(projAllocation.Overridden__c, 'Expect project Allocation to be marked as overridden');

        projAllocation.Hours__c = 6;
        update projAllocation;

        projAllocation = [select Id, Overridden__c, Hours__c from Project_Allocation__c where Id = :projAllocation.Id];
        System.assert(!projAllocation.Overridden__c, 'Expect project Allocation not to be marked as overridden');
    }
    private static void queryTestData(){
        for(Account accountRecord : [select Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry from Account]){
            if(accountRecord.Name == 'Account1') account1 = accountRecord;
        }
        for(Contact contactRecord : [select Id, Name from Contact]){
            if(contactRecord.Name == 'Resource Contact') resourceContact = contactRecord;
        }
        for(Opportunity opportunityRecord : [select Id, Name from Opportunity]){
            if(opportunityRecord.Name == 'Opportunity1') opportunity1 = opportunityRecord;
        }
        for(Project__c projectRecord : [select Id, Name from Project__c]){
            if(projectRecord.Name == 'Project1') project1 = projectRecord;
        }

        for(Contact_Role__c contactRoleRecord : [select Id, Contact__c, Project__c from Contact_Role__c]){
            if(contactRoleRecord.Contact__c == resourceContact.Id && contactRoleRecord.Project__c == project1.Id) resourceRole = contactRoleRecord;
        }
    }
}