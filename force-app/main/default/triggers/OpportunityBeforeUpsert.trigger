/*
Trigger for making pre-save Opportunity record updates
    - Test Classes: RateQuoteController, SupportQuoteController, InvoiceCreationController
    - 1/6/2013 - Initial  Version - Charles Howard
*/

trigger OpportunityBeforeUpsert on Opportunity (before insert, before update) 
{
    for(Opportunity record : Trigger.new)
    {
        if(record.Quote_Valid_For__c == '30 Days')
        {
            record.Quote_Valid_Until__c = Date.today().addDays(30);
        }
        else if(record.Quote_Valid_For__c == '60 Days')
        {
            record.Quote_Valid_Until__c = Date.today().addDays(60);
        }
        else if(record.Quote_Valid_For__c == '90 Days')
        {
            record.Quote_Valid_Until__c = Date.today().addDays(90);
        }
        else if(record.Quote_Valid_For__c == '6 Months')
        {
            record.Quote_Valid_Until__c = Date.today().addMonths(6);
        }
        else if(record.Quote_Valid_For__c == '1 Year')
        {
            record.Quote_Valid_Until__c = Date.today().addYears(1);
        }
        else
        {
            record.Quote_Valid_Until__c = Date.today().addDays(30);
        }
        
    }
}