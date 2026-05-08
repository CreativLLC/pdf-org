/**
 * Created by charl on 2/20/2024.
 */

@IsTest
private class RateQuoteControllerTest {
    public static testmethod void testRateQuoteController()
    {
        //In this case, the Visualforce page named 'success' is the starting point of this test method.
        Test.setCurrentPage(Page.RateQuote);

        Account testAccount = new Account();
        testAccount.Name = 'test';
        testAccount.Phone = '111-222-3334';
        testAccount.Type = 'Standard Price Book';
        Database.insert(testAccount);

        Opportunity testopportunity = new Opportunity();
        testopportunity.AccountId = testAccount.Id;
        testopportunity.Amount = 100;
        testopportunity.Name = 'test';
        testopportunity.CloseDate = Date.valueOf('2011-12-12');
        testopportunity.StageName = 'Closed - Won';
        testopportunity.PriceBook2Id = '01s30000000K0jQAAS';
        Database.insert(testopportunity);

        RateQuoteController controller = new RateQuoteController(new ApexPages.Standardcontroller(testopportunity));
    }
}