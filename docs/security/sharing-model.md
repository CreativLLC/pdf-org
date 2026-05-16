---
title: Sharing model
audience: public
last_updated: 2026-05-15
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - README.md
  - custom-permissions.md
  - public-groups-and-queues.md
  - apex-sharing.md
  - permission-set-groups.md
---

# Sharing model

## Org-wide defaults (OWD)

Every object's default record visibility, before sharing rules / Apex sharing / role hierarchy.

| Object | Internal OWD | External OWD | Grant Access Using Hierarchies |
|---|---|---|---|
| `Document_Template__c` | Public Read/Write | Public Read/Write | Default (Yes) |
| `Form__c` | Public Read/Write | Public Read/Write | Default (Yes) |
| `Signature__c` | Controlled by Parent (`Form__c`) | — | n/a |
| `Template_Mapping__c` | Controlled by Parent (`Document_Template__c`) | — | n/a |
| `Template_Version__c` | Controlled by Parent (`Document_Template__c`) | — | n/a |

> Standard objects (`Account`, `Contact`, `Opportunity`, `Lead`, etc.) and engagement custom objects whose `<Object>.object-meta.xml` is not retrieved into source (e.g., `Acct__c`, `Contact_Role__c`, `Project__c`, `Project_Allocation__c`, `Invoice__c`, `Time_Sheet__c`, `Transaction__c`, `Requirement_Use_Case__c`) have OWD set in Setup → Sharing Settings; those values are not visible from `force-app/main/default/`. The full per-object view is in each object's [`../objects/<Object>.md`](../objects/) "Sharing model" section, which records what is in source and notes where Setup is the authority.

## Sharing rules

Configured rules that grant access beyond OWD. Listed per object that has any.

### `Account`

| Rule name | Type | Criterion | Shared with | Access level |
|---|---|---|---|---|
| `Share_with_Internal_Users` | Ownership-based | Records owned by all internal users | All Internal Users | Edit (Account, Case, Contact, Opportunity) |

This rule effectively gives every internal user Edit access to every Account-owned record (and the implicitly-shared child Case / Contact / Opportunity rows) regardless of the role hierarchy. With a Public Read/Write or even Private OWD on Account, this is a load-bearing rule for cross-team visibility.

> All other `force-app/main/default/sharingRules/*.sharingRules-meta.xml` files were retrieved as empty stubs (no `<sharingCriteriaRules>` / `<sharingOwnerRules>` / `<sharingTerritoryRules>` / `<sharingGuestRules>` content) for objects that have no engagement-defined sharing rules in the org.

## Apex (programmatic) sharing

_None — all sharing is declarative._ No `__Share` token usage was found in `force-app/main/default/classes/`.

## Implicit sharing notes

- **Account → Contact / Opportunity / Case**: Read access to an Account grants Read to its child Contacts, Opportunities, and Cases per standard Salesforce implicit sharing. The `Share_with_Internal_Users` ownership-based rule above explicitly raises that to Edit for all internal users.
- **Master-Detail `Controlled by Parent`** chains in this engagement:
  - [`Signature__c`](../objects/Signature__c.md) → [`Form__c`](../objects/Form__c.md)
  - [`Template_Mapping__c`](../objects/Template_Mapping__c.md) → [`Document_Template__c`](../objects/Document_Template__c.md)
  - [`Template_Version__c`](../objects/Template_Version__c.md) → [`Document_Template__c`](../objects/Document_Template__c.md)

  In each, access to the parent fully determines access to the child.

## Restriction Rules

_None._ No `force-app/main/default/restrictionRules/` directory exists in source.

## Role hierarchy notes

_Engagement-specific role hierarchy details are not visible from source metadata; consult Setup → Roles for the full tree._

The `Share_with_Internal_Users` rule plus the Public Read/Write OWD on the PDF-generator objects suggests this org operates with broadly-permissive internal access; the role hierarchy likely matters less for record visibility here than profile/permission-set entitlements (see [`profiles/`](./profiles/) and [`permission-sets/`](./permission-sets/)).

## Custom Permissions usage map

_None — see [`custom-permissions.md`](./custom-permissions.md) for context._

## Public Groups and Queues

See [`public-groups-and-queues.md`](./public-groups-and-queues.md) for full enumeration. Summary:

- **Groups used in sharing rules**: none. The single Public Group `Internal Users` is not referenced in `Account.sharingRules-meta.xml` (which uses the SF-built-in `<allInternalUsers/>` token instead).
- **Queues**: `US Leads` and `International Leads`, both routing `Lead`.

## Permission Set Groups

Two PSGs are present (both in the `force__` namespace, i.e., Salesforce-managed packages — Sales Workspace and Scale Center). See [`permission-set-groups.md`](./permission-set-groups.md).

## Why this posture (engagement narrative)

_TODO: engineer to author. The auto-generator captured the facts above but cannot infer the WHY. Add a 2–4 paragraph explanation of the business reasoning behind the OWD choices (Public Read/Write on PDF-generator objects, Controlled-by-Parent on the version/mapping/signature chains), the existence of the `Share_with_Internal_Users` rule, and any deferred or rejected alternatives. Link to relevant ADRs in [`../decisions/`](../decisions/)._

## Related decisions

_None._
