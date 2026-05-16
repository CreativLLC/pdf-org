---
title: Permission Sets
audience: public
last_updated: 2026-05-15
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - ../README.md
  - ../sharing-model.md
  - ../permission-set-groups.md
---

# Permission Sets — Meditrina

Permission sets are additive grants layered on top of a user's base profile. This index lists every permission set in `force-app/main/default/permissionsets/`; per-PS detail is in the linked file.

## Permission set inventory

| Permission Set | License | PSG membership | Doc |
|---|---|---|---|
| `MFA_Required` | _None_ | _None_ | [`MFA_Required.md`](./MFA_Required.md) |
| `Manage_Billing` | _None_ | _None_ | [`Manage_Billing.md`](./Manage_Billing.md) |
| `PdfGeneratorAdmin` | _None_ | _None_ | [`PdfGeneratorAdmin.md`](./PdfGeneratorAdmin.md) |
| `System_Admin_Extra_Perms` | _None_ | _None_ | [`System_Admin_Extra_Perms.md`](./System_Admin_Extra_Perms.md) |
| `TEST` | _None_ | _None_ | [`TEST.md`](./TEST.md) |
| `View_Invoices` | Customer Portal Manager Custom | _None_ | [`View_Invoices.md`](./View_Invoices.md) |
| `sfdcInternalInt__sfdc_nc_constraints_engine_deploy` | Cloud Integration User | _None_ | [`sfdcInternalInt__sfdc_nc_constraints_engine_deploy.md`](./sfdcInternalInt__sfdc_nc_constraints_engine_deploy.md) |

## Permission Set Groups

Two PSGs exist in source — both `force__` namespace (Salesforce-managed packages); see [`../permission-set-groups.md`](../permission-set-groups.md) for the section-level summary.
