@isTest
public class TimeSheetUtilsTest {
    public static Account account1;
    public static Contact developerContact;
    public static Contact baContact;
    public static Contact_Role__c developerProject1;
    public static Contact_Role__c developerProject2;
    public static Contact_Role__c baProject1;
    public static Contact_Role__c baProject2;
    public static Opportunity opportunity1;
    public static Project__c project1;
    public static Project__c project2;

    @testSetup
    static void generateData()
    {
        account1 = AccountUtils.generateAccount('Account1', true);
        
        developerContact = ContactUtils.generateContact('Developer', 'Contact', account1.Id, false);
        developerContact.Jira_Name__c = 'Jira Developer Name';
        baContact = ContactUtils.generateContact('BA', 'Contact', account1.Id, false);
        baContact.Jira_Name__c = 'Jira BA Name';
        Database.insert(new List<Contact>{developerContact,baContact});
        
        opportunity1 = OpportunityUtils.generateOpportunity('Opportunity1', account1.Id, true);
        
        project1 = ProjectUtils.generateProject('Test Project', account1.Id, ProjectUtils.getRecordTypeId('Active'), opportunity1.Id, 'New', false);
        project1.Jira_Project_Name__c = 'Test Jira Project Name';
        project2 = ProjectUtils.generateProject('Test Project 2', account1.Id, ProjectUtils.getRecordTypeId('Active'), opportunity1.Id, 'New', false);
        project2.Jira_Project_Name__c = 'Test Jira Project Name 2';
        Database.insert(new List<Project__c>{project1, project2});
        
        developerProject1 = ContactRoleUtils.generateAssignmentContactRole(developerContact.Id, project1.Id, Date.today(), null, 1, false);
        developerProject2 = ContactRoleUtils.generateAssignmentContactRole(developerContact.Id, project2.Id, Date.today(), null, 1, false);
        baProject1 = ContactRoleUtils.generateAssignmentContactRole(baContact.Id, project1.Id, Date.today(), null, 1, false);
        baProject2 = ContactRoleUtils.generateAssignmentContactRole(baContact.Id, project2.Id, Date.today(), null, 1, false);
        Database.insert(new List<Contact_Role__c>{developerProject1,developerProject2,baProject1,baProject2});
    }

    private static testMethod void testNewTimeSheetInsertion(){
        queryTestData();
        Test.startTest();
        Time_Sheet__c timeSheet1 = TimeSheetUtils.createRecord(developerContact.Jira_Name__c, project1.Jira_Project_Name__c, Date.today(), false);
        Time_Sheet__c timeSheet2 = TimeSheetUtils.createRecord(developerContact.Jira_Name__c, project2.Jira_Project_Name__c, Date.today(), false);
        Time_Sheet__c timeSheet3 = TimeSheetUtils.createRecord(baContact.Jira_Name__c, project1.Jira_Project_Name__c, Date.today(), false);
        Time_Sheet__c timeSheet4 = TimeSheetUtils.createRecord(baContact.Jira_Name__c, project2.Jira_Project_Name__c, Date.today(), false);
        Database.insert(new List<Time_Sheet__c>{timeSheet1,timeSheet2,timeSheet3,timeSheet4});
        Test.stopTest();

        // Verify that each time sheet was connected to the right person and project
        Boolean timeSheet1Checked = false;
        Boolean timeSheet2Checked = false;
        Boolean timeSheet3Checked = false;
        Boolean timeSheet4Checked = false;
        for(Time_Sheet__c ts : [select Id, Done_By__c, Project__c from Time_Sheet__c]){
            if(ts.Id == timeSheet1.Id){
				System.assertEquals(ts.Done_By__c, developerContact.Id, 'Expect first time sheet connected to Developer');
                System.assertEquals(ts.Project__c, project1.Id, 'Expect first time sheet connected to Project1');
                timeSheet1Checked = true;
            }
            else if(ts.Id == timeSheet2.Id){
                System.assertEquals(ts.Done_By__c, developerContact.Id, 'Expect second time sheet connected to Developer');
                System.assertEquals(ts.Project__c, project2.Id, 'Expect second time sheet connected to Project2');
                timeSheet2Checked = true;
            }
            else if(ts.Id == timeSheet3.Id){
                System.assertEquals(ts.Done_By__c, baContact.Id, 'Expect third time sheet connected to BA');
                System.assertEquals(ts.Project__c, project1.Id, 'Expect third time sheet connected to Project1');
                timeSheet3Checked = true;
            }
            else if(ts.Id == timeSheet4.Id){
                System.assertEquals(ts.Done_By__c, baContact.Id, 'Expect fourth time sheet connected to BA');
                System.assertEquals(ts.Project__c, project2.Id, 'Expect fourth time sheet connected to Project2');
                timeSheet4Checked = true;
            }
        }
        System.assert(timeSheet1Checked, 'Expect that we checked timeSheet1');
        System.assert(timeSheet2Checked, 'Expect that we checked timeSheet2');
        System.assert(timeSheet3Checked, 'Expect that we checked timeSheet3');
        System.assert(timeSheet4Checked, 'Expect that we checked timeSheet4');

    }
    
