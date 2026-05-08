/**
 * Created by Charles on 2/4/2021.
 */

@IsTest

public with sharing class OpportunityUtilsTest {
    public static Lead lead1;
    public static Account accountInternal;
    public static Contact contactInternal;

    @testSetup static void generateData()
    {
        accountInternal = AccountUtils.generateAccount('Internal Account', true);

        contactInternal = ContactUtils.generateContact(accountInternal.Id, true);

        lead1 = LeadUtils.generateLead('FirstName1', 'LastName1', 'Company1', false);
        lead1.Referral_Contact__c = contactInternal.Id;
        insert lead1;
    }
    @isTest static void testLeadLinking(){
        queryTestData();

        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(lead1.id);

        LeadStatus convertStatus = [SELECT Id, MasterLabel FROM LeadStatus WHERE IsConverted=true LIMIT 1];
        lc.setConvertedStatus(convertStatus.MasterLabel);

        Database.LeadConvertResult lcr = Database.convertLead(lc);
        System.assert(lcr.isSuccess());

        Opportunity generatedOpp = [select Id from Opportunity where Lead__c = :lead1.Id limit 1];
        System.assertNotEquals(null, generatedOpp, 'Expect the generated Opportunity record to be linked to the Lead');
    }
    @isTest static void testContactRoleCreation(){
        queryTestData();

        // Convert the Lead to generate customer Account, Contact and Opportunity records
        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(lead1.id);

        LeadStatus convertStatus = [SELECT Id, MasterLabel FROM LeadStatus WHERE IsConverted=true LIMIT 1];
        lc.setConvertedStatus(convertStatus.MasterLabel);

        Database.LeadConvertResult lcr = Database.convertLead(lc);
        System.assert(lcr.isSuccess());

        Opportunity generatedOpp = [select Id from Opportunity where Lead__c = :lead1.Id limit 1];
        List<Contact_Role__c> generatedContactRoles = [select Contact__c, Lead__c, Opportunity__c from Contact_Role__c];
        System.assertNotEquals(null, generatedContactRoles, 'Expect Contact Roles to exist');
        System.assertEquals(1, generatedContactRoles.size(), 'Expect one Contact Role to be generated');
        System.assertEquals(generatedOpp.Id, generatedContactRoles[0].Opportunity__c, 'Expect Contact Role linked to Opportunity');
        System.assertEquals(contactInternal.Id, generatedContactRoles[0].Contact__c, 'Expect Contact Role linked to Internal Contact');
        System.assertEquals(lead1.Id, generatedContactRoles[0].Lead__c, 'Expect Contact Role linked to Lead');
    }
    private static void queryTestData(){
        for(Lead leadRecord : [select Id, FirstName, LastName, Company, Street, City, State, PostalCode, Country from Lead]){
            if(leadRecord.FirstName == 'FirstName1' && leadRecord.LastName == 'LastName1') lead1 = leadRecord;
        }
        contactInternal = [select Id, FirstName, LastName from Contact][0];
    }
}