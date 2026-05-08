public with sharing class PaycheckWorksheet {
	
	private final Paycheck__c paycheck; 
	public Paycheck__c tempPaycheck {get; set;}
	
	public List<Time_Sheet__c> tsQuery {get; set;}
	public List<selectableTimeSheet> timeSheets;
	
	public Decimal configTotal {get; set;}
	public Decimal designTotal {get; set;} 
	public Decimal documentationTotal {get; set;} 
	public Decimal trainingTotal {get; set;} 
	public Decimal testingTotal {get; set;} 
	public Decimal reportingTotal {get; set;} 
	public Decimal developmentTotal {get; set;}
	public Decimal PMtotal {get; set;}
	public Decimal invoiceTotal {get; set;}
	
	public Boolean editable {get; set;}
	
	private Boolean isCommission;
	private String queryString;
	
	public PaycheckWorksheet(ApexPages.StandardController stdCont)
	{
		String pchId = ((Paycheck__c)stdCont.getRecord()).Id;
		
		// If this is a new record
		if(pchId == null)
			paycheck = (Paycheck__c)stdCont.getRecord();
		else
			paycheck = [select Id, RecordTypeId, Status__c, Name, Issued_To__c from Paycheck__c where Id = :pchId];
			
		editable = true;
		isCommission = false;
		if(paycheck.RecordTypeId == CNST.rType_Paycheck_Commission)
			isCommission = true;
			
		// Assign the final paycheck to one that will interface with the page
		// ?? Change to a Controller instead of an Extension ??
		tempPaycheck = paycheck;
	}
	
	public List<selectableTimeSheet> getTimeSheets()
	{
		queryString =  'select Id, Requirement__r.Project__c, Requirement__r.Id, Design_Time__c, '; 
		queryString += 'Documentation_Time__c, Training_Time__c,Testing_Time__c, Reporting_Time__c, '; 
		queryString += 'Development_Time__c, Project_Management__c, Configuration_Time__c, Paycheck__c, ';
		queryString += 'Commission_Check__c, Total_Hours__c, Done_By__r.Name, Date__c from Time_Sheet__c ';
		
		List<Time_Sheet__c> timeSheetsQuery;
		
		String paycheckId, paycheckIssuedTo;
		
		if(paycheck.Id != null) paycheckId = paycheck.Id;
		else paycheckId = '';
			
		if(paycheck.Issued_To__c != null) paycheckIssuedTo = paycheck.Issued_To__c;
		else paycheckIssuedTo = '';
		
		// If this is a Commission Paycheck 
		if(isCommission)
		{
			// Adjust query criteria to select time sheets where the commission 
			//  has not been paid, or that are attached to the current Paycheck record
			queryString += 'where (Commission_Check__c = \'\' or Commission_Check__c = \'' + paycheckId + '\')';
			
			// If the Issued To has been defined
			if(paycheckIssuedTo != '')
				queryString += 'and Requirement__r.Project__r.Pay_Commission_To__c = \'' + paycheckIssuedTo + '\'';
		}
		else // Otherwise, this must be a regular paycheck
		{
			// Adjust query criteria to select Time Sheets that don't have a paycheck 
			//  and belong to the person the paycheck is issued to, or that are attached
			//  to the current paycheck record
			queryString += 'where (Paycheck__c = \'\' or Paycheck__c = \'' + paycheckId + '\')';
			
			// If the Issued To has been defined
			if(paycheckIssuedTo != '')
				queryString += 'and Done_By__c = \'' + paycheckIssuedTo + '\'';
		}
		
		// Query for Time sheet records
		timeSheetsQuery = Database.query(queryString);
		
		// Add Time Sheets to a selectable Time Sheet list
		List<selectableTimeSheet> timeSheetList = new List<selectableTimeSheet>{};
		for(Time_Sheet__c ts : timeSheetsQuery)
		{	
			selectableTimeSheet sts = new selectableTimeSheet(ts);
			if(isCommission && paycheck.Id != null && ts.Commission_Check__c == paycheck.Id)
				sts.selected = true;
			else if(paycheck.Id != null && ts.Paycheck__c == paycheck.Id)
				sts.selected = true;
			timeSheetList.add(sts);
		}
			
		// Return the list of selectableTimeSheets
		return timeSheetList;
	}
}