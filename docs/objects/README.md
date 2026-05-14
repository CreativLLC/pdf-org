# Objects

One file per significant standard-with-customizations or custom object in the org. Out-of-the-box standard objects with no engagement-specific customizations are *not* documented here — Salesforce documents those.

## When to add an object doc

Add a doc when:
- A custom object is created.
- A standard object is materially customized — new required fields, custom validation rules, custom triggers, custom Apex consumers, custom integrations.
- A junction object or external object is added.
- A custom metadata type is added that drives configuration.

Update the existing doc when:
- A field is added, removed, or renamed.
- A trigger or Apex class touching the object changes.
- The sharing posture changes.
- A new validation rule is added.

## Template

The object doc template lives at [`harness/docs-templates/object-doc.md`](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/docs-templates/object-doc.md). Required sections: Purpose, Type and origin, Key fields, Relationships, Sharing model, Validation rules, Triggers and Apex, Flows, Integrations, Test coverage, Constraints and gotchas, History.

## Index

| Object | Type | Doc |
|---|---|---|
| `Renewal__c` | Custom | [`Renewal__c.md`](./Renewal__c.md) |

*(Phase 1.5 will add: `Account` (with Acme customizations), `Contract` (with Acme customizations), `Renewal_Line_Item__c`, `Renewal_Status__mdt`.)*
