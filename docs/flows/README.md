# Flows

One file per significant Flow. Trivial validation rules and small no-side-effect Flows are not documented here — they're documented inline in the object doc's Validation Rules table.

## When to add a Flow doc

Add a doc when:
- A new Flow is created with side effects (creates/updates other records, publishes events, sends notifications, makes callouts).
- A Flow spans multiple objects.
- A Flow implements business logic worth understanding for future engineers.

Skip a doc when:
- The Flow is a single-object validation that the object's doc already explains.
- The Flow is a one-shot data correction (use anonymous Apex instead).

## Template

The flow doc template lives at [`harness/docs-templates/flow-doc.md`](https://github.com/CreativLLC/archon-salesforce-jira/blob/main/docs-templates/flow-doc.md). Required sections: Purpose, Type and trigger, What it does, Side effects, Error handling, Dependencies, Performance and limits, Testing, Ownership and on-call, History.

## Index

| Flow | Type | Doc |
|---|---|---|
| `Renewal_Auto_Create` | Schedule-Triggered | [`Renewal_Auto_Create.md`](./Renewal_Auto_Create.md) |

*(Phase 1.5 will add: `Renewal_Reminder_Scheduled`, `Account_Owner_Reassign`, `Opportunity_Stage_Notify`.)*
