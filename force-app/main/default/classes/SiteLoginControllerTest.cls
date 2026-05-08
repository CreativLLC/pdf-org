/**
 * Created by charl on 2/20/2024.
 */

@IsTest
private class SiteLoginControllerTest {
    @IsTest(SeeAllData=true) static void testSiteLoginController () {
        // Instantiate a new controller with all parameters in the page
        SiteLoginController controller = new SiteLoginController ();
        controller.username = 'test@salesforce.com';
        controller.password = '123456';

        System.assertEquals(controller.login(),null);
    }
}