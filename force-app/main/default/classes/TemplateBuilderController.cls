/**
 * @AuraEnabled service for the templateLivePreview LWC.
 * Loads template + parent metadata, lists sample records to preview against,
 * renders unsaved JSON to HTML, and persists edits.
 */
public with sharing class TemplateBuilderController {

    public class TemplateContext {
        @AuraEnabled public String templateVersionId;
        @AuraEnabled public String templateName;
        @AuraEnabled public String templateId;
        @AuraEnabled public String targetSObject;
        @AuraEnabled public String definitionJson;
        @AuraEnabled public String status;
        @AuraEnabled public String revisionNumber;
        @AuraEnabled public String sampleRecordId;
    }

    public class SampleRecord {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
    }

    public class PreviewResult {
        @AuraEnabled public String html;
        @AuraEnabled public String fontStack;
    }

    public class FieldInfo {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
    }

    public class RelationInfo {
        @AuraEnabled public String relationshipName;
        @AuraEnabled public String childObject;
        @AuraEnabled public List<FieldInfo> fields;
    }

    public class ObjectMetadata {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public List<FieldInfo> fields;
        @AuraEnabled public List<RelationInfo> relations;
    }

    @AuraEnabled(cacheable=true)
    public static ObjectMetadata describeObject(String objectApi) {
        if (String.isBlank(objectApi)) throw new AuraHandledException('objectApi required');
        if (!Pattern.matches('[A-Za-z_][A-Za-z_0-9]*', objectApi)) {
            throw new AuraHandledException('Illegal object name: ' + objectApi);
        }
        Schema.SObjectType t = Schema.getGlobalDescribe().get(objectApi);
        if (t == null) throw new AuraHandledException('Unknown SObject: ' + objectApi);
        Schema.DescribeSObjectResult d = t.getDescribe();

        ObjectMetadata om = new ObjectMetadata();
        om.apiName = d.getName();
        om.label = d.getLabel();
        om.fields = new List<FieldInfo>();
        om.relations = new List<RelationInfo>();

        Set<String> systemSkip = new Set<String>{
            'IsDeleted', 'SystemModstamp', 'LastViewedDate', 'LastReferencedDate',
            'LastActivityDate', 'OwnerId', 'CurrencyIsoCode', 'CreatedById', 'LastModifiedById'
        };

        for (Schema.SObjectField f : d.fields.getMap().values()) {
            Schema.DescribeFieldResult fd = f.getDescribe();
            if (!fd.isAccessible()) continue;
            if (systemSkip.contains(fd.getName())) continue;
            FieldInfo fi = new FieldInfo();
            fi.apiName = fd.getName();
            fi.label = fd.getLabel();
            fi.type = String.valueOf(fd.getType());
            om.fields.add(fi);
        }
        om.fields.sort(new FieldByLabel());

        for (Schema.ChildRelationship cr : d.getChildRelationships()) {
            String relName = cr.getRelationshipName();
            if (String.isBlank(relName)) continue;
            Schema.DescribeSObjectResult childD = cr.getChildSObject().getDescribe();
            if (!childD.isAccessible()) continue;
            // Skip standard noise
            if (childD.getName() == 'AttachedContentDocument'
                || childD.getName() == 'ContentDocumentLink'
                || childD.getName() == 'Attachment'
                || childD.getName() == 'CombinedAttachment'
                || childD.getName() == 'FeedItem'
                || childD.getName() == 'FeedSubscriptionsForEntity'
                || childD.getName() == 'EntitySubscription'
                || childD.getName() == 'TopicAssignment'
                || childD.getName() == 'ProcessInstance'
                || childD.getName() == 'ProcessInstanceHistory'
                || childD.getName() == 'RecordAction'
                || childD.getName() == 'EmailMessage'
                || childD.getName() == 'Task'
                || childD.getName() == 'Event'
                || childD.getName() == 'NoteAndAttachment'
                || childD.getName() == 'Note'
                || childD.getName() == 'CollaborationGroupRecord'
                || childD.getName() == 'DuplicateRecordItem') continue;

            RelationInfo ri = new RelationInfo();
            ri.relationshipName = relName + (childD.isCustom() ? '__r' : '');
            ri.childObject = childD.getName();
            ri.fields = new List<FieldInfo>();
            for (Schema.SObjectField cf : childD.fields.getMap().values()) {
                Schema.DescribeFieldResult cfd = cf.getDescribe();
                if (!cfd.isAccessible()) continue;
                if (systemSkip.contains(cfd.getName())) continue;
                FieldInfo cfi = new FieldInfo();
                cfi.apiName = cfd.getName();
                cfi.label = cfd.getLabel();
                cfi.type = String.valueOf(cfd.getType());
                ri.fields.add(cfi);
            }
            ri.fields.sort(new FieldByLabel());
            om.relations.add(ri);
        }
        return om;
    }

    public class FieldByLabel implements Comparator<FieldInfo> {
        public Integer compare(FieldInfo a, FieldInfo b) {
            return a.label.compareTo(b.label);
        }
    }

    @AuraEnabled(cacheable=false)
    public static TemplateContext getContext(Id templateVersionId) {
        if (templateVersionId == null) throw new AuraHandledException('templateVersionId required');
        Template_Version__c tv = [
            SELECT Id, Name, Document_Template__c, Document_Template__r.Name, Document_Template__r.Target_SObject__c,
                   Definition_Json__c, Status__c, Revision_Number__c, Sample_Record_Id__c
            FROM Template_Version__c
            WHERE Id = :templateVersionId
            LIMIT 1
        ];
        TemplateContext c = new TemplateContext();
        c.templateVersionId = tv.Id;
        c.templateName = tv.Document_Template__r.Name;
        c.templateId = tv.Document_Template__c;
        c.targetSObject = tv.Document_Template__r.Target_SObject__c;
        c.definitionJson = tv.Definition_Json__c;
        c.status = tv.Status__c;
        c.revisionNumber = tv.Revision_Number__c == null ? null : String.valueOf(tv.Revision_Number__c.intValue());
        c.sampleRecordId = tv.Sample_Record_Id__c;
        return c;
    }

    @AuraEnabled(cacheable=true)
    public static List<SampleRecord> listSampleRecords(String objectApi, Integer maxRows) {
        if (String.isBlank(objectApi)) return new List<SampleRecord>();
        Integer lim = (maxRows == null || maxRows <= 0) ? 50 : Math.min(maxRows, 200);
        if (!Pattern.matches('[A-Za-z_][A-Za-z_0-9]*', objectApi)) {
            throw new AuraHandledException('Illegal object name: ' + objectApi);
        }
        String soql = 'SELECT Id, Name FROM ' + objectApi
            + ' ORDER BY LastModifiedDate DESC LIMIT ' + lim;
        List<SampleRecord> out = new List<SampleRecord>();
        try {
            for (SObject r : Database.query(soql)) {
                SampleRecord sr = new SampleRecord();
                sr.id = (String) r.get('Id');
                Object n = r.get('Name');
                sr.name = n == null ? sr.id : String.valueOf(n);
                out.add(sr);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Failed to list ' + objectApi + ': ' + e.getMessage());
        }
        return out;
    }

    @AuraEnabled
    public static PreviewResult previewTemplate(String defJson, String targetSObject, Id sampleRecordId) {
        if (String.isBlank(defJson)) throw new AuraHandledException('Template JSON is empty.');
        if (String.isBlank(targetSObject)) throw new AuraHandledException('Target SObject is missing on the template.');
        if (sampleRecordId == null) throw new AuraHandledException('Pick a sample record to preview against.');
        try {
            PdfTemplateService.PageModel m = PdfTemplateService.buildFromJson(defJson, targetSObject, sampleRecordId);
            PreviewResult r = new PreviewResult();
            r.fontStack = m.page.fontStack;
            r.html = String.join(m.htmlBlocks, '');
            return r;
        } catch (PdfTemplateService.TemplateException e) {
            throw new AuraHandledException(e.getMessage());
        } catch (Exception e) {
            throw new AuraHandledException('Render error: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void saveTemplate(Id templateVersionId, String defJson, String sampleRecordId) {
        if (templateVersionId == null) throw new AuraHandledException('templateVersionId required');
        // Validate JSON parses before saving.
        try {
            JSON.deserializeUntyped(defJson);
        } catch (Exception e) {
            throw new AuraHandledException('JSON does not parse: ' + e.getMessage());
        }
        Template_Version__c tv = new Template_Version__c(
            Id = templateVersionId,
            Definition_Json__c = defJson
        );
        if (String.isNotBlank(sampleRecordId)) {
            tv.Sample_Record_Id__c = sampleRecordId;
        }
        update tv;
    }
}
