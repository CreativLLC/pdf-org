trigger ProductAfterSave on Product2 (after insert, after update) 
{
	public List<PriceBookEntry> priceBookList = new List<PriceBookEntry>();
	public Map<Id, PriceBookEntry> productMap = new Map<Id, PriceBookEntry>();
	
	for(PriceBookEntry priceBook: [select Id, Product2.Id, Product2.Base_Price__c from PricebookEntry where PriceBook2.Name = 'Standard Price Book'])
	{
		productMap.put(priceBook.Product2.Id, priceBook);
	
	}
	for(Product2 product:trigger.new)
	{
		if(productMap.get(product.Id)== NULL)
		{
			PriceBookEntry newPriceBook = new PriceBookEntry();
			newPriceBook.Product2Id = product.ID;
			newPriceBook.UnitPrice = product.Base_Price__c;
			newPriceBook.PriceBook2Id = CNST.Standard_Pricebook_Id;
			newPriceBook.IsActive = True;
			priceBookList.add(newPriceBook);
		}
		else
		{
			PriceBookEntry updatePriceBook = productMap.get(product.ID);
			updatePriceBook.UnitPrice = product.Base_Price__c;
			priceBookList.add(updatePriceBook);
		}
	}
	database.upsert(priceBookList);				

}