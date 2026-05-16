---
title: Custom Permissions
audience: public
last_updated: 2026-05-15
last_updated_by: archon-discover
related_tickets: []
related_docs:
  - README.md
  - sharing-model.md
---

# Custom Permissions

Custom Permissions are feature-flag-style entitlements that Apex checks via `FeatureManagement.checkPermission(...)` or that Flow checks via the `$Permission` global. They sit alongside object-/field-level permissions on profiles and permission sets but do not themselves grant data access.

_None — this engagement does not use Custom Permissions._

No `force-app/main/default/customPermissions/` directory exists in source, and no `FeatureManagement.checkPermission` calls were found in `force-app/main/default/classes/`.
