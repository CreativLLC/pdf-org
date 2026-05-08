trigger AccountBeforeChange on Account (before insert, before update) {

	for(Account currentAccount : Trigger.new)
	{
		//currentAccount.Name = currentAccount.Industry + ' - ' + currentAccount.BillingState + ' - ' + currentAccount.AccountNumber;
		currentAccount.Last_Updated__c = System.now();	
	}
}