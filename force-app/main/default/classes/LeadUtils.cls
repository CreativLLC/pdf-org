public class LeadUtils {
    public static Integer uniqueNumber = 0;
    public static Lead generateLead(Boolean createRecord){
    	return generateLead(null, null, null, null, null, null, null, null, createRecord);
    }
    public static Lead generateLead(String firstName, String lastName, String company, Boolean createRecord){
    	return generateLead(firstName, lastName, company, null, null, null, null, null, createRecord);
    }
    public static Lead generateLead(String firstName, String lastName, String company, String street, String city, String state, String postalCode, String country, Boolean createRecord){
		LeadUtils.uniqueNumber = LeadUtils.uniqueNumber + 1;
        String uniqueVal = String.valueOf(LeadUtils.uniqueNumber);
        Lead newLead = new Lead();
        newLead.FirstName = firstName != null ? firstName : 'TestFirstName' + uniqueVal;
        newLead.LastName = lastName != null ? lastName : 'TestLastName' + uniqueVal;
        newLead.Company = company != null ? company : 'TestCompany' + uniqueVal;
        newLead.Street = street != null ? street : 'TestStreet' + uniqueVal;
        newLead.City = city != null ? city : 'Boulder';
        newLead.State = state != null ? state : 'Colorado';
        newLead.PostalCode = postalCode != null ? postalCode : '11235';
        newLead.Country = country != null ? country : 'United States';
        
        if(createRecord) insert newLead;
        return newLead;
    }
}