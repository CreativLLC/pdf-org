@IsTest
public with sharing class TestRequirementTriggers {

	public static testMethod void testRequirementUseCaseTriggers(){
		Account testAccount = new Account();
		testAccount.Name = 'test';
		insert testAccount;
		
		Project__c testProject = new Project__c();
		testProject.Account__c = testAccount.Id;
		insert testProject;
		
		Requirement__c testRequirement = new Requirement__c();
		testRequirement.Project__c = testProject.Id;
		testRequirement.Subject__c = 'test subject';
		insert testRequirement;
		
		Process__c testProcess = new Process__c();
		testProcess.Account__c = testAccount.Id;
		testProcess.Process_Description__c = 'Test Description';
		insert testProcess;
		
		Use_Case__c testUseCase = new Use_Case__c();
		testUseCase.Account__c = testAccount.Id;
		testUseCase.Actors__c = 'test actors';
		testUseCase.Use_Case_Name__c = 'test use case';
		testUseCase.Process__c = testProcess.Id;
		insert testUseCase;
		
		Requirement_Use_Case__c testRequirementUseCase = new Requirement_Use_Case__c();
		testRequirementUseCase.Requirement__c = testRequirement.Id;
		testRequirementUseCase.Use_Case__c = testUseCase.Id;
		//testRequirementUseCase.Estimated_Configuration_Time__c = 0; 
		//testRequirementUseCase.Estimated_Design_Time__c = 0;
		testRequirementUseCase.Estimated_Development_Time__c = 0;
		testRequirementUseCase.Estimated_Documentation_Time__c = 0;
		testRequirementUseCase.Estimated_Project_Management_Time__c = 0;  
		testRequirementUseCase.Estimated_Reporting_Time__c = 0; 
		testRequirementUseCase.Estimated_Testing_Time__c = 0; 
		testRequirementUseCase.Estimated_Training_Time__c = 0;
		insert testRequirementUseCase;
	}
}