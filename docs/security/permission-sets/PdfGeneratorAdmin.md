---
title: "PdfGeneratorAdmin"
audience: public
last_updated: 2026-05-16
last_updated_by: drew.smith@openwacca.com
related_tickets:
  - GRIM-51
related_docs:
  - README.md
  - ../sharing-model.md
  - ../../objects/Document_Template__c.md
---

# `PdfGeneratorAdmin`

## Identity

| | |
|---|---|
| **API name** | `PdfGeneratorAdmin` |
| **Label** | PDF Generator Admin |
| **License** | _None (does not require a permission set license)._ |
| **PSG membership** | _Not a member of any Permission Set Group._ |
| **Origin** | Engagement-authored |
| **Description** | Full access to PDF Generator objects, fields, tabs, app, and Apex services. |
| **Activation required** | No |

## Purpose

Authoring + administration of the PDF template-builder feature. Grants CRUD on `Document_Template__c`, `Template_Version__c`, `Template_Mapping__c`, plus tab/page/class access for the builder LWC + render Visualforce. _(inferred)_

## Object permissions added

| Object | Read | Create | Edit | Delete | View All | Modify All | Notes |
|---|---|---|---|---|---|---|---|
| `Document_Template__c` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | engagement custom object |
| `Form__c` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | engagement custom object |
| `Signature__c` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | engagement custom object |
| `Template_Mapping__c` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | engagement custom object |
| `Template_Version__c` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | engagement custom object |

## Field-level security added

| Object | Field | Read | Edit |
|---|---|---|---|
| `Document_Template__c` | `Active__c` | ✓ | ✓ |
| `Document_Template__c` | `Default_Version__c` | ✓ | ✓ |
| `Document_Template__c` | `Description__c` | ✓ | ✓ |
| `Document_Template__c` | `File_Naming_Pattern__c` | ✓ | ✓ |
| `Document_Template__c` | `Overwrite_Existing_File__c` | ✓ | ✓ |
| `Document_Template__c` | `Reviewer__c` | ✓ | ✓ |
| `Form__c` | `Comments__c` | ✓ | ✓ |
| `Form__c` | `Patient_Name__c` | ✓ | ✓ |
| `Form__c` | `Procedure_Date__c` | ✓ | ✓ |
| `Form__c` | `Revision_Number__c` | ✓ | ✓ |
| `Form__c` | `Status__c` | ✓ | ✓ |
| `Signature__c` | `Signed_At__c` | ✓ | ✓ |
| `Signature__c` | `Signed_By__c` | ✓ | ✓ |
| `Template_Mapping__c` | `Match_Field_Api_Name__c` | ✓ | ✓ |
| `Template_Mapping__c` | `Match_Value__c` | ✓ | ✓ |
| `Template_Mapping__c` | `Record_Type_Developer_Name__c` | ✓ | ✓ |
| `Template_Version__c` | `Definition_Json__c` | ✓ | ✓ |
| `Template_Version__c` | `Revision_Number__c` | ✓ | ✓ |
| `Template_Version__c` | `Sample_Record_Id__c` | ✓ | ✓ |

## App access added

- `PDF_Generator`

## Tab settings overrides

| Tab | Setting |
|---|---|
| `Document_Template__c` | **Visible** |
| `Form__c` | **Visible** |
| `Template_Mapping__c` | **Visible** |
| `Template_Version__c` | **Visible** |

## System permissions added

_No system permissions added._

## Custom Permissions granted

_No Custom Permissions granted._

## Apex class access added

- `DocumentRenderController`
- `PdfGeneratorController`
- `PdfTemplateService`
- `TemplateBuilderController`

## Visualforce page access added

- `DocumentRender`

## Connected App access added

_No Connected App access added._

## Typical assignment pattern

_Assignment pattern not documented; check Setup or the engagement's onboarding runbook._

## Related decisions

_None._
