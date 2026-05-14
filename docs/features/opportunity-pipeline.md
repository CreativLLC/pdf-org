---
title: Opportunity Pipeline
audience: public
last_updated: 2026-05-14
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - ../objects/Opportunity.md
  - ../objects/Contact_Role__c.md
  - ../objects/Project__c.md
---

# `Opportunity Pipeline`

> Opportunities carry a configurable quote-validity window that auto-stamps an expiration date, and any opportunity sourced from a referral-bearing lead automatically gets a 3 percent referral commission role created.

## Overview

The sales record in this engagement is the standard [`Opportunity`](../objects/Opportunity.md) with two engagement-specific behaviors: (1) a `Quote_Valid_Until__c` date that is recomputed on every save from the picklist `Quote_Valid_For__c` (`30 Days`, `60 Days`, `90 Days`, `6 Months`, `1 Year`, default 30); and (2) on insert, when the opportunity is bound to a Lead carrying a `Referral_Contact__c`, a `Referral`-record-type [`Contact_Role__c`](../objects/Contact_Role__c.md) is auto-created with a 3 percent commission rate and an `Active` status. Opportunities are also the upstream owner of Contact Roles that later carry forward to [`Project__c`](../objects/Project__c.md) on project insert (see the [Project Resourcing](project-resourcing.md) feature).

## How it works

1. **Sales rep creates the opportunity.** A staging field `Lead_Id_Passable__c` (used by inbound flows/imports that can only populate custom-named fields) is lifted onto the standard `Lead__c` lookup on before-insert.
2. **Quote validity computed.** Before-save logic computes `Quote_Valid_Until__c = today + delta`, where the delta is derived from `Quote_Valid_For__c`. Anything outside the recognized picklist values falls through to 30 days.
3. **Referral commission auto-created.** On after-insert, if the bound Lead has a `Referral_Contact__c`, a `Contact_Role__c` is inserted with `RecordTypeId = Referral`, `Fee_Commission_Type__c = 'Percentage'`, `Fee_Commission_Rate__c = 3.00`, `Status__c = 'Active'`, and `Title__c = 'Referral Source'`.
4. **Sales staffs the deal.** Sales-team and other-participant Contact Roles are added manually as the opportunity progresses.
5. **Handoff at project creation.** When a `Project__c` is later inserted referencing this opportunity, the project's after-insert handler bulk-updates the opportunity's active Contact Roles to also set `Project__c` (the original `Opportunity__c` lookup is preserved). See [Project Resourcing](project-resourcing.md).

## Acceptance signals

- A new opportunity created today with `Quote_Valid_For__c = '90 Days'` shows `Quote_Valid_Until__c` = today + 90.
- An opportunity inserted with a `Lead__c` whose `Referral_Contact__c` is set produces exactly one Referral-record-type `Contact_Role__c` linked back to the opportunity with rate `3.00` and status `Active`.
- A project created from the opportunity shows the opportunity's active Contact Roles re-parented onto the project's related list.

## Known limitations

- **Two triggers on Opportunity overlap.** `OpportunityTrigger` and `OpportunityBeforeUpsert` both compute `Quote_Valid_Until__c` on before-insert. They write the same value today, so there is no conflict, but the duplication means a change to one branch will diverge from the other if not mirrored.
- **`6 Months` and `1 Year` branches are duplicated across both triggers.** Editing one without the other will produce inconsistent results once they diverge.
- **Referral auto-creation runs once on insert only.** Updating `Lead__c` (or its `Referral_Contact__c`) post-insert does not create a new Referral role.
- **No formal contract object behavior.** `Logic_Contract.cls` despite its name does not act on opportunities — it rolls timesheet hours into the standard `Contract` object (see [Timesheet Billing](timesheet-billing.md)).
- **The `Lead_Id_Passable__c` staging pattern is repeated** on `Account` and `Contact` as well; it exists because inbound flows/imports can only write custom-named fields, and the triggers lift them onto the standard relationships.

## Related tickets

None recorded at the engagement level for this baseline behavior.
