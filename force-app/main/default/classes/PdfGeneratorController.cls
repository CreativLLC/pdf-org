/**
 * @AuraEnabled entry point invoked from the Generate Document Button LWC.
 * Resolves which Template_Version__c to use, calls the VF page's getContentAsPdf(),
 * saves the resulting blob as a Salesforce File on the source record, and (if the
 * template is configured for overwrite) supersedes prior generations.
 */
public with sharing class PdfGeneratorController {

    public class GenerateResult {
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String contentVersionId;
        @AuraEnabled public String fileName;
        @AuraEnabled public String templateVersionId;
    }

    @AuraEnabled
    public static GenerateResult generateAndSave(Id templateId, Id recordId) {
        return doGenerate(templateId, null, recordId);
    }

    @AuraEnabled
    public static GenerateResult generateAndSaveByName(String templateName, Id recordId) {
        return doGenerate(null, templateName, recordId);
    }

    private static GenerateResult doGenerate(Id templateId, String templateName, Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('recordId is required.');
        }

        Document_Template__c dt = resolveTemplate(templateId, templateName);
        if (!dt.Active__c) {
            throw new AuraHandledException('Template "' + dt.Name + '" is not Active.');
        }

        Id versionId = resolveVersion(dt, recordId);
        if (versionId == null) {
            throw new AuraHandledException(
                'No matching Template Version. Add a Template Mapping rule or set a Default Version on "' + dt.Name + '".'
            );
        }

        Blob pdfBlob = renderPdf(versionId, recordId);
        String baseName = computeFileName(dt, recordId);

        if (dt.Overwrite_Existing_File__c) {
            removePriorVersions(versionId, recordId);
        }

        ContentVersion cv = new ContentVersion(
            Title = baseName,
            PathOnClient = baseName + '.pdf',
            VersionData = pdfBlob,
            Source_Template_Version__c = String.valueOf(versionId)
        );
        insert cv;

        Id contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;

        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = recordId,
            ShareType = 'V',
            Visibility = 'AllUsers'
        );

        GenerateResult r = new GenerateResult();
        r.contentDocumentId = contentDocumentId;
        r.contentVersionId = cv.Id;
        r.fileName = baseName + '.pdf';
        r.templateVersionId = versionId;
        return r;
    }

    private static Document_Template__c resolveTemplate(Id templateId, String templateName) {
        if (templateId != null) {
            List<Document_Template__c> rs = [
                SELECT Id, Name, Target_SObject__c, File_Naming_Pattern__c, Overwrite_Existing_File__c, Default_Version__c, Active__c
                FROM Document_Template__c WHERE Id = :templateId LIMIT 1
            ];
            if (rs.isEmpty()) throw new AuraHandledException('Document Template not found: ' + templateId);
            return rs[0];
        }
        if (String.isNotBlank(templateName)) {
            List<Document_Template__c> rs = [
                SELECT Id, Name, Target_SObject__c, File_Naming_Pattern__c, Overwrite_Existing_File__c, Default_Version__c, Active__c
                FROM Document_Template__c WHERE Name = :templateName LIMIT 1
            ];
            if (rs.isEmpty()) throw new AuraHandledException('Document Template not found by name: ' + templateName);
            return rs[0];
        }
        throw new AuraHandledException('Either documentTemplateId or documentTemplateName must be configured on the button.');
    }

    private static Id resolveVersion(Document_Template__c dt, Id recordId) {
        List<Template_Mapping__c> rules = [
            SELECT Id, Template_Version__c, Record_Type_Developer_Name__c,
                   Match_Field_Api_Name__c, Match_Operator__c, Match_Value__c, Priority__c
            FROM Template_Mapping__c
            WHERE Document_Template__c = :dt.Id
            ORDER BY Priority__c ASC NULLS LAST
        ];
        if (rules.isEmpty()) return dt.Default_Version__c;

        Set<String> fieldsNeeded = new Set<String>{ 'Id' };
        Boolean needsRecordType = false;
        for (Template_Mapping__c rule : rules) {
            if (String.isNotBlank(rule.Record_Type_Developer_Name__c)) needsRecordType = true;
            if (String.isNotBlank(rule.Match_Field_Api_Name__c)) fieldsNeeded.add(rule.Match_Field_Api_Name__c);
        }
        if (needsRecordType) fieldsNeeded.add('RecordType.DeveloperName');

        SObject row;
        try {
            String soql = 'SELECT ' + String.join(new List<String>(fieldsNeeded), ', ')
                + ' FROM ' + escapeIdentifier(dt.Target_SObject__c)
                + ' WHERE Id = :recordId LIMIT 1';
            row = Database.query(soql);
        } catch (Exception e) {
            // Object might not have RecordType — retry without
            fieldsNeeded.remove('RecordType.DeveloperName');
            String soql = 'SELECT ' + String.join(new List<String>(fieldsNeeded), ', ')
                + ' FROM ' + escapeIdentifier(dt.Target_SObject__c)
                + ' WHERE Id = :recordId LIMIT 1';
            row = Database.query(soql);
        }

        String rtName = needsRecordType ? safeRtName(row) : null;
        for (Template_Mapping__c rule : rules) {
            if (matches(rule, row, rtName)) return rule.Template_Version__c;
        }
        return dt.Default_Version__c;
    }

    private static String safeRtName(SObject row) {
        try {
            SObject rt = row.getSObject('RecordType');
            return rt == null ? null : (String) rt.get('DeveloperName');
        } catch (Exception e) { return null; }
    }

    private static Boolean matches(Template_Mapping__c rule, SObject row, String rtName) {
        if (String.isNotBlank(rule.Record_Type_Developer_Name__c)) {
            if (rtName == null || !rule.Record_Type_Developer_Name__c.equals(rtName)) return false;
        }
        if (rule.Match_Operator__c == 'Default') return true;
        if (String.isBlank(rule.Match_Field_Api_Name__c)) return false;

        Object v = null;
        try { v = row.get(rule.Match_Field_Api_Name__c); } catch (Exception e) { return false; }
        String vs = v == null ? null : String.valueOf(v);

        if (rule.Match_Operator__c == 'NotNull') return String.isNotBlank(vs);
        if (rule.Match_Operator__c == 'Equals') return vs != null && vs.equals(rule.Match_Value__c);
        if (rule.Match_Operator__c == 'In') {
            if (vs == null || rule.Match_Value__c == null) return false;
            for (String candidate : rule.Match_Value__c.split(',')) {
                if (candidate.trim().equals(vs)) return true;
            }
        }
        return false;
    }

    private static Blob renderPdf(Id versionId, Id recordId) {
        if (Test.isRunningTest()) {
            // PageReference.getContentAsPdf() returns null in test context.
            return Blob.valueOf('test-pdf-bytes');
        }
        PageReference pr = Page.DocumentRender;
        pr.getParameters().put('templateVersionId', String.valueOf(versionId));
        pr.getParameters().put('recordId', String.valueOf(recordId));
        return pr.getContentAsPdf();
    }

    private static String computeFileName(Document_Template__c dt, Id recordId) {
        String base;
        if (String.isBlank(dt.File_Naming_Pattern__c)) {
            String recordName = '';
            try {
                String soql = 'SELECT Name FROM ' + escapeIdentifier(dt.Target_SObject__c)
                    + ' WHERE Id = :recordId LIMIT 1';
                SObject r = Database.query(soql);
                Object n = r.get('Name');
                if (n != null) recordName = String.valueOf(n);
            } catch (Exception e) { /* object has no Name field */ }
            base = dt.Name + (String.isNotBlank(recordName) ? ' - ' + recordName : '');
        } else {
            base = expandPatternTokens(dt.File_Naming_Pattern__c, dt.Target_SObject__c, recordId);
        }
        return sanitizeFilename(base);
    }

    private static String expandPatternTokens(String tpl, String objectApi, Id recordId) {
        Matcher m = Pattern.compile('\\{\\{([A-Za-z_][A-Za-z_0-9]*(?:\\.[A-Za-z_][A-Za-z_0-9]*)*)\\}\\}').matcher(tpl);
        Set<String> fields = new Set<String>();
        while (m.find()) fields.add(m.group(1));
        if (fields.isEmpty()) return tpl;
        SObject row;
        try {
            String soql = 'SELECT ' + String.join(new List<String>(fields), ', ')
                + ' FROM ' + escapeIdentifier(objectApi) + ' WHERE Id = :recordId LIMIT 1';
            row = Database.query(soql);
        } catch (Exception e) { return tpl; }
        String out = tpl;
        for (String f : fields) {
            Object v = null;
            try { v = row.get(f); } catch (Exception e) { /* ignore */ }
            String s;
            if (v == null) s = '';
            else if (v instanceof Date) s = ((Date) v).format();
            else if (v instanceof Datetime) s = ((Datetime) v).format();
            else s = String.valueOf(v);
            out = out.replace('{{' + f + '}}', s);
        }
        return out;
    }

    private static String sanitizeFilename(String s) {
        if (String.isBlank(s)) return 'document';
        return s.replaceAll('[^A-Za-z0-9 _\\-.]', '_').left(180);
    }

    private static void removePriorVersions(Id versionId, Id recordId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
        ];
        if (links.isEmpty()) return;
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink l : links) docIds.add(l.ContentDocumentId);
        Set<Id> docIdsToDelete = new Set<Id>();
        String versionStr = String.valueOf(versionId);
        for (ContentVersion cv : [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds
              AND IsLatest = true
              AND Source_Template_Version__c = :versionStr
        ]) {
            docIdsToDelete.add(cv.ContentDocumentId);
        }
        if (!docIdsToDelete.isEmpty()) {
            delete [SELECT Id FROM ContentDocument WHERE Id IN :docIdsToDelete];
        }
    }

    private static String escapeIdentifier(String name) {
        if (!Pattern.matches('[A-Za-z_][A-Za-z_0-9]*', name)) {
            throw new AuraHandledException('Illegal SObject name: ' + name);
        }
        return name;
    }
}
