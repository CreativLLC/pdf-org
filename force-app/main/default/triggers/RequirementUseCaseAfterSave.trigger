trigger RequirementUseCaseAfterSave on Requirement_Use_Case__c (after insert, after update) {

/*
	// Query the affected Requirement Use Case records and
	// Compile a unique list of Requirements referenced by
	// 	the Requirement Use Cases
	Set<Id> referencedRequirements = new Set<Id>{};
	for(Requirement_Use_Case__c ruc : [select Id, Requirement__c 
										from Requirement_Use_Case__c 
										where Id in :Trigger.newMap.keySet()])
	{
		referencedRequirements.add(ruc.Requirement__c);
	}
	
	// Query all Requirement Use Cases attached to the 
	//  referenced Requirements
	List<Requirement_Use_Case__c> allRequirementUseCases = 
		[select Id, Requirement__c, Estimated_Configuration_Time__c, 
			Estimated_Design_Time__c, Estimated_Development_Time__c,
			Estimated_Documentation_Time__c, Estimated_Project_Management_Time__c,
			Estimated_Reporting_Time__c, Estimated_Testing_Time__c,
			Estimated_Training_Time__c from Requirement_Use_Case__c 
			where Requirement__c in :referencedRequirements];
	
	
	// Sum up the estimate fields on all Requirement Use cases
	Map<Id, Requirement__c> requirementsToUpdate = new Map<Id, Requirement__c>{};
	for(Requirement_Use_Case__c ruc : allRequirementUseCases)
	{
		Requirement__c tempRequirement;
		if(!(requirementsToUpdate.get(ruc.Requirement__c) == null))
			tempRequirement = requirementsToUpdate.get(ruc.Requirement__c);
		else
		{
			tempRequirement = new Requirement__c(Id=ruc.Requirement__c);
			tempRequirement.Estimated_Configuration_Time__c = 0; 
			tempRequirement.Estimated_Design_Time__c = 0;
			tempRequirement.Estimated_Development_Time__c = 0;
			tempRequirement.Estimated_Documentation_Time__c = 0;
			tempRequirement.Estimated_Project_Management_Time__c = 0;  
			tempRequirement.Estimated_Reporting_Time__c = 0; 
			tempRequirement.Estimated_Testing_Time__c = 0; 
			tempRequirement.Estimated_Training_Time__c = 0;
		}
			
		tempRequirement.Estimated_Configuration_Time__c += UtilNinja.smartValue(ruc.Estimated_Configuration_Time__c); 
		tempRequirement.Estimated_Design_Time__c += UtilNinja.smartValue(ruc.Estimated_Design_Time__c);
		tempRequirement.Estimated_Development_Time__c += UtilNinja.smartValue(ruc.Estimated_Development_Time__c); 
		tempRequirement.Estimated_Documentation_Time__c += UtilNinja.smartValue(ruc.Estimated_Documentation_Time__c);  
		tempRequirement.Estimated_Project_Management_Time__c += UtilNinja.smartValue(ruc.Estimated_Project_Management_Time__c); 
		tempRequirement.Estimated_Reporting_Time__c += UtilNinja.smartValue(ruc.Estimated_Reporting_Time__c);
		tempRequirement.Estimated_Testing_Time__c += UtilNinja.smartValue(ruc.Estimated_Testing_Time__c);
		tempRequirement.Estimated_Training_Time__c += UtilNinja.smartValue(ruc.Estimated_Training_Time__c);
		
		requirementsToUpdate.put(tempRequirement.Id, tempRequirement); 
	}
	
	// Update the Requirement records with the updated sums  
	Database.update(requirementsToUpdate.values());
	*/
}