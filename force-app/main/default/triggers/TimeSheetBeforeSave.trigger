trigger TimeSheetBeforeSave on Time_Sheet__c (before insert, before update) {
	for(Time_Sheet__c TS:Trigger.new)
	{
		TS.Total_Hours__c = 0;	
		TS.Total_Hours__c += TS.Configuration_Time__c;
		TS.Total_Hours__c += TS.Design_Time__c;
		TS.Total_Hours__c += TS.Development_Time__c;
		TS.Total_Hours__c += TS.Documentation_Time__c;
		TS.Total_Hours__c += TS.Project_Management__c;
		TS.Total_Hours__c += TS.Reporting_Time__c;
		TS.Total_Hours__c += TS.Testing_Time__c;
		TS.Total_Hours__c += TS.Training_Time__c;
	}
}