public with sharing class SupportQuoteController 
{	
	private final Opportunity oppRecord;
	private Opportunity tempOppRecord;
	public List<PriceBookEntry> pbeList;
	public List<GenericTableRow> quoteLineItems {get; set;}
	public String validUntil {get; set;}
	public String accountName {get; set;}
	
	public SupportQuoteController(ApexPages.StandardController std)
	{
		// Get information about the related opportunity
		oppRecord = (Opportunity)std.getRecord();
		tempOppRecord = [select Id, PriceBook2Id, Account.Name 
							from Opportunity 
							where Id = :oppRecord.Id];
		
		accountName = tempOppRecord.Account.Name;
		validUntil = Date.today().addDays(30).format();
		
		// Initialize Lists and Maps
		pbeList = new List<PriceBookEntry> {}; 
		quoteLineItems = new List<GenericTableRow> {}; 
		
		// Get the standard price book entries for labor items the PriceBook related to the Opportunity
		pbeList = [select Id, UnitPrice, Product2.Units__c, Product2.Description, Product2.Name, Product2.ProductCode, 
					Product2.Family	
					from PriceBookEntry 
					where PriceBook2Id = :tempOppRecord.Pricebook2Id 
					and Product2.Product_Class__c = 'Contract'
					order by UnitPrice desc];
		
		// For each support option defined in the pricebook, list it in the table
		for(Integer i=0; i<pbeList.size(); i++)
		//for(PricebookEntry pbe : pbeList)
		{
			PricebookEntry pbe = pbeList[i];
			GenericTableRow lineItemRow = new GenericTableRow();
			lineItemRow.value0 = 'Option ' + (i+1) + ': ';
			lineItemRow.value1 = pbe.Product2.Name;
			if(pbe.Product2.Units__c != null && pbe.Product2.Units__c != '')
				lineItemRow.value2 = '/' + pbe.Product2.Units__c;
			else
				lineItemRow.value2 = ' each';
			lineItemRow.value10 = pbe.UnitPrice;
			quoteLineItems.add(lineItemRow);
		}
	}
}