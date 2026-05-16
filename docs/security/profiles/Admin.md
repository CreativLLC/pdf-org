---
title: "Admin"
audience: public
last_updated: 2026-05-15
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - README.md
  - ../sharing-model.md
---

# `Admin`

## Identity

| | |
|---|---|
| **API name** | `Admin` |
| **Label** | `Admin` |
| **User license** | Salesforce |
| **License count** | _Not visible from source._ |
| **Origin** | Stock with customizations |
| **Description** | _Not set._ |

## Persona

Full system administrator. Bears the ModifyAllData / ViewAllData / CustomizeApplication triad and broad object access; the catch-all admin role. _(inferred from naming + system perms)_

## Object permissions

_No object permissions declared in source — uses minimum-access defaults._

## Field-level security overrides

_No FLS overrides — uses default field visibility._

## App access

_Stock Salesforce app only._

## Tab settings

_All tabs use default visibility._

## System permissions of note

- **`ApiEnabled`** — Enabled.
- **`AuthorApex`** — Enabled.
- **`ConvertLeads`** — Enabled.
- **`CustomizeApplication`** — Enabled.
- **`DataExport`** — Enabled.
- **`DelegatedTwoFactor`** — Enabled.
- **`ExportReport`** — Enabled.
- **`ManageDataIntegrations`** — Enabled.
- **`ManageInternalUsers`** — Enabled.
- **`ManagePasswordPolicies`** — Enabled.
- **`ManageProfilesPermissionsets`** — Enabled.
- **`ManageRoles`** — Enabled.
- **`ManageSandboxes`** — Enabled.
- **`ManageUsers`** — Enabled.
- **`ModifyAllData`** — Enabled.
- **`NewReportBuilder`** — Enabled.
- **`ResetPasswords`** — Enabled.
- **`RunReports`** — Enabled.
- **`ScheduleReports`** — Enabled.
- **`ViewAllData`** — Enabled.
- **`ViewRoles`** — Enabled.
- **`ViewSetup`** — Enabled.

## Apex class access

_No engagement-specific Apex class access._

## Visualforce page access

_No engagement-specific VF page access._

## Connected App access

_No engagement-specific Connected App access._

## Typically assigned with

_None known; permission sets are assigned ad-hoc._

## Related decisions

_None._
