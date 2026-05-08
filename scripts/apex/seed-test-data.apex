// =============================================================================
//  Seed test data for the Meditrina PDF generator POC.
//  Run via: sf apex run --file scripts/apex/seed-test-data.apex
//  Or paste into Dev Console > Execute Anonymous.
//  Output (System.debug) includes the test URL to hit.
// =============================================================================

// --- 1. Clean previously-seeded data so this script is rerunnable ---
delete [SELECT Id FROM Form__c WHERE Name LIKE 'POC Test%'];
delete [SELECT Id FROM Document_Template__c WHERE Name = 'POC Test Form Template'];

// --- 2. Create a Form__c with two Signature__c children ---
Form__c form = new Form__c(
    Name = 'POC Test Form 001',
    Patient_Name__c = 'Jane Doe',
    Procedure_Date__c = Date.today().addDays(-3),
    Status__c = 'Complete',
    Comments__c = 'Procedure completed without complications. Patient stable, vitals normal. Follow-up scheduled in two weeks.',
    Revision_Number__c = 1
);
insert form;

Signature__c sigPatient = new Signature__c(
    Form__c = form.Id,
    Signature_Type__c = 'Patient',
    Signed_By__c = 'Jane Doe',
    Signed_At__c = Datetime.now().addHours(-4)
);
Signature__c sigPhys = new Signature__c(
    Form__c = form.Id,
    Signature_Type__c = 'Physician',
    Signed_By__c = 'Dr. Robert Smith, MD',
    Signed_At__c = Datetime.now().addHours(-3)
);
Signature__c sigWit = new Signature__c(
    Form__c = form.Id,
    Signature_Type__c = 'Witness',
    Signed_By__c = 'Nurse Allen',
    Signed_At__c = Datetime.now().addHours(-3)
);
insert new List<Signature__c>{ sigPatient, sigPhys, sigWit };

// --- 3. Attach a placeholder PNG to each signature record ---
//      (5x5 red dot, just so the renderer has something to embed)
String redDotB64 = 'iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAYAAACNbyblAAAAHElEQVQI12P4//8/w38GIAXDIBKE0DHxgljNBAAO9TXL0Y4OHwAAAABJRU5ErkJggg==';
List<ContentVersion> cvs = new List<ContentVersion>();
for (Signature__c s : new List<Signature__c>{ sigPatient, sigPhys, sigWit }) {
    cvs.add(new ContentVersion(
        Title = 'sig-' + s.Signature_Type__c.toLowerCase(),
        PathOnClient = 'sig-' + s.Signature_Type__c.toLowerCase() + '.png',
        VersionData = EncodingUtil.base64Decode(redDotB64)
    ));
}
insert cvs;
Map<Id, Id> cvIdToDocId = new Map<Id, Id>();
for (ContentVersion cv : [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :cvs]) {
    cvIdToDocId.put(cv.Id, cv.ContentDocumentId);
}
List<ContentDocumentLink> links = new List<ContentDocumentLink>();
List<Signature__c> sigList = new List<Signature__c>{ sigPatient, sigPhys, sigWit };
for (Integer i = 0; i < sigList.size(); i++) {
    links.add(new ContentDocumentLink(
        ContentDocumentId = cvIdToDocId.get(cvs[i].Id),
        LinkedEntityId = sigList[i].Id,
        ShareType = 'V'
    ));
}
insert links;

// --- 4. Create the Document_Template__c + Template_Version__c with a sample JSON ---
Document_Template__c dt = new Document_Template__c(
    Name = 'POC Test Form Template',
    Target_SObject__c = 'Form__c',
    Description__c = 'Smoke-test template covering: tokens, conditional visibility, related-list table, signature image embedding.',
    Active__c = true,
    Overwrite_Existing_File__c = true
);
insert dt;

