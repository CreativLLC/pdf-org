@IsTest
private class PdfTemplateServiceTest {

    private static Form__c makeForm(String status) {
        Form__c f = new Form__c(
            Name = 'Test Form 1',
            Patient_Name__c = 'Jane Doe',
            Status__c = status,
            Comments__c = 'Procedure completed without complications.',
            Revision_Number__c = 1
        );
        insert f;
        return f;
    }

    private static Signature__c makeSig(Id formId, String type, String signedBy) {
        Signature__c s = new Signature__c(
            Form__c = formId,
            Signature_Type__c = type,
            Signed_By__c = signedBy,
            Signed_At__c = Datetime.now()
        );
        insert s;
        return s;
    }

    private static void attachFile(Id linkedEntityId, String title) {
        // 5x5 red dot PNG
        String b64 = 'iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAYAAACNbyblAAAAHElEQVQI12P4//8/w38GIAXDIBKE0DHxgljNBAAO9TXL0Y4OHwAAAABJRU5ErkJggg==';
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.png',
            VersionData = EncodingUtil.base64Decode(b64)
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId = linkedEntityId,
            ShareType = 'V'
        );
    }

    private static Template_Version__c makeTemplate(String defJson) {
        Document_Template__c dt = new Document_Template__c(
            Name = 'Test Template',
            Target_SObject__c = 'Form__c',
            Active__c = true
        );
        insert dt;
        Template_Version__c tv = new Template_Version__c(
            Document_Template__c = dt.Id,
            Revision_Number__c = 1,
            Status__c = 'Published',
            Definition_Json__c = defJson
        );
        insert tv;
        return tv;
    }

    @IsTest
    static void rendersTextWithMergeTokensAndConditional() {
        Form__c f = makeForm('Complete');
        String defJson = '{'
            + '"page": {"size":"LETTER","orientation":"portrait","margins":"0.5in"},'
            + '"root": {"type":"row","children":[{"type":"col","props":{"width":"100%"},"children":['
            +   '{"type":"text","props":{"spans":[{"text":"Patient: ","bold":true},{"token":"Patient_Name__c"}]}},'
            +   '{"type":"text","visibleIf":"Status__c == \'Complete\'","props":{"spans":[{"text":"COMPLETED"}]}},'
            +   '{"type":"text","visibleIf":"Status__c == \'Draft\'","props":{"spans":[{"text":"DRAFT-ONLY"}]}}'
            + ']}]}'
            + '}';
        Template_Version__c tv = makeTemplate(defJson);

        Test.startTest();
        PdfTemplateService.PageModel m = PdfTemplateService.build(tv.Id, f.Id);
        Test.stopTest();

        System.assertNotEquals(null, m, 'Model should be populated');
        String all = String.join(m.htmlBlocks, '');
        System.assert(all.contains('Jane Doe'), 'Should resolve patient name token');
        System.assert(all.contains('COMPLETED'), 'Conditional block should render when Status=Complete');
        System.assert(!all.contains('DRAFT-ONLY'), 'Conditional block should be hidden when Status=Complete');
    }

    @IsTest
    static void rendersRelatedListTable() {
        Form__c f = makeForm('Complete');
        makeSig(f.Id, 'Patient', 'Jane Doe');
        makeSig(f.Id, 'Physician', 'Dr. Smith');

        String defJson = '{'
            + '"root": {"type":"text","props":{"spans":[{"text":"Header"}]}},'
            + '"tables": [{"type":"table","props":{"fromRelation":"Signatures__r","columns":['
            +   '{"header":"Type","spans":[{"token":"row.Signature_Type__c"}]},'
            +   '{"header":"Signed By","spans":[{"token":"row.Signed_By__c"}]},'
            +   '{"header":"Patient X","cellExpr":"row.Signature_Type__c == \'Patient\' ? \'X\' : \'\'"}'
            + ']}}]'
            + '}';
        Template_Version__c tv = makeTemplate(defJson);

        Test.startTest();
        PdfTemplateService.PageModel m = PdfTemplateService.build(tv.Id, f.Id);
        Test.stopTest();

        String all = String.join(m.htmlBlocks, '');
        System.assert(all.contains('Jane Doe'), 'Patient row should appear');
        System.assert(all.contains('Dr. Smith'), 'Physician row should appear');
        // Patient row should have an X in the cellExpr column
        System.assert(all.contains('X'), 'cellExpr should evaluate to X for patient row');
    }

    @IsTest
    static void embedsRelatedFileImage() {
        Form__c f = makeForm('Complete');
        Signature__c s = makeSig(f.Id, 'Physician', 'Dr. Smith');
        attachFile(s.Id, 'sig-physician');

        String defJson = '{'
            + '"root": {"type":"image","props":{"source":"relatedFile","fromRelation":"Signatures__r","filterExpr":"Signature_Type__c == \'Physician\'","maxWidth":"200px","maxHeight":"80px"}}'
            + '}';
        Template_Version__c tv = makeTemplate(defJson);

        Test.startTest();
        PdfTemplateService.PageModel m = PdfTemplateService.build(tv.Id, f.Id);
        Test.stopTest();

        String all = String.join(m.htmlBlocks, '');
        System.assert(all.contains('data:image/png;base64,'), 'Image should be embedded as data URI');
    }

    @IsTest
    static void evaluatesCompoundExpression() {
        Form__c f = makeForm('Complete');
        f.Revision_Number__c = 3;
        update f;
        String defJson = '{'
            + '"root": {"type":"text","visibleIf":"Status__c == \'Complete\' AND Revision_Number__c >= 2","props":{"spans":[{"text":"VISIBLE"}]}}'
            + '}';
        Template_Version__c tv = makeTemplate(defJson);

        Test.startTest();
        PdfTemplateService.PageModel m = PdfTemplateService.build(tv.Id, f.Id);
        Test.stopTest();

        System.assert(String.join(m.htmlBlocks, '').contains('VISIBLE'),
            'Compound AND with comparison should evaluate true');
    }

    @IsTest
    static void controllerHandlesMissingParams() {
        Test.setCurrentPage(Page.DocumentRender);
        DocumentRenderController c = new DocumentRenderController();
        System.assertNotEquals(null, c.errorMessage, 'Should report missing param error');
    }

    @IsTest
    static void controllerRendersWithValidParams() {
        Form__c f = makeForm('Complete');
        Template_Version__c tv = makeTemplate('{"root":{"type":"text","props":{"spans":[{"token":"Patient_Name__c"}]}}}');

        PageReference pr = Page.DocumentRender;
        pr.getParameters().put('templateVersionId', tv.Id);
        pr.getParameters().put('recordId', f.Id);
        Test.setCurrentPage(pr);

        DocumentRenderController c = new DocumentRenderController();
        System.assertEquals(null, c.errorMessage, 'No error expected');
        System.assertNotEquals(null, c.pageModel, 'Page model should be populated');
        System.assert(String.join(c.pageModel.htmlBlocks, '').contains('Jane Doe'));
    }
}
