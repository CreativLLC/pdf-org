/**
 * Created by charl on 3/21/2023.
 */

@IsTest
private class ContactRoleUtilsTest {

    public static Account account1;
    public static Contact baContact;
    public static Contact developerContact;
    public static Opportunity opportunity1;
    public static Project__c project1;

    static
    {
        account1 = AccountUtils.generateAccount('Account1', true);
        baContact = ContactUtils.generateContact('BA', 'Contact', account1.Id, true);
        developerContact = ContactUtils.generateContact('Developer', 'Contact', account1.Id, true);
        opportunity1 = OpportunityUtils.generateOpportunity('Opportunity1', account1.Id, true);
        project1 = ProjectUtils.generateProject('Project1', account1.Id, opportunity1.Id, true);
    }

    @IsTest
    static void testGenerateProjectAllocations() {
        Date startDate = Date.newInstance(2023, 3, 13);
        Date endDate = Date.newInstance(2023, 4, 9);
        Contact_Role__c baAssignment = ContactRoleUtils.generateAssignmentContactRole(baContact.Id,project1.Id,startDate,null,15,false);
        Contact_Role__c developerAssignment = ContactRoleUtils.generateAssignmentContactRole(developerContact.Id,project1.Id,startDate,endDate,20,false);

        Test.startTest();
        insert new List<Contact_Role__c>{baAssignment, developerAssignment};
        Test.stopTest();

        List<Project_Allocation__c> baAllocations = [select Id from Project_Allocation__c where Contact_Role__c = :baAssignment.Id];
        System.assertEquals(53, baAllocations.size(), 'Expect 53 allocations generated for BA Contact Role with no end date');

        List<Project_Allocation__c> developerAllocations = [select Id from Project_Allocation__c where Contact_Role__c = :developerAssignment.Id];
        System.assertEquals(4, developerAllocations.size(), 'Expect 4 allocations generated for Developer Contact Role with end date');
    }

    @IsTest
    static void testAdjustProjectAllocations_ShiftEarlier() {
        Date startDate = Date.newInstance(2023, 3, 13);
        Date endDate = Date.newInstance(2023, 4, 9);
        Contact_Role__c testAssignment = ContactRoleUtils.generateAssignmentContactRole(baContact.Id,project1.Id,startDate,endDate,20,true);

        Test.startTest();
        testAssignment.Start_Date__c = testAssignment.Start_Date__c.addDays(-28);
        testAssignment.End_Date__c = testAssignment.End_Date__c.addDays(-14);
        update testAssignment;
        Test.stopTest();

        List<Project_Allocation__c> projAllocations = [select Id from Project_Allocation__c where Contact_Role__c = :testAssignment.Id];
        System.assertEquals(6, projAllocations.size());
    }

    @IsTest
    static void testAdjustProjectAllocations_ShiftLater() {
        Date startDate = Date.newInstance(2023, 3, 13);
        Date endDate = Date.newInstance(2023, 4, 9);
        Contact_Role__c testAssignment = ContactRoleUtils.generateAssignmentContactRole(baContact.Id,project1.Id,startDate,endDate,20,true);

        Test.startTest();
        testAssignment.Start_Date__c = testAssignment.Start_Date__c.addDays(14);
        testAssignment.End_Date__c = testAssignment.End_Date__c.addDays(28);
        update testAssignment;
        Test.stopTest();

        List<Project_Allocation__c> projAllocations = [select Id from Project_Allocation__c where Contact_Role__c = :testAssignment.Id];
        System.assertEquals(6, projAllocations.size());
    }

    @IsTest
    static void testAdjustProjectAllocations_UpdateHours() {
        Date startDate = Date.newInstance(2023, 3, 13);
        Date endDate = Date.newInstance(2023, 4, 9);
        Contact_Role__c testAssignment = ContactRoleUtils.generateAssignmentContactRole(baContact.Id,project1.Id,startDate,null,20,true);
        List<Project_Allocation__c> projAllocations = [select Id from Project_Allocation__c where Contact_Role__c = :testAssignment.Id];
        projAllocations[0].Hours__c = 21;
        update projAllocations[0];

        Test.startTest();
        testAssignment.Hours_Per_Week__c = 27;
        update testAssignment;
        Test.stopTest();

        Integer numOfOverrides = 0;
        Integer numOfNonOverrides = 0;
        for(Project_Allocation__c projAllocation : [select Id, Hours__c, Overridden__c from Project_Allocation__c where Contact_Role__c = :testAssignment.Id]){
            if(projAllocation.Overridden__c){
                numOfOverrides = numOfOverrides + 1;
                System.assertEquals(21, projAllocation.Hours__c);
            }
            else{
                numOfNonOverrides = numOfNonOverrides + 1;
                System.assertEquals(27, projAllocation.Hours__c);
            }
        }
        System.assertEquals(1, numOfOverrides);
        System.assertEquals(52, numOfNonOverrides);
    }

    @IsTest
    static void testRemoveAllocations_CompleteContactRole() {
        Date startDate = Date.newInstance(2023, 3, 13);
        Date endDate = Date.newInstance(2023, 4, 9);
        Contact_Role__c testAssignment = ContactRoleUtils.generateAssignmentContactRole(baContact.Id,project1.Id,startDate,null,20,true);

        List<Project_Allocation__c> projAllocations = [select Id from Project_Allocation__c where Contact_Role__c = :testAssignment.Id];
        System.assertNotEquals(0,projAllocations.size(),'Expect project allocations to be generated');

        Test.startTest();
        testAssignment.Status__c = 'Completed';
        update testAssignment;
        Test.stopTest();

        projAllocations = [select Id from Project_Allocation__c where Contact_Role__c = :testAssignment.Id];
        System.assertEquals(0,projAllocations.size(),'Expect project allocations to be removed');
    }
}