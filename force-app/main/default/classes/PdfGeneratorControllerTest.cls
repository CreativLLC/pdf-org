@IsTest
private class PdfGeneratorControllerTest {

    private static Form__c makeForm() {
        Form__c f = new Form__c(
            Name = 'PG Test 001',
            Patient_Name__c = 'Test Patient',
            Status__c = 'Complete',
            Revision_Number__c = 1
        );
        insert f;
        return f;
    }

    private static Document_Template__c makeTemplate(Boolean overwrite) {
        Document_Template__c dt = new Document_Template__c(
            Name = 'PG Test Template',
            Target_SObject__c = 'Form__c',
            Active__c = true,
            Overwrite_Existing_File__c = overwrite
        );
        insert dt;
        Template_Version__c tv = new Template_Version__c(
            Document_Template__c = dt.Id,
            Revision_Number__c = 1,
            Status__c = 'Published',
            Definition_Json__c = '{"root":{"type":"text","props":{"spans":[{"token":"Patient_Name__c"}]}}}'
        );
        insert tv;
        dt.Default_Version__c = tv.Id;
        update dt;
        return dt;
    }

    @IsTest
    static void generateAndSaveCreatesContentVersionAndLink() {
        Form__c f = makeForm();
        Document_Template__c dt = makeTemplate(false);

        Test.startTest();
        PdfGeneratorController.GenerateResult r = PdfGeneratorController.generateAndSave(dt.Id, f.Id);
        Test.stopTest();

        System.assertNotEquals(null, r.contentDocumentId, 'Should return ContentDocumentId');
        System.assertNotEquals(null, r.contentVersionId, 'Should return ContentVersionId');
        System.assert(r.fileName.endsWith('.pdf'), 'File name should end with .pdf');

        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink
            WHERE ContentDocumentId = :r.contentDocumentId AND LinkedEntityId = :f.Id
        ];
        System.assertEquals(1, links.size(), 'Should link the file to the source record');
    }

    @IsTest
    static void generateAndSaveByNameWorks() {
        Form__c f = makeForm();
        Document_Template__c dt = makeTemplate(false);

        Test.startTest();
        PdfGeneratorController.GenerateResult r = PdfGeneratorController.generateAndSaveByName(dt.Name, f.Id);
        Test.stopTest();

        System.assertNotEquals(null, r.contentDocumentId);
    }

    @IsTest
    static void overwriteRemovesPriorGeneration() {
        Form__c f = makeForm();
        Document_Template__c dt = makeTemplate(true);

        Test.startTest();
        PdfGeneratorController.GenerateResult r1 = PdfGeneratorController.generateAndSave(dt.Id, f.Id);
        PdfGeneratorController.GenerateResult r2 = PdfGeneratorController.generateAndSave(dt.Id, f.Id);
        Test.stopTest();

        System.assertNotEquals(r1.contentDocumentId, r2.contentDocumentId, 'Second run creates a new doc');

        Integer linkCount = [
            SELECT COUNT() FROM ContentDocumentLink
            WHERE LinkedEntityId = :f.Id
        ];
        System.assertEquals(1, linkCount, 'Old generation should have been deleted; only one link remains');
    }

    @IsTest
    static void mappingRuleSelectsVersion() {
        Form__c f = makeForm();
        Document_Template__c dt = makeTemplate(false);
        // Create a second version and a mapping rule that should pick it for Revision_Number__c=1
        Template_Version__c tv2 = new Template_Version__c(
            Document_Template__c = dt.Id,
            Revision_Number__c = 2,
            Status__c = 'Published',
            Definition_Json__c = '{"root":{"type":"text","props":{"spans":[{"text":"V2"}]}}}'
        );
        insert tv2;
        insert new Template_Mapping__c(
            Document_Template__c = dt.Id,
            Template_Version__c = tv2.Id,
            Match_Field_Api_Name__c = 'Revision_Number__c',
            Match_Operator__c = 'Equals',
            Match_Value__c = '1',
            Priority__c = 10
        );

        Test.startTest();
        PdfGeneratorController.GenerateResult r = PdfGeneratorController.generateAndSave(dt.Id, f.Id);
        Test.stopTest();

        System.assertEquals(tv2.Id, r.templateVersionId, 'Mapping rule should have selected v2');
    }

    @IsTest
    static void inactiveTemplateThrows() {
        Form__c f = makeForm();
        Document_Template__c dt = makeTemplate(false);
        dt.Active__c = false;
        update dt;

        try {
            PdfGeneratorController.generateAndSave(dt.Id, f.Id);
            System.assert(false, 'Should have thrown for inactive template');
        } catch (AuraHandledException e) {
            // Expected
        }
    }

    @IsTest
    static void noVersionThrows() {
        Form__c f = makeForm();
        Document_Template__c dt = new Document_Template__c(
            Name = 'No Versions',
            Target_SObject__c = 'Form__c',
            Active__c = true
        );
        insert dt;
        try {
            PdfGeneratorController.generateAndSave(dt.Id, f.Id);
            System.assert(false, 'Should have thrown — no versions or default');
        } catch (AuraHandledException e) {
            // Expected
        }
    }

    @IsTest
    static void fileNamePatternExpands() {
        Form__c f = makeForm();
        Document_Template__c dt = makeTemplate(false);
        dt.File_Naming_Pattern__c = '{{Name}}-{{Patient_Name__c}}-rev{{Revision_Number__c}}';
        update dt;

        Test.startTest();
        PdfGeneratorController.GenerateResult r = PdfGeneratorController.generateAndSave(dt.Id, f.Id);
        Test.stopTest();

        System.assert(r.fileName.contains('PG Test 001'), 'Name token should expand');
        System.assert(r.fileName.contains('Test Patient'), 'Patient_Name__c token should expand');
        System.assert(r.fileName.contains('rev1'), 'Revision_Number__c token should expand');
    }
}
