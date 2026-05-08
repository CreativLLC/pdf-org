/**
 * Created by Charles on 2/4/2021.
 */

@IsTest
public class AccountUtilsTest {
    public static Lead lead1;
    public static Account account1;
    public static Account account2;
    
    
    @testSetup static void generateData()
    {
        lead1 = LeadUtils.generateLead('FirstName1', 'LastName1', 'Company1', true);
        account1 = AccountUtils.generateAccount('Test Account', false);
        account2 = AccountUtils.generateAccount('Test Account2', false);
        Database.insert(new List<Account>{account1,account2});
        
    }
    @isTest static void testAccountFieldDefaults(){
        queryTestData();
        
        account1.Parent_Account__c = account2.Id;
        update account1;
    }    
    @isTest static void testLeadConversionLinking(){
        queryTestData();
        
        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(lead1.id);
        
        LeadStatus convertStatus = [SELECT Id, MasterLabel FROM LeadStatus WHERE IsConverted=true LIMIT 1];
        lc.setConvertedStatus(convertStatus.MasterLabel);
        
        Database.LeadConvertResult lcr = Database.convertLead(lc);
        System.assert(lcr.isSuccess());
        
        Account generatedAccount = [select Id from Account where Lead__c = :lead1.Id limit 1];
        System.assertNotEquals(null, generatedAccount, 'Expect the generated Account record to be linked to the Lead');
    }
    private static void queryTestData(){
        for(Lead leadRecord : [select Id, FirstName, LastName, Company, Street, City, State, PostalCode, Country from Lead]){
            if(leadRecord.FirstName == 'FirstName1' && leadRecord.LastName == 'LastName1') lead1 = leadRecord;
        }
        
        for(Account accountRecord : [select Id, Name from Account]){
            if(accountRecord.Name == 'Test Account') account1 = accountRecord;
            if(accountRecord.Name == 'Test Account2') account2 = accountRecord;
        }
    }
}