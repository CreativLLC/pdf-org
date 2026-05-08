public class AccountUtils {
    public static Integer uniqueNumber = 0;

    public static void handleBeforeInsert(){
        for(Account currentAccount : (List<Account>) Trigger.new)
        {
            currentAccount.ParentId = currentAccount.Parent_Account__c;
            currentAccount.Last_Updated__c = System.now();
            currentAccount.Lead__c = currentAccount.Lead_Id_Passable__c;
        }
    }
    public static void handleBeforeUpdate(){
       	for(Account currentAccount : (List<Account>) Trigger.new)
        {
            currentAccount.ParentId = currentAccount.Parent_Account__c;
            currentAccount.Last_Updated__c = System.now();
            currentAccount.Lead__c = currentAccount.Lead_Id_Passable__c;
        }
    }
    public static void handleBeforeDelete(){
        
    }
    public static void handleAfterInsert(){
        
    }
    public static void handleAfterUpdate(){
        
    }
    public static void handleAfterDelete(){
        
    }
    public static void handleAfterUndelete(){
        
    }
    public static Account generateAccount(Boolean createRecord){
        return generateAccount(null, null, null, null, null, null, createRecord);
    }
    public static Account generateAccount(String accountName, Boolean createRecord){
        return generateAccount(accountName, null, null, null, null, null, createRecord);
    }
    public static Account generateAccount(String accountName, String street, String city, String state, String postalCode, String country, Boolean createRecord){
        AccountUtils.uniqueNumber = AccountUtils.uniqueNumber + 1;
        String uniqueVal = String.valueOf(LeadUtils.uniqueNumber);
        Account newAccount = new Account();
        newAccount.Name = accountName != null ? accountName : 'TestAccountName' + uniqueVal;
        newAccount.BillingStreet = street != null ? street : 'TestStreet' + uniqueVal;
        newAccount.BillingCity = city != null ? city : 'Boulder';
        newAccount.BillingState = state != null ? state : 'Colorado';
        newAccount.BillingPostalCode = postalCode != null ? postalCode : '11235';
        newAccount.BillingCountry = country != null ? country : 'United States';

        if(createRecord) insert newAccount;
        return newAccount;
    }
}