String templateJson =
    '{' +
    '  "page": {"size":"LETTER","orientation":"portrait","margins":"0.5in"},' +
    '  "fontStack": "Helvetica, Arial, sans-serif",' +
    '  "root": {"type":"row","children":[' +
    '    {"type":"col","props":{"width":"100%"},"children":[' +
    '      {"type":"text","props":{"align":"center","fontSize":"22pt","marginBottom":"4px","spans":[{"text":"Pre-Op Surgical Form","bold":true}]}},' +
    '      {"type":"text","props":{"align":"center","fontSize":"10pt","marginBottom":"16px","spans":[{"text":"Form #: "},{"token":"Name"},{"text":"  ·  Revision "},{"token":"Revision_Number__c"}]}},' +
    '      {"type":"rule"},' +
    '      {"type":"row","children":[' +
    '        {"type":"col","props":{"width":"50%"},"children":[' +
    '          {"type":"text","props":{"spans":[{"text":"Patient: ","bold":true},{"token":"Patient_Name__c"}]}},' +
    '          {"type":"text","props":{"spans":[{"text":"Procedure Date: ","bold":true},{"token":"Procedure_Date__c"}]}}' +
    '        ]},' +
    '        {"type":"col","props":{"width":"50%"},"children":[' +
    '          {"type":"text","props":{"align":"right","spans":[{"text":"Status: ","bold":true},{"token":"Status__c"}]}}' +
    '        ]}' +
    '      ]},' +
    '      {"type":"spacer","props":{"height":"12px"}},' +
    '      {"type":"text","visibleIf":"Status__c == \'Complete\'","props":{"spans":[{"text":"✓ FORM COMPLETE","bold":true,"color":"#0a7c0a"}]}},' +
    '      {"type":"text","visibleIf":"Status__c != \'Complete\'","props":{"spans":[{"text":"DRAFT — NOT FOR DISTRIBUTION","bold":true,"color":"#aa0000"}]}},' +
    '      {"type":"spacer","props":{"height":"8px"}},' +
    '      {"type":"text","props":{"spans":[{"text":"Comments","bold":true,"fontSize":"13pt"}]}},' +
    '      {"type":"text","props":{"spans":[{"token":"Comments__c"}]}}' +
    '    ]}' +
    '  ]},' +
    '  "tables": [' +
    '    {"type":"table","props":{"fromRelation":"Signatures__r","headerBackground":"#EAEAEA","columns":[' +
    '      {"header":"Type","width":"20%","spans":[{"token":"row.Signature_Type__c"}]},' +
    '      {"header":"Signed By","width":"40%","spans":[{"token":"row.Signed_By__c"}]},' +
    '      {"header":"Signed At","width":"25%","spans":[{"token":"row.Signed_At__c"}]},' +
    '      {"header":"Patient","width":"5%","cellExpr":"row.Signature_Type__c == \'Patient\' ? \'X\' : \'\'"},' +
    '      {"header":"Phys.","width":"5%","cellExpr":"row.Signature_Type__c == \'Physician\' ? \'X\' : \'\'"},' +
    '      {"header":"Wit.","width":"5%","cellExpr":"row.Signature_Type__c == \'Witness\' ? \'X\' : \'\'"}' +
    '    ]}}, ' +
    '    {"type":"row","children":[' +
    '      {"type":"col","props":{"width":"33%"},"children":[' +
    '        {"type":"text","props":{"spans":[{"text":"Patient Signature","bold":true}]}},' +
    '        {"type":"image","props":{"source":"relatedFile","fromRelation":"Signatures__r","filterExpr":"Signature_Type__c == \'Patient\'","maxHeight":"60px"}}' +
    '      ]},' +
    '      {"type":"col","props":{"width":"33%"},"children":[' +
    '        {"type":"text","props":{"spans":[{"text":"Physician Signature","bold":true}]}},' +
    '        {"type":"image","props":{"source":"relatedFile","fromRelation":"Signatures__r","filterExpr":"Signature_Type__c == \'Physician\'","maxHeight":"60px"}}' +
    '      ]},' +
    '      {"type":"col","props":{"width":"33%"},"children":[' +
    '        {"type":"text","props":{"spans":[{"text":"Witness Signature","bold":true}]}},' +
    '        {"type":"image","props":{"source":"relatedFile","fromRelation":"Signatures__r","filterExpr":"Signature_Type__c == \'Witness\'","maxHeight":"60px"}}' +
    '      ]}' +
    '    ]}' +
    '  ]' +
    '}';

Template_Version__c tv = new Template_Version__c(
    Document_Template__c = dt.Id,
    Revision_Number__c = 1,
    Status__c = 'Published',
    Definition_Json__c = templateJson,
    Sample_Record_Id__c = form.Id
);
insert tv;

// Set this version as the default
dt.Default_Version__c = tv.Id;
update dt;

// --- 5. Print the test URL ---
String orgDomain = URL.getOrgDomainURL().toExternalForm();
String testUrl = orgDomain + '/apex/DocumentRender?templateVersionId=' + tv.Id + '&recordId=' + form.Id;

System.debug('=================================================================');
System.debug('SEED COMPLETE');
System.debug('Form Id:             ' + form.Id);
System.debug('Document Template:   ' + dt.Id);
System.debug('Template Version:    ' + tv.Id);
System.debug('-----------------------------------------------------------------');
System.debug('OPEN THIS URL TO SEE THE PDF:');
System.debug(testUrl);
System.debug('=================================================================');
