/**
 * Created by charl on 3/24/2023.
 */

@IsTest
private class ResourcePlannerControllerTest {

    public static Account account1;
    public static Contact baContact;
    public static Contact developerContact;
    public static Opportunity opportunity1;
    public static Project__c project1;
    public static Contact_Role__c baAssignment;
    public static Contact_Role__c developerAssignment;

    static
    {
        account1 = AccountUtils.generateAccount('Account1', true);
        baContact = ContactUtils.generateContact('BA', 'Contact', account1.Id, true);
        developerContact = ContactUtils.generateContact('Developer', 'Contact', account1.Id, true);
        opportunity1 = OpportunityUtils.generateOpportunity('Opportunity1', account1.Id, true);
        project1 = ProjectUtils.generateProject('Project1', account1.Id, opportunity1.Id, true);

        Date startDate = Date.today();
        Date endDate = Date.today().addDays(14);
        baAssignment = ContactRoleUtils.generateAssignmentContactRole(baContact.Id,project1.Id,startDate,null,15,false);
        developerAssignment = ContactRoleUtils.generateAssignmentContactRole(developerContact.Id,project1.Id,startDate,endDate,20,false);
        Database.insert(new List<Contact_Role__c>{baAssignment,developerAssignment});
    }

    @IsTest
    static void testGetPageModel() {
        ResourcePlannerController.ResourcePlannerModel pageModel = ResourcePlannerController.getResourcePlannerModel(null, null);
        System.assert(pageModel.datesRow.displayCells.size() > 0, 'Expect dates row to have display cells');
        System.assertEquals(4, pageModel.resourceDataRows.size(), 'Expect four resource rows');
        System.assertEquals(3, pageModel.projectDataRows.size(), 'Expect three project rows');
    }
}