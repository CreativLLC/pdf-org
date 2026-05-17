@IsTest
private class TemplateVersionApprovalHandler_Test {

    @TestSetup
    static void seed() {
        Document_Template__c dt = new Document_Template__c(
            Name = 'Approval Test Template',
            Target_SObject__c = 'Form__c'
        );
        insert dt;

        Template_Version__c v1 = newVersion(dt.Id, 1);
        Template_Version__c v2 = newVersion(dt.Id, 2);
        insert new List<Template_Version__c>{ v1, v2 };

        // v1 has 3 mappings, 1 pre-stamped
        Template_Mapping__c m1 = newMapping(dt.Id, v1.Id, 10, null);
        Template_Mapping__c m2 = newMapping(dt.Id, v1.Id, 20, Datetime.newInstance(2024, 1, 1));
        Template_Mapping__c m3 = newMapping(dt.Id, v1.Id, 30, null);

        // v2 has 1 mapping, unstamped
        Template_Mapping__c m4 = newMapping(dt.Id, v2.Id, 10, null);

        insert new List<Template_Mapping__c>{ m1, m2, m3, m4 };
    }

    @IsTest
    static void stampApproval_singleVersion_stampsAllUnstamped() {
        Template_Version__c v = [
            SELECT Id FROM Template_Version__c WHERE Revision_Number__c = 2 LIMIT 1
        ];

        TemplateVersionApprovalHandler.Input req = new TemplateVersionApprovalHandler.Input();
        req.templateVersionId = v.Id;

        Test.startTest();
        TemplateVersionApprovalHandler.stampApproval(
            new List<TemplateVersionApprovalHandler.Input>{ req }
        );
        Test.stopTest();

        List<Template_Mapping__c> stamped = [
            SELECT Approved_At__c FROM Template_Mapping__c
            WHERE Template_Version__c = :v.Id
        ];
        System.assertEquals(1, stamped.size(), 'Setup created exactly 1 mapping for v2');
        System.assertNotEquals(null, stamped[0].Approved_At__c, 'Approved_At__c should be stamped');
    }

    @IsTest
    static void stampApproval_singleVersion_skipsAlreadyStamped() {
        Template_Version__c v = [
            SELECT Id FROM Template_Version__c WHERE Revision_Number__c = 1 LIMIT 1
        ];

        Template_Mapping__c preStamped = [
            SELECT Id, Approved_At__c FROM Template_Mapping__c
            WHERE Template_Version__c = :v.Id AND Approved_At__c != NULL
            LIMIT 1
        ];
        Datetime pre = preStamped.Approved_At__c;

        TemplateVersionApprovalHandler.Input req = new TemplateVersionApprovalHandler.Input();
        req.templateVersionId = v.Id;

        Test.startTest();
        TemplateVersionApprovalHandler.stampApproval(
            new List<TemplateVersionApprovalHandler.Input>{ req }
        );
        Test.stopTest();

        Template_Mapping__c reloaded = [
            SELECT Approved_At__c FROM Template_Mapping__c WHERE Id = :preStamped.Id
        ];
        System.assertEquals(pre, reloaded.Approved_At__c,
            'Pre-stamped mapping must NOT be overwritten');

        List<Template_Mapping__c> newlyStamped = [
            SELECT Approved_At__c FROM Template_Mapping__c
            WHERE Template_Version__c = :v.Id AND Id != :preStamped.Id
        ];
        for (Template_Mapping__c m : newlyStamped) {
            System.assertNotEquals(null, m.Approved_At__c,
                'Previously-unstamped mapping should now carry a stamp');
        }
    }

    @IsTest
    static void stampApproval_bulk200versions_singleSoqlSingleDml() {
        Document_Template__c dt = [SELECT Id FROM Document_Template__c LIMIT 1];

        List<Template_Version__c> bulkVersions = new List<Template_Version__c>();
        for (Integer i = 0; i < 200; i++) {
            bulkVersions.add(newVersion(dt.Id, i + 100));
        }
        insert bulkVersions;

        List<Template_Mapping__c> bulkMappings = new List<Template_Mapping__c>();
        for (Template_Version__c v : bulkVersions) {
            bulkMappings.add(newMapping(dt.Id, v.Id, 10, null));
            bulkMappings.add(newMapping(dt.Id, v.Id, 20, null));
        }
        insert bulkMappings;

        List<TemplateVersionApprovalHandler.Input> inputs =
            new List<TemplateVersionApprovalHandler.Input>();
        for (Template_Version__c v : bulkVersions) {
            TemplateVersionApprovalHandler.Input req = new TemplateVersionApprovalHandler.Input();
            req.templateVersionId = v.Id;
            inputs.add(req);
        }

        Test.startTest();
        Integer soqlBefore = Limits.getQueries();
        Integer dmlBefore = Limits.getDmlStatements();

        TemplateVersionApprovalHandler.stampApproval(inputs);

        Integer soqlAfter = Limits.getQueries();
        Integer dmlAfter = Limits.getDmlStatements();
        Test.stopTest();

        System.assertEquals(1, soqlAfter - soqlBefore,
            'Should issue exactly 1 SOQL regardless of input size');
        System.assertEquals(1, dmlAfter - dmlBefore,
            'Should issue exactly 1 DML regardless of input size');

        Set<Id> versionIds = new Set<Id>();
        for (Template_Version__c v : bulkVersions) versionIds.add(v.Id);
        Integer stampedCount = [
            SELECT COUNT() FROM Template_Mapping__c
            WHERE Template_Version__c IN :versionIds AND Approved_At__c != NULL
        ];
        System.assertEquals(400, stampedCount,
            '200 versions × 2 mappings each = 400 stamps');
    }

    @IsTest
    static void stampApproval_emptyInput_noOp() {
        Integer soqlBefore;
        Integer dmlBefore;
        Integer soqlAfter;
        Integer dmlAfter;

        Test.startTest();
        soqlBefore = Limits.getQueries();
        dmlBefore = Limits.getDmlStatements();

        TemplateVersionApprovalHandler.stampApproval(
            new List<TemplateVersionApprovalHandler.Input>()
        );

        soqlAfter = Limits.getQueries();
        dmlAfter = Limits.getDmlStatements();
        Test.stopTest();

        System.assertEquals(0, soqlAfter - soqlBefore, 'Empty input must not issue SOQL');
        System.assertEquals(0, dmlAfter - dmlBefore, 'Empty input must not issue DML');
    }

    // ── helpers ───────────────────────────────────────────────────

    private static Template_Version__c newVersion(Id documentTemplateId, Integer rev) {
        return new Template_Version__c(
            Document_Template__c = documentTemplateId,
            Revision_Number__c = rev,
            Status__c = 'Draft'
        );
    }

    private static Template_Mapping__c newMapping(
        Id documentTemplateId, Id templateVersionId, Integer priority, Datetime approvedAt
    ) {
        return new Template_Mapping__c(
            Document_Template__c = documentTemplateId,
            Template_Version__c = templateVersionId,
            Priority__c = priority,
            Match_Operator__c = 'Default',
            Approved_At__c = approvedAt
        );
    }
}