    private static testMethod void testNewTimeSheetUpdate(){
        queryTestData();
        
        Time_Sheet__c timeSheet1 = TimeSheetUtils.createRecord(developerContact.Jira_Name__c+'Test', project1.Jira_Project_Name__c, Date.today(), false);
        Time_Sheet__c timeSheet2 = TimeSheetUtils.createRecord(developerContact.Jira_Name__c, project2.Jira_Project_Name__c+'Test', Date.today(), false);
        Time_Sheet__c timeSheet3 = TimeSheetUtils.createRecord(baContact.Jira_Name__c, project1.Jira_Project_Name__c+'Test', Date.today(), false);
        Time_Sheet__c timeSheet4 = TimeSheetUtils.createRecord(baContact.Jira_Name__c+'Test', project2.Jira_Project_Name__c, Date.today(), false);
        Database.insert(new List<Time_Sheet__c>{timeSheet1,timeSheet2,timeSheet3,timeSheet4});
        
        Test.startTest();
        timeSheet1.Done_By_Name__c = developerContact.Jira_Name__c;
        timeSheet2.Project_Name__c = project2.Jira_Project_Name__c;
        timeSheet3.Project_Name__c = project1.Jira_Project_Name__c;
        timeSheet4.Done_By_Name__c = baContact.Jira_Name__c;
        Database.update(new List<Time_Sheet__c>{timeSheet1,timeSheet2,timeSheet3,timeSheet4});
        Test.stopTest();

        // Verify that each time sheet was connected to the right person and project
        Boolean timeSheet1Checked = false;
        Boolean timeSheet2Checked = false;
        Boolean timeSheet3Checked = false;
        Boolean timeSheet4Checked = false;
        for(Time_Sheet__c ts : [select Id, Done_By__c, Project__c from Time_Sheet__c]){
            if(ts.Id == timeSheet1.Id){
				System.assertEquals(ts.Done_By__c, developerContact.Id, 'Expect first time sheet connected to Developer');
                System.assertEquals(ts.Project__c, project1.Id, 'Expect first time sheet connected to Project1');
                timeSheet1Checked = true;
            }
            else if(ts.Id == timeSheet2.Id){
                System.assertEquals(ts.Done_By__c, developerContact.Id, 'Expect second time sheet connected to Developer');
                System.assertEquals(ts.Project__c, project2.Id, 'Expect second time sheet connected to Project2');
                timeSheet2Checked = true;
            }
            else if(ts.Id == timeSheet3.Id){
                System.assertEquals(ts.Done_By__c, baContact.Id, 'Expect third time sheet connected to BA');
                System.assertEquals(ts.Project__c, project1.Id, 'Expect third time sheet connected to Project1');
                timeSheet3Checked = true;
            }
            else if(ts.Id == timeSheet4.Id){
                System.assertEquals(ts.Done_By__c, baContact.Id, 'Expect fourth time sheet connected to BA');
                System.assertEquals(ts.Project__c, project2.Id, 'Expect fourth time sheet connected to Project2');
                timeSheet4Checked = true;
            }
        }
        System.assert(timeSheet1Checked, 'Expect that we checked timeSheet1');
        System.assert(timeSheet2Checked, 'Expect that we checked timeSheet2');
        System.assert(timeSheet3Checked, 'Expect that we checked timeSheet3');
        System.assert(timeSheet4Checked, 'Expect that we checked timeSheet4');

    }

    private static void queryTestData(){
        for(Account accountRecord : [select Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry from Account]){
            if(accountRecord.Name == 'Account1') account1 = accountRecord;
        }
        for(Contact contactRecord : [select Id, Name, Jira_Name__c from Contact]){
            if(contactRecord.Name == 'Developer Contact') developerContact = contactRecord;
            else if(contactRecord.Name == 'BA Contact') baContact = contactRecord;
        }
        for(Opportunity opportunityRecord : [select Id, Name from Opportunity]){
            if(opportunityRecord.Name == 'Opportunity1') opportunity1 = opportunityRecord;
        }
        for(Project__c projectRecord : [select Id, Name, Jira_Project_Name__c from Project__c]){
            if(projectRecord.Name == 'Test Project') project1 = projectRecord;
            if(projectRecord.Name == 'Test Project 2') project2 = projectRecord;
        }        
    }
}