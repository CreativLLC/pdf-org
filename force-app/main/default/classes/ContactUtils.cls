public class ContactUtils {
    public static Integer uniqueNumber = 0;
    public static void handleBeforeInsert(){
        for(Contact currentContact : (List<Contact>) Trigger.new)
        {
            currentContact.Lead__c = currentContact.Lead_Id_Passable__c;
        }
    }
    public static void handleBeforeUpdate(){
       	for(Contact currentContact : (List<Contact>) Trigger.new)
        {
            currentContact.Lead__c = currentContact.Lead_Id_Passable__c;
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
    public static Contact generateContact(Id accountId, Boolean createRecord){
        return generateContact(null, null, accountId, createRecord);
    }
    public static Contact generateContact(String firstName, String lastName, Id accountId, Boolean createRecord){
        ContactUtils.uniqueNumber = ContactUtils.uniqueNumber + 1;
        String uniqueVal = String.valueOf(ContactUtils.uniqueNumber);
        Contact newContact = new Contact();
        newContact.FirstName = firstName != null ? firstName : 'TestFirstName' + uniqueVal;
        newContact.LastName = lastName != null ? lastName : 'TestLastName' + uniqueVal;
        newContact.AccountId = accountId;

        if(createRecord) insert newContact;
        return newContact;
    }
}