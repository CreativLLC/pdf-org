/**
 * Created by Charles on 2/3/2021.
 */
@IsTest
public with sharing class InvoiceUtilsTest {
    public static Account account1;
    public static Contact referralContact;
    public static Contact salesContact;
    public static Opportunity opportunity1;
    public static Project__c project1;
    public static Contact_Role__c referralRole;
    public static Contact_Role__c salesRole;

    @testSetup static void generateData()
    {
        account1 = AccountUtils.generateAccount('Account1', true);
        referralContact = ContactUtils.generateContact('Referral', 'Contact', account1.Id, true);
        salesContact = ContactUtils.generateContact('Sales', 'Contact', account1.Id, true);
        opportunity1 = OpportunityUtils.generateOpportunity('Opportunity1', account1.Id, true);
        project1 = ProjectUtils.generateProject('Test Project', account1.Id, ProjectUtils.getRecordTypeId('Active'), opportunity1.Id, 'New', true);

        referralRole = ContactRoleUtils.generateReferralContactRole(referralContact.Id, null, opportunity1.Id, project1.Id, 'Percentage', 0, 3, true);
        salesRole = ContactRoleUtils.generateSalesContactRole(salesContact.Id, null, opportunity1.Id, project1.Id, 'Percentage', 0, 6, true);
    }
    @isTest static void testReferralFeeCreation(){
        queryTestData();
        Test.startTest();
        InvoiceUtils.generateInvoice(project1.Id, account1.Id, null, null, 1000.00, 0.00, null, true);
        Test.stopTest();

        List<Referral_Commission_Payment__c> payments = [select Id, Contact_Role__c, Invoice__c, Payment_Amount__c
                                                            from Referral_Commission_Payment__c];

        System.assertEquals(2, payments.size(), 'Expect two Referral Commission Payments to be created');
        Boolean referralPaymentFound = false;
        Boolean commissionPaymentFound = false;
        for(Referral_Commission_Payment__c payment : payments){
            if(payment.Contact_Role__c == referralRole.Id){
                System.assertEquals(30, payment.Payment_Amount__c, 'Expect the referral payment to be 3% of the Invoice total');
                referralPaymentFound = true;
            }
            else if(payment.Contact_Role__c == salesRole.Id){
                System.assertEquals(60, payment.Payment_Amount__c, 'Expect the sales commission payment to be 6% of the Invoice total');
                commissionPaymentFound = true;
            }
        }
        System.assert(referralPaymentFound, 'Expect that a Referral Payment was created, with the correct amount');
        System.assert(commissionPaymentFound, 'Expect that a Sales Commission Payment was created, with the correct amount');
    }
    @isTest static void testPaymentDaysDefault(){
        queryTestData();
        Invoice__c testInvoice = InvoiceUtils.generateInvoice(project1.Id, account1.Id, null, null, 1000.00, 0.00, null, true);
        testInvoice.Payment_Days__c = null;
        Test.startTest();
        update testInvoice;
        Test.stopTest();
    }
    @isTest static void testDepositInvoice(){
        queryTestData();
        Invoice__c depositInvoice = InvoiceUtils.generateInvoice(project1.Id, account1.Id, null, null, 0.00, 1000.00, null, false);
        depositInvoice.Amount_Received__c = 1000.00;
        insert depositInvoice;
        
        Invoice__c testInvoice = InvoiceUtils.generateInvoice(project1.Id, account1.Id, null, null, 1000.00, 0.00, null, false);
        testInvoice.Payment_Days__c = null;
        testInvoice.Deposit_Invoice__c = depositInvoice.Id;
        insert testInvoice;
        Test.startTest();
        update testInvoice;
        Test.stopTest();
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
        for(Project__c projectRecord : [select Id, Name from Project__c]){
            if(projectRecord.Name == 'Test Project') project1 = projectRecord;
        }
    }
}