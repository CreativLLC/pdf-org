public with sharing class RollupTransaction {
	
	public Transaction__c trans {get; set;}
    public String rowLabel {get; set;}
    public String rowId {get; set;}
	public Decimal rollupValue {get; set;}
	/*
	public RollupTransaction (Transaction__c transValue)
	{
		trans = transValue;
		rollupValue = 0;
	}
	*/
	public RollupTransaction (Transaction__c transValue, String rowLabel, String rowId, Decimal rollupAmount)
	{
		this.trans = transValue;
        this.rowLabel = rowLabel;
        this.rowId = rowId;
		this.rollupValue = rollupAmount;	
	}
}