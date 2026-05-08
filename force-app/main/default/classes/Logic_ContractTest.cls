/**
 * Created by charl on 2/20/2024.
 */

@IsTest
private class Logic_ContractTest {
    public static testMethod void testLogicContractMethods()
    {
        Account testAccount = objectHelperMethods.newAccount();
        database.insert(testAccount);

        Project__c testProject = objectHelperMethods.newProject(testAccount.Id);
        database.insert(testProject);

        Contract testContract = objectHelperMethods.newContract(testAccount.Id);
        testContract.Total_Contract_Hours__c = 10;
        database.insert(testContract);

        Invoice__c testInvoice = objectHelperMethods.newInvoice(testAccount.Id);
        testInvoice.Support_Contract__c = testContract.Id;
        testInvoice.Project__c = testProject.Id;
        testInvoice.Invoice_Start_Date__c = Date.today().addDays(-30);
        testInvoice.Invoice_End_Date__c = Date.today().addDays(-2);
        database.insert(testInvoice);

        Requirement__c testRequirement = objectHelperMethods.newRequirement(testProject.Id);
        database.insert(testRequirement);

        /*Time_Sheet__c testTimeSheet = objectHelperMethods.newTimeSheet(testRequirement.Id);
        testTimeSheet.Date__c = Date.today();
        testTimeSheet.Configuration_Hours__c = 2;
        testTimeSheet.Invoice__c = testInvoice.Id;
        database.insert(testTimeSheet);*/

        Contract verifyContract = [select Id, Available_Contract_Hours__c
        from Contract where Id = :testContract.Id limit 1];

        //System.assertEquals(8, verifyContract.Available_Contract_Hours__c);
    }
}