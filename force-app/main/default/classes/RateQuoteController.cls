public with sharing class RateQuoteController 
{	
	private final Opportunity oppRecord;
	private Opportunity tempOppRecord;
	public List<PriceBookEntry> pbeList;
	private Map<String, String> pbeDescriptions;
	private Map<String, Decimal> pbeAverages;
	private Map<String, Integer> pbeCounts;
	public List<GenericTableRow> quoteLineItems {get; set;}
	public String validUntil {get; set;}
	public Boolean showSupport {get; set;}
	private Decimal averagePrice = 0;
	public Decimal tier1Price {get; set;}
	public Decimal tier2Price {get; set;}
	public Decimal tier3Price {get; set;}
	
	public RateQuoteController(ApexPages.StandardController std)
	{
		// Get information about the related opportunity
		oppRecord = (Opportunity)std.getRecord();
		tempOppRecord = [select Id, PriceBook2Id, Quote_Valid_Until__c, Include_Support_Packages__c from Opportunity where Id = :oppRecord.Id];
		
		validUntil = tempOppRecord.Quote_Valid_Until__c.format();
		showSupport = tempOppRecord.Include_Support_Packages__c == 'Yes' ? true : false;  
		
		// Initialize Lists and Maps
		pbeList = new List<PriceBookEntry> {}; 
		pbeDescriptions = new Map<String, String> {};
		pbeAverages = new Map<String, Decimal> {}; 
		pbeCounts = new Map<String, Integer> {}; 
		quoteLineItems = new List<GenericTableRow> {}; 
		
		// Get the standard price book entries for the PriceBook related to the Opportunity
		pbeList = [select Id, UnitPrice, Product2.Description, Product2.Name, Product2.ProductCode, 
					Product2.Family	
					from PriceBookEntry 
					where PriceBook2Id = :tempOppRecord.Pricebook2Id and Product2.Product_Class__c = 'Labor'
					order by Product2.Name desc];
					
		// Average the prices for products by category
		for(PricebookEntry pbe : pbeList)
		{
			Integer currentCount = pbeCounts.get(pbe.Product2.Family);
			Decimal currentAverage = pbeAverages.get(pbe.Product2.Family);
			String currentDescription = pbeDescriptions.get(pbe.Product2.Family);
			
			// Construct the descrption for this product family
			if(currentCount == null || currentCount == 0)
				pbeDescriptions.put(pbe.Product2.Family, pbe.Product2.Name);
			else
				pbeDescriptions.put(pbe.Product2.Family, currentDescription + ', ' +pbe.Product2.Name);
				
			// Recalculate the average for this product family
			if(currentCount == null || currentCount == 0)
				pbeAverages.put(pbe.Product2.Family, pbe.UnitPrice);
			else
				pbeAverages.put(pbe.Product2.Family, (((currentAverage*currentCount)+pbe.UnitPrice)/(currentCount+1)));
			
			// Add one to the current count
			if(currentCount == null || currentCount == 0)
				pbeCounts.put(pbe.Product2.Family, 1);
			else
				pbeCounts.put(pbe.Product2.Family, currentCount + 1);
		}
		
		Map<Decimal, String> invertedMap = new Map<Decimal, String>{};
		List<Decimal> sortedPrices = new List<Decimal>{};
		List<String> sortedFamilies = new List<String>{};
		
		// Construct an inverted Map and a list for sorting
		for(String family : pbeAverages.keySet())
		{
			Decimal price = pbeAverages.get(family);
			sortedPrices.add(price);
			invertedMap.put(price, family);
		}
		
		// Sort the price list
		sortedPrices.sort();
		
		// Iterate through the sorted price list and construct a sorted Family list
		for(Decimal price : sortedPrices)
		{
			sortedFamilies.add(invertedMap.get(price));
		}
		
		Decimal sortedFamiliesTotal = 0;
		
		// For each family of products, list out the rates
		//for(String family : pbeDescriptions.keySet())
		for(String family : sortedFamilies)
		{
			Decimal familyValue = pbeAverages.get(family);
			
			if(familyValue != null)
			{
				GenericTableRow lineItemRow = new GenericTableRow();
				lineItemRow.value0 = family;
				lineItemRow.value1 = pbeDescriptions.get(family);
				lineItemRow.value2 = '$' + String.valueOf(familyValue) + '/hr';
				quoteLineItems.add(lineItemRow);
				
				sortedFamiliesTotal += familyValue;
			}
		}
		if(sortedFamilies.size() > 0){
			averagePrice = sortedFamiliesTotal/sortedFamilies.size();

			tier1Price = averagePrice*0.85;
			tier2Price = averagePrice*0.80;
			tier3Price = averagePrice*0.75;
		}
	}
}