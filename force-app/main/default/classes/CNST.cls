public with sharing class CNST {
	public static Id rType_Paycheck_Commission = '01230000001JFGS';
	public static Id Standard_Pricebook_Id = '01s30000000K0jQAAS';
	
	static testMethod void testCNST() 
	{
		String testString = CNST.rType_Paycheck_Commission;
		testString = CNST.Standard_Pricebook_Id;
	}
}