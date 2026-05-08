@IsTest
public class InvoicePDFcontrollerTest {
    public static Account account1;
    public static Project__c project1;
    public static Invoice__c invoice1;
    public static List<Time_Sheet__c> timeSheets;

    @testSetup static void generateData()
    {
        account1 = AccountUtils.generateAccount('Account1', true);
        project1 = ProjectUtils.generateProject('Test Project', account1.Id, ProjectUtils.getRecordTypeId('Active'), null, 'New', true);
        invoice1 = InvoiceUtils.generateInvoice(project1.Id, account1.Id, Date.today().addDays(-10), Date.today(), 1000.00, null, null, true);
        
        timeSheets = new List<Time_Sheet__c>();
        for(Integer i=-10; i<=0; i++){
            Time_Sheet__c newTimeSheet = new Time_Sheet__c();
            newTimeSheet.Project__c = project1.Id;
            newTimeSheet.Date__c = Date.today().addDays(i);
            newTimeSheet.Hours__c = 1;
            timeSheets.add(newTimeSheet);
        }
        Database.insert(timeSheets);
    }
    
    @isTest static void testInvoicePDFPageLoad(){
        queryTestData();
        
        PageReference pageRef = Page.InvoicePDF;
        pageRef.getParameters().put('id', String.valueOf(invoice1.Id));
        Test.setCurrentPage(pageRef);
        InvoicePDFController controller = new InvoicePDFController();
        System.assertEquals(11, controller.totalHours, 'Expect total hours to be 11');
    }
    
    private static void queryTestData(){
        for(Account accountRecord : [select Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry from Account]){
            if(accountRecord.Name == 'Account1') account1 = accountRecord;
        }
        for(Project__c projectRecord : [select Id, Name from Project__c]){
            if(projectRecord.Name == 'Test Project') project1 = projectRecord;
        }
        for(Invoice__c invoiceRecord : [select Id, Name, Project__c from Invoice__c]){
            if(invoiceRecord.Project__c == project1.Id) invoice1 = invoiceRecord;
        }
    }
}