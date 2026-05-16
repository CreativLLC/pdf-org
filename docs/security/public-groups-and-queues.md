---
title: Public Groups and Queues
audience: public
last_updated: 2026-05-15
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - README.md
  - sharing-model.md
---

# Public Groups and Queues

## Public Groups

| Group | Label | Includes | Used in |
|---|---|---|---|
| `Internal_Users` | Internal Users | `doesIncludeBosses=true` (members not enumerated in source — managed in Setup → Public Groups) | Not referenced by any `force-app/main/default/sharingRules/*.sharingRules-meta.xml`. The `Account` `Share_with_Internal_Users` ownership rule uses the SF-built-in `<allInternalUsers/>` token rather than this group. |

## Queues

| Queue | Label | SObject(s) | Notes |
|---|---|---|---|
| `USLeads` | US Leads | `Lead` | `doesIncludeBosses=true`; `doesSendEmailToMembers=false`. Member listed in source: `charles.howard@openwacca.com`. |
| `InternationalLeads` | International Leads | `Lead` | `doesIncludeBosses=true`; `doesSendEmailToMembers=false`. No queue members declared in source (managed in Setup). |
