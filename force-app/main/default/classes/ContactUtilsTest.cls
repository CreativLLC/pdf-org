/**
 * Created by Charles on 2/4/2021.
 */

@IsTest
private class ContactUtilsTest {
    public static Lead lead1;

    @testSetup static void generateData()
    {
        lead1 = LeadUtils.generateLead('FirstName1', 'LastName1', 'Company1', true);
    }
    @isTest static void testLeadLinking(){
        queryTestData();

        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(lead1.id);

        LeadStatus convertStatus = [SELECT Id, MasterLabel FROM LeadStatus WHERE IsConverted=true LIMIT 1];
        lc.setConvertedStatus(convertStatus.MasterLabel);

        Database.LeadConvertResult lcr = Database.convertLead(lc);
        System.assert(lcr.isSuccess());

        Contact generatedContact = [select Id from Contact where Lead__c = :lead1.Id limit 1];
        System.assertNotEquals(null, generatedContact, 'Expect the generated Contact record to be linked to the Lead');
    }
    private static void queryTestData(){
        for(Lead leadRecord : [select Id, FirstName, LastName, Company, Street, City, State, PostalCode, Country from Lead]){
            if(leadRecord.FirstName == 'FirstName1' && leadRecord.LastName == 'LastName1') lead1 = leadRecord;
        }
    }
}