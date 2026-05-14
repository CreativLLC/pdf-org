// =============================================================================
//  Reset the POC Test Form Template's published Definition JSON to a clean,
//  demo-friendly minimal layout. Use before showing the builder to a client so
//  the starting state is instantly recognizable.
//
//  Run via: sf apex run --file scripts/apex/reset-to-simple-template.apex
// =============================================================================

String simpleJson = '{'
    + '"page": {"size":"LETTER","orientation":"portrait","margins":"0.5in"},'
    + '"fontStack": "\'Helvetica Neue\', Helvetica, Arial, sans-serif",'
    + '"root": {"type":"row","children":[{"type":"col","props":{"width":"100%","padding":"0"},"children":['
    +   '{"type":"text","props":{"align":"center","fontSize":"22pt","marginBottom":"4px","spans":[{"text":"Patient Form","bold":true}]}},'
    +   '{"type":"rule"},'
    +   '{"type":"spacer","props":{"height":"12px"}},'
    +   '{"type":"text","props":{"align":"left","spans":[{"text":"Patient Name: ","bold":true},{"token":"Patient_Name__c"}]}},'
    +   '{"type":"text","props":{"align":"left","spans":[{"text":"Status: ","bold":true},{"token":"Status__c"}]}},'
    +   '{"type":"spacer","props":{"height":"24px"}},'
    +   '{"type":"text","props":{"align":"left","fontSize":"14pt","marginBottom":"6px","spans":[{"text":"Patient Signature","bold":true}]}},'
    +   '{"type":"image","props":{"source":"relatedFile","fromRelation":"Signatures__r","filterExpr":"Signature_Type__c == \'Patient\'","width":"220px","height":"60px"}}'
    + ']}]}'
    + '}';

List<Template_Version__c> versions = [
    SELECT Id, Name, Document_Template__c, Document_Template__r.Name, Definition_Json__c
    FROM Template_Version__c
    WHERE Document_Template__r.Name = 'POC Test Form Template'
    ORDER BY CreatedDate ASC
];

if (versions.isEmpty()) {
    System.debug('No template version found for "POC Test Form Template". Run scripts/apex/seed-test-data.apex first.');
    return;
}

Template_Version__c tv = versions[0];
tv.Definition_Json__c = simpleJson;
update tv;

System.debug('=================================================================');
System.debug('TEMPLATE RESET TO SIMPLE STARTING STATE');
System.debug('Document Template: ' + tv.Document_Template__r.Name);
System.debug('Template Version:  ' + tv.Name + ' (' + tv.Id + ')');
System.debug('-----------------------------------------------------------------');
System.debug('Layout:');
System.debug('  Heading:  "Patient Form"');
System.debug('  Rule');
System.debug('  Patient Name: {{Patient_Name__c}}');
System.debug('  Status: {{Status__c}}');
System.debug('  Heading:  "Patient Signature"');
System.debug('  Image:    Patient signature (related file)');
System.debug('=================================================================');
System.debug('Refresh the Template Builder page to see the new starting state.');
