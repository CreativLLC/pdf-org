public with sharing class CertificateController {

	public Contract contract {get; set;}
	public String expiration {get; set;}
	public String currentDate {get; set;} 
	String contractId;

	public CertificateController()
	{
		contractId = ApexPages.currentPage().getParameters().get('id');
		contract = [select Id, ContractNumber, Account.Name, EndDate, Perpetual__c 
					from Contract 
					where Id = :contractId limit 1];
					
		currentDate = Date.today().format();
		
		if(contract.Perpetual__c)
			expiration = 'Never';
		else
			expiration = contract.EndDate.format();
	}
}