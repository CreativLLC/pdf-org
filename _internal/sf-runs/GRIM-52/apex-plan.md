# Plan — sf-apex-change (GRIM-52, family 2/3)

**Sub-type:** `create-class`
**Scope:** small
**Touches SOQL/DML:** true

## File changes

| Path | Op |
|---|---|
| `force-app/main/default/classes/TemplateVersionApprovalHandler.cls` | add |
| `force-app/main/default/classes/TemplateVersionApprovalHandler.cls-meta.xml` | add |
| `force-app/main/default/classes/TemplateVersionApprovalHandler_Test.cls` | add |
| `force-app/main/default/classes/TemplateVersionApprovalHandler_Test.cls-meta.xml` | add |

## Public API

```apex
public with sharing class TemplateVersionApprovalHandler {

    public class Input {
        @InvocableVariable(required=true label='Template Version Id')
        public Id templateVersionId;
    }

    @InvocableMethod(
        label='Stamp Approval On Related Mappings'
        description='For each Template_Version__c provided, stamp Approved_At__c=System.now() on every related Template_Mapping__c that does not already carry a stamp. Idempotent — re-running with the same input does nothing on second pass.'
        category='PDF Generator'
    )
    public static void stampApproval(List<Input> inputs) { ... }
}
```

Why a wrapper `Input` class: `@InvocableVariable` requires named fields. Allows Flow's Apex Action to pass the version ID as a named parameter.

## Algorithm

1. Collect every `Input.templateVersionId` from `inputs` into `Set<Id>`.
2. Single SOQL: `SELECT Id FROM Template_Mapping__c WHERE Template_Version__c IN :versionIds AND Approved_At__c = NULL`.
3. For each, `mapping.Approved_At__c = Datetime.now()`.
4. Single `update mappings` (DML).

Bulk-safe: one SOQL, one DML, regardless of input size. Governor-safe to ~200 versions per invocation (each could have many mappings — the SOQL is the limit; if a single version has 10k+ mappings, that's a separate scaling discussion).

Idempotent: the `Approved_At__c = NULL` filter ensures we never overwrite an existing stamp.

`with sharing`: the Flow context already enforces user perms; stamping the timestamp is system-style audit. We use `with sharing` for safety; if FLS is missing the DML will hard-fail and the Flow will surface the error in the UI.

## Test plan

`TemplateVersionApprovalHandler_Test.cls` — 4 methods:

1. `stampApproval_singleVersion_stampsAllUnstamped` — 1 version, 3 mappings (all unstamped) → all 3 stamped post-call.
2. `stampApproval_singleVersion_skipsAlreadyStamped` — 1 version, 3 mappings (1 pre-stamped) → only 2 newly stamped; pre-stamp untouched.
3. `stampApproval_bulk_200versions_singleSoqlSingleDml` — 200 versions, ~2 mappings each → Test.startTest()/stopTest() asserts Limits.getQueries() <= 1 + setup, Limits.getDmlStatements() <= 1 + setup.
4. `stampApproval_emptyInput_noOp` — empty list → no SOQL, no DML, no exception.

`@TestSetup` builds reusable Document_Template__c + Template_Version__c + Template_Mapping__c fixtures. The existing engagement uses `*Utils.generate*` factory pattern (see `ContactUtils.generateContact`); there's no `Template_VersionUtils` yet — we can either:
- (a) use inline `Document_Template__c dt = new Document_Template__c(...)` etc. in `@TestSetup` (simpler for one test class).
- (b) add `TemplateVersionUtils.generateTemplateVersion(...)` to match the convention.

Going with (a) for this PR — the factory pattern is engagement-wide but cluttering for a one-test-class addition. If the engagement wants to standardize, that's a follow-up.

## Coverage target

AC #3 says "≥75% per-class coverage" — matches the engagement default in `engagement.yaml: salesforce.coverage.per_class_target`. The class has ~12 logic lines plus the wrapper; 4 tests should hit ≥85%.

## Risk

- Bulk-200 test is mandatory (per `apex-trigger-handler.md` pattern doc and engagement convention).
- The Flow that calls this (next family) will pass exactly one version per invocation (record-triggered Flows fire one at a time per record, then Salesforce auto-bulks them at the platform level). The Apex must still handle a list (Flow's Apex Action sends the bulk batch).
