public with sharing class selectableTimeSheet {

	public Boolean selected {get; set;}
	public Time_Sheet__c timeSheet {get; set;}

	public selectableTimeSheet(Time_Sheet__c timeSheet)
	{
		selected = false;
		this.timeSheet = timeSheet; 
	}
	
	static testMethod void testSelectableTimeSheet()
	{
		Time_Sheet__c ts = new Time_Sheet__c();
		selectableTimeSheet testSTS = new selectableTimeSheet(ts);
	}
}