public with sharing class TemplateVersionApprovalHandler {

    public class Input {
        @InvocableVariable(required=true label='Template Version Id')
        public Id templateVersionId;
    }

    @InvocableMethod(
        label='Stamp Approval On Related Mappings'
        description='For each Template_Version__c provided, stamp Approved_At__c=System.now() on every related Template_Mapping__c that does not already carry a stamp. Idempotent.'
        category='PDF Generator'
    )
    public static void stampApproval(List<Input> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            return;
        }
        Set<Id> versionIds = new Set<Id>();
        for (Input req : inputs) {
            if (req != null && req.templateVersionId != null) {
                versionIds.add(req.templateVersionId);
            }
        }
        if (versionIds.isEmpty()) {
            return;
        }

        List<Template_Mapping__c> unstamped = [
            SELECT Id, Approved_At__c
            FROM Template_Mapping__c
            WHERE Template_Version__c IN :versionIds
              AND Approved_At__c = NULL
        ];

        if (unstamped.isEmpty()) {
            return;
        }

        Datetime now = Datetime.now();
        for (Template_Mapping__c m : unstamped) {
            m.Approved_At__c = now;
        }
        update unstamped;
    }
}
