/**
 * Created by charl on 2/19/2024.
 */

@IsTest
private class ForgotPasswordControllerTest {
    @IsTest(SeeAllData=true) public static void testForgotPasswordController() {
        // Instantiate a new controller with all parameters in the page
        ForgotPasswordController controller = new ForgotPasswordController();
        controller.username = 'test@salesforce.com';

        System.assertEquals(controller.forgotPassword(),null);
    }
}