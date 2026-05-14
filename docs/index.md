---
title: Meditrina — Engagement Documentation Index
audience: public
last_updated: 2026-05-14
last_updated_by: archon-discover
related_tickets: []
related_docs: [README.md]
---

# Meditrina — Engagement Documentation Index

> **For AI agents:** load this file first, then load ONLY the docs in the "Quick paths" section relevant to your current task. Do not load the entire `docs/` tree by default.

## Quick paths

### Working on Apex on a specific object

Load: `docs/objects/<ObjectAPIName>.md` + the Apex classes referenced therein.

### Adding or modifying a feature

Load: `docs/features/<closest-feature>.md` + the object docs that feature references.

### Touching the PDF generator

Load: [`docs/features/pdf-template-builder.md`](./features/pdf-template-builder.md) + [`Document_Template__c`](./objects/Document_Template__c.md), [`Template_Version__c`](./objects/Template_Version__c.md), [`Template_Mapping__c`](./objects/Template_Mapping__c.md).

### Touching timesheets, invoicing, or contracts

Load: [`docs/features/timesheet-billing.md`](./features/timesheet-billing.md) + [`Time_Sheet__c`](./objects/Time_Sheet__c.md), [`Invoice__c`](./objects/Invoice__c.md), [`Contact_Role__c`](./objects/Contact_Role__c.md).

### Touching project staffing / resource planning

Load: [`docs/features/project-resourcing.md`](./features/project-resourcing.md) + [`Project__c`](./objects/Project__c.md), [`Project_Allocation__c`](./objects/Project_Allocation__c.md), [`Contact_Role__c`](./objects/Contact_Role__c.md).

### Designing a new architectural pattern

Load: any relevant `docs/decisions/*.md` ADRs.

### Onboarding to the engagement (humans)

Read: this page → the Feature index below → drill into specific feature docs.

---

## Object index

Canonical reference layer (one doc per significant object). 17 objects documented.

### PDF generator subsystem

| Object | Description |
|---|---|
| [`Document_Template__c`](./objects/Document_Template__c.md) | Root template for a class of generated PDF documents, bound to a single target SObject. Parent of versions and mapping rules. |
| [`Template_Version__c`](./objects/Template_Version__c.md) | A revision of a `Document_Template__c`; holds the template body JSON (with 128KB spillover to a linked `ContentVersion`). |
| [`Template_Mapping__c`](./objects/Template_Mapping__c.md) | Rule that picks which `Template_Version__c` renders for a given source record by record type / field match, ordered by priority. |
| [`Form__c`](./objects/Form__c.md) | Demo object — a quality form used to test the PDF generator against realistic shaped data. No production meaning. |
| [`Signature__c`](./objects/Signature__c.md) | Demo child of `Form__c`; a signature slot. Image lives in attached Files, discriminated by signature type. |
| [`ContentVersion`](./objects/ContentVersion.md) | Standard Files object; one custom field `Source_Template_Version__c` enables overwrite-on-regenerate of generated PDFs. |

### PSA core (time-and-billing, project resourcing, sales)

| Object | Description |
|---|---|
| [`Account`](./objects/Account.md) | Customer entity. Two triggers maintain an audit timestamp and re-project custom-named staging fields onto standard relationships. |
| [`Contact`](./objects/Contact.md) | Standard Contact with one trigger that re-projects a `Lead_Id_Passable__c` staging field onto the standard-named lookup. |
| [`Contact_Role__c`](./objects/Contact_Role__c.md) | Junction linking Contact to Opportunity / Project / Lead in distinct role types. Project Assignments drive the allocation generator. |
| [`Opportunity`](./objects/Opportunity.md) | Sales record. Computes quote-validity date and auto-creates referral commission roles from the originating lead. |
| [`Project__c`](./objects/Project__c.md) | Delivery object owning a customer, opportunity, weekly hour targets, payment terms, resources, and invoices. |
| [`Project_Allocation__c`](./objects/Project_Allocation__c.md) | One week of planned hours for a Project Assignment. Auto-generated weekly (Monday-start) from the role's start/end window. |
| [`Time_Sheet__c`](./objects/Time_Sheet__c.md) | Worked-time entry imported from Jira/Tempo. Hours roll up to Invoice and to the related Contract's used-hours balance. |
| [`Invoice__c`](./objects/Invoice__c.md) | Billing object aggregating T&M for a project. Two modes (standard / deposit) with applied-credit draw-down. |
| [`Transaction__c`](./objects/Transaction__c.md) | Money movement: instance, recurring schedule, or budget. Budgets and recurring sources project forward into instance rows. |
| [`Product2`](./objects/Product2.md) | Standard Product. Trigger keeps a Standard Pricebook entry in sync with `Base_Price__c`. |
| [`Requirement_Use_Case__c`](./objects/Requirement_Use_Case__c.md) | Use case under a requirement. **Trigger is entirely commented out** — intended rollups are inert. |

## Feature index

Derived business-facing layer (one doc per cross-cutting feature). 6 features documented.

| Feature | Description |
|---|---|
| [`pdf-template-builder`](./features/pdf-template-builder.md) | Admins design reusable PDF document templates against any Salesforce object; end users generate a merged PDF from any matching record with one click. |
| [`timesheet-billing`](./features/timesheet-billing.md) | Worked hours imported from Jira/Tempo are auto-matched to resource + project, summed into a printable invoice, and rolled up to the related support contract's used-hours balance. |
| [`project-resourcing`](./features/project-resourcing.md) | Resources staffed onto a project auto-generate weekly hour allocations across the staffing window; a planner UI shows who is over- or under-allocated week by week. |
| [`opportunity-pipeline`](./features/opportunity-pipeline.md) | Opportunities carry a quote-validity window that auto-stamps an expiration date; opportunities sourced from a referral-bearing lead automatically get a 3% referral commission role. |
| [`account-management`](./features/account-management.md) | Customer Accounts carry an audit timestamp on every save and lift custom-named staging fields onto standard parent-account and lead relationships. |
| [`transactions-and-forecast`](./features/transactions-and-forecast.md) | Recurring or budgeted transactions project forward into individual money-movement instances; an account-forecast page shows the running balance across a custom financial account. |

## Flow index

*No declarative Flows are present in this engagement's source.*

## Integration index

*No external integrations (named credentials, connected apps, REST classes, or HTTP callouts) are present in this engagement's source.*

## Architectural decisions

ADRs that record long-lived rationale for this engagement.

See [`decisions/`](./decisions/) for the full list. *(No engagement-specific ADRs authored yet; the harness ADRs live in `.archon/decisions/`.)*

---

## How this index stays current

- Every `/sf` run that creates a new object / feature / flow / integration doc adds an entry to the corresponding section above ([ADR-0010 §3](../../.archon/decisions/0010-engagement-documentation-model.md)).
- Descriptions on existing entries are updated when a `/sf` run materially changes what the underlying doc describes.
- If you see a stale or missing entry, edit this file directly — it's not generated.
