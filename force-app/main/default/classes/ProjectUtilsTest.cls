@isTest
public class ProjectUtilsTest {
    public static Account account1;
    public static Contact referralContact;
    public static Contact salesContact;
    public static Opportunity opportunity1;
    public static Project__c project1;
    public static Contact_Role__c referralRole;
    public static Contact_Role__c salesRole;

    @testSetup
    static void generateData()
    {
        account1 = AccountUtils.generateAccount('Account1', true);
        referralContact = ContactUtils.generateContact('Referral', 'Contact', account1.Id, true);
        salesContact = ContactUtils.generateContact('Sales', 'Contact', account1.Id, true);
        opportunity1 = OpportunityUtils.generateOpportunity('Opportunity1', account1.Id, true);
        referralRole = ContactRoleUtils.generateReferralContactRole(referralContact.Id, null, opportunity1.Id, null, 'Percentage', 0, 3, true);
        salesRole = ContactRoleUtils.generateSalesContactRole(salesContact.Id, null, opportunity1.Id, null, 'Percentage', 0, 3, true);
    }

    private static testMethod void testNewProjectInsertion(){
        queryTestData();
        Test.startTest();
        Project__c testProject = ProjectUtils.generateProject('Test Project', account1.Id, ProjectUtils.getRecordTypeId('Active'), opportunity1.Id, 'New', true);
        Test.stopTest();

        // Verify that both Contact Roles were linked to the new Project
        for(Contact_Role__c contactRoleRecord : [select Id, Contact__c, Opportunity__c, Project__c from Contact_Role__c]){
            if(contactRoleRecord.Contact__c == referralContact.Id && contactRoleRecord.Opportunity__c == opportunity1.Id) referralRole = contactRoleRecord;
            else if(contactRoleRecord.Contact__c == salesContact.Id && contactRoleRecord.Opportunity__c == opportunity1.Id) salesRole = contactRoleRecord;
        }

        System.assertEquals(testProject.Id, referralRole.Project__c, 'Expect that the referral role is linked to the new Project');
        System.assertEquals(testProject.Id, salesRole.Project__c, 'Expect that the sales role is linked to the new Project');
    }

    private static void queryTestData(){
        for(Account accountRecord : [select Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry from Account]){
            if(accountRecord.Name == 'Account1') account1 = accountRecord;
        }
        for(Contact contactRecord : [select Id, Name from Contact]){
            if(contactRecord.Name == 'Referral Contact') referralContact = contactRecord;
            else if(contactRecord.Name == 'Sales Contact') salesContact = contactRecord;
        }
        for(Opportunity opportunityRecord : [select Id, Name from Opportunity]){
            if(opportunityRecord.Name == 'Opportunity1') opportunity1 = opportunityRecord;
        }
        for(Contact_Role__c contactRoleRecord : [select Id, Contact__c, Opportunity__c from Contact_Role__c]){
            if(contactRoleRecord.Contact__c == referralContact.Id && contactRoleRecord.Opportunity__c == opportunity1.Id) referralRole = contactRoleRecord;
            else if(contactRoleRecord.Contact__c == salesContact.Id && contactRoleRecord.Opportunity__c == opportunity1.Id) salesRole = contactRoleRecord;
        }
    }
}