# `sf-discover-classify`

You are inventorying the engagement's SFDX metadata and deciding which artifacts are **significant** enough to document. Salesforce orgs have thousands of native fields, default Apex classes from managed packages, and trivially-customized standard objects — none of which deserve their own doc. Your job is to pick out the artifacts that actually *carry* the engagement's business logic and data model.

## Inputs

- `$smoke-validate-sfdx.output` — confirmed SFDX presence + categories.
- The engagement's `force-app/main/default/` directory (read-only).

## Tools

Read, Glob, Grep, Bash (for find / wc / grep counting). No file writes here. No SF CLI.

## What counts as significant

### Significant objects

Include in the output list:

- **Every custom object** (`*__c` API name, files under `objects/<Object>__c/`).
- **Customized standard objects** — Account, Contact, Opportunity, etc. — IF the engagement has added custom fields, validation rules, triggers, or flows referencing them. Detect by:
  - `objects/<Object>/fields/*__c.field-meta.xml` exists (custom fields), OR
  - `objects/<Object>/validationRules/` non-empty, OR
  - `triggers/*.trigger` has `on <Object>` clause, OR
  - `flows/*.flow-meta.xml` references the object as start type.
- **Exclude**: standard objects with no customization (skip even if the directory exists).
- **Exclude**: managed-package objects (namespace prefix in the API name).

### Significant Flows

- All `flows/*.flow-meta.xml` files where `<status>Active</status>`.
- Exclude inactive / obsolete Flows (status != Active).
- Exclude managed-package Flows.

### Significant integrations

External-system surfaces:
- Connected Apps (`connectedApps/*.connectedApp-meta.xml`)
- Named Credentials (`namedCredentials/*.namedCredential-meta.xml`)
- External Services (`externalServiceRegistrations/`)
- Platform Event definitions (`objects/*__e/`)
- Apex classes that contain `HttpRequest` or `Http.send` (outbound callouts) — group by the endpoint they hit (parse the URL)
- Apex REST classes (`@RestResource`) — group as inbound integrations

### Significant Apex classes (for cross-reference)

Used by the per-category nodes to know which classes touch which objects. List every `.cls` file under `classes/` that:
- Is not test-only (`@IsTest` class-level annotation is excluded)
- Is not a managed-package class
- Has more than ~20 lines of actual logic (filter out stubs)

## Task

1. **Inventory each category** per the rules above. Use `find`, `ls`, `wc -l` via Bash to count efficiently. Read individual files only when classification needs the content (e.g., to check whether an Apex class is `@IsTest`).

2. **Cross-reference:** for each significant object, list the Apex classes / triggers / Flows that touch it (grep on the API name within force-app/).

3. **Identify probable feature clusters** — groups of (object + Apex + Flow + integration) that together implement one business feature. Heuristics:
   - Apex classes whose names start with the same prefix as a custom object (e.g., `Renewal__c` + `RenewalCalculator.cls` + `RenewalTrigger.trigger` → renewal feature).
   - Triggers + handler classes that fire on the same object.
   - Flows + Apex classes referenced from those Flows.
   You're sketching feature boundaries; the synthesize node refines them.

4. **Estimate total tokens** the parallel document-* agents will spend, using ADR-0011's heuristic:
   - Per object: ~$0.225 (opus[1m])
   - Per flow: ~$0.15
   - Per integration: ~$0.20

## Output

Structured JSON for downstream nodes:

```json
{
  "objects": [
    {
      "api_name": "Renewal__c",
      "is_custom": true,
      "file_path": "force-app/main/default/objects/Renewal__c/",
      "field_count": 12,
      "trigger_files": ["RenewalTrigger.trigger"],
      "apex_classes_referencing": ["RenewalCalculator", "RenewalTriggerHandler", "RenewalBillingJob"],
      "flows_referencing": ["Renewal_Auto_Create"]
    }
  ],
  "flows": [
    { "api_name": "Renewal_Auto_Create", "type": "RecordTriggered", "object": "Opportunity", "file_path": "force-app/main/default/flows/Renewal_Auto_Create.flow-meta.xml" }
  ],
  "integrations": [
    { "system_name": "Stripe", "kind": "callout+webhook", "endpoint": "https://api.stripe.com/v1/...", "apex_classes": ["StripeBillingService", "StripeWebhookController"] }
  ],
  "probable_features": [
    { "slug": "renewal-pipeline", "involves_objects": ["Renewal__c", "Opportunity"], "involves_integrations": ["Stripe"] }
  ],
  "cost_estimate": {
    "objects_cost_usd": 2.25,
    "flows_cost_usd": 0.15,
    "integrations_cost_usd": 0.20,
    "synthesis_cost_usd": 0.50,
    "total_estimated_usd": 3.10
  },
  "skipped": [
    { "category": "object", "name": "User", "reason": "standard object, no customization detected" }
  ]
}
```

If a category is entirely empty (e.g., the engagement has no Flows), output an empty array for that category — don't fail.
