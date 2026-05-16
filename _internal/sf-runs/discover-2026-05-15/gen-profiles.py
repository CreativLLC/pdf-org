import os, re, xml.etree.ElementTree as ET, pathlib

os.chdir(r"c:\Users\m0gul\Documents\meditrinaPOCsandbox\archonJiraDemoOrg")

NS = "{http://soap.sforce.com/2006/04/metadata}"

def parse_profile(path):
    tree = ET.parse(path)
    root = tree.getroot()
    name = path.stem.replace(".profile-meta", "")
    license = (root.findtext(f"{NS}userLicense") or "Salesforce").strip()
    custom = (root.findtext(f"{NS}custom") or "false").strip() == "true"
    desc = (root.findtext(f"{NS}description") or "").strip() or None

    obj_perms = []
    for op in root.findall(f"{NS}objectPermissions"):
        obj = op.findtext(f"{NS}object") or ""
        flags = {k: (op.findtext(f"{NS}{k}") or "false") == "true"
                 for k in ("allowRead","allowCreate","allowEdit","allowDelete","viewAllRecords","modifyAllRecords")}
        if any(flags.values()):
            obj_perms.append((obj, flags))
    obj_perms.sort()

    fls_overrides = []
    for fp in root.findall(f"{NS}fieldPermissions"):
        field = fp.findtext(f"{NS}field") or ""
        readable = (fp.findtext(f"{NS}readable") or "false") == "true"
        editable = (fp.findtext(f"{NS}editable") or "false") == "true"
        if not readable or not editable:
            obj_part, _, field_part = field.partition(".")
            fls_overrides.append((obj_part, field_part, readable, editable))
    fls_overrides.sort()

    tab_overrides = []
    for tv in root.findall(f"{NS}tabVisibilities"):
        tab = tv.findtext(f"{NS}tab") or ""
        vis = tv.findtext(f"{NS}visibility") or ""
        if vis in ("Hidden", "DefaultOff", "DefaultOn"):
            tab_overrides.append((tab, vis))
    tab_overrides.sort()

    NOTABLE = {
        "ApiEnabled","AuthorApex","CustomizeApplication","ManageUsers","ManageProfilesPermissionsets",
        "ModifyAllData","ViewAllData","ManageDataIntegrations","BulkApiHardDelete","ExportReport",
        "ManageReports","RunReports","ScheduleReports","ResetPasswords","ViewSetup","ViewRoles",
        "ManagePasswordPolicies","ManageRoles","ManageSandboxes","DataExport","ManageSession",
        "ManageInternalUsers","NewReportBuilder","TwoFactorApi","DelegatedTwoFactor","ConvertLeads",
        "ApiUserOnly","SendExternalEmailAvailable",
    }
    sys_perms_enabled = []
    for up in root.findall(f"{NS}userPermissions"):
        n = up.findtext(f"{NS}name") or ""
        en = (up.findtext(f"{NS}enabled") or "false") == "true"
        if en and n in NOTABLE:
            sys_perms_enabled.append(n)
    sys_perms_enabled.sort()

    classes = sorted([
        ca.findtext(f"{NS}apexClass")
        for ca in root.findall(f"{NS}classAccesses")
        if (ca.findtext(f"{NS}enabled") or "false") == "true"
    ])
    pages = sorted([
        pa.findtext(f"{NS}apexPage")
        for pa in root.findall(f"{NS}pageAccesses")
        if (pa.findtext(f"{NS}enabled") or "false") == "true"
    ])
    conn_apps = sorted([
        ca.findtext(f"{NS}connectedApp")
        for ca in root.findall(f"{NS}connectedAppAccesses")
        if (ca.findtext(f"{NS}enabled") or "false") == "true"
    ])

    apps_visible = []
    default_app = None
    for av in root.findall(f"{NS}applicationVisibilities"):
        a = av.findtext(f"{NS}application") or ""
        if (av.findtext(f"{NS}visible") or "false") == "true":
            apps_visible.append(a)
        if (av.findtext(f"{NS}default") or "false") == "true":
            default_app = a
    apps_visible.sort()

    cps = sorted([
        cp.findtext(f"{NS}name")
        for cp in root.findall(f"{NS}customPermissions")
        if (cp.findtext(f"{NS}enabled") or "false") == "true"
    ])

    return {
        "name": name, "license": license, "custom": custom, "desc": desc,
        "obj_perms": obj_perms, "fls_overrides": fls_overrides, "tab_overrides": tab_overrides,
        "sys_perms": sys_perms_enabled, "classes": classes, "pages": pages, "conn_apps": conn_apps,
        "apps_visible": apps_visible, "default_app": default_app, "custom_perms": cps,
    }


PERSONA = {
    "Admin": "Full system administrator. Bears the ModifyAllData / ViewAllData / CustomizeApplication triad and broad object access; the catch-all admin role. _(inferred from naming + system perms)_",
    "System Admin Full": "Engagement-specific admin variant alongside the stock `Admin` profile. Likely cloned to fence off changes to a specific named admin team. _(inferred)_",
    "Sales Manager": "Sales leadership — broad CRM access (`Account`, `Contact`, `Opportunity`, `Lead`) plus team-level reporting. _(inferred)_",
    "Marketing Manager": "Marketing operations lead — CRM read/write plus campaign management. _(inferred)_",
    "MarketingProfile": "Day-to-day marketing user — CRM read/write on campaigns, leads, contacts. Likely the rank-and-file marketing seat. _(inferred from naming)_",
    "Standard": "Stock Salesforce Standard User profile. Baseline CRM access; commonly the cloning source for engagement-specific variants. _(stock Salesforce)_",
    "SolutionManager": "Stock Salesforce Solution Manager profile (manages the legacy Solutions feature). _(stock Salesforce)_",
    "ContractManager": "Stock Salesforce Contract Manager profile (full CRUD on Contracts; reads Accounts/Opportunities). _(stock Salesforce)_",
    "Read Only": "Stock Salesforce Read Only profile. Used for audit / observer accounts. _(stock Salesforce)_",
    "Analytics Cloud Integration User": "Stock CRM Analytics integration user — service account for CRM Analytics syncing. _(stock Salesforce)_",
    "Sales Insights Integration User": "Stock Sales Insights integration user — service account. _(stock Salesforce)_",
    "Chatter Moderator User": "Stock Chatter moderator profile. _(stock Salesforce)_",
    "Anypoint Integration": "Stock MuleSoft Anypoint integration profile — service account for Anypoint connections. _(stock Salesforce)_",
    "Identity User": "Stock Identity-only user (SSO without CRM access). _(stock Salesforce)_",
    "Chatter Free User": "Stock Chatter Free profile (no CRM data). _(stock Salesforce)_",
    "Analytics Cloud Security User": "Stock CRM Analytics security user — sharing-resolution service account. _(stock Salesforce)_",
    "Customer Portal User": "Stock legacy Customer Portal user. _(stock Salesforce; Customer Portal is deprecated)_",
    "Contractor Portal User": "Stock Contractor / Partner Community user. _(stock Salesforce)_",
    "Customer Portal Manager Custom": "Customer Portal Manager profile, retrieved with customizations applied in this org. _(stock-customized)_",
    "Chatter External User": "Stock Chatter External user (collaborate with external Chatter members). _(stock Salesforce)_",
    "Guest License User": "Stock Guest user profile (unauthenticated site/community visitors). _(stock Salesforce)_",
    "Osibtys Profile": "Engagement-named profile of unclear purpose — name suggests an account-specific identifier. _(verify with engagement)_",
    "Minimum Access - Salesforce": "Stock minimum-access Salesforce profile (newer SF baseline; CRM access is grant-by-permission-set rather than via the profile itself). _(stock Salesforce)_",
    "Salesforce API Only System Integrations": "Stock API-only integration profile — service account that cannot log in via UI. _(stock Salesforce)_",
    "Minimum Access - API Only Integrations": "Stock minimum-access API-only integration profile. _(stock Salesforce)_",
}

CUSTOM_OBJECTS = {
    "Document_Template__c","Form__c","Signature__c","Template_Mapping__c","Template_Version__c",
    "Contact_Role__c","Project__c","Project_Allocation__c","Invoice__c","Time_Sheet__c",
    "Transaction__c","Requirement_Use_Case__c","Acct__c",
}


def fmt_check(b):
    return "✓" if b else "—"


def render_profile(p):
    name = p["name"]
    persona = PERSONA.get(name, "_Inferred persona unavailable from source — verify with engagement._")
    out = []
    out.append("---")
    out.append(f'title: "{name}"')
    out.append("audience: public")
    out.append("last_updated: 2026-05-15")
    out.append("last_updated_by: archon-discover")
    out.append("related_tickets: []")
    out.append("related_docs:")
    out.append("  - README.md")
    out.append("  - ../sharing-model.md")
    out.append("---")
    out.append("")
    out.append(f"# `{name}`")
    out.append("")
    out.append("## Identity")
    out.append("")
    out.append("| | |")
    out.append("|---|---|")
    out.append(f"| **API name** | `{name}` |")
    out.append(f"| **Label** | `{name}` |")
    out.append(f"| **User license** | {p['license']} |")
    out.append("| **License count** | _Not visible from source._ |")
    origin = "Custom (engagement-authored)" if p["custom"] else "Stock with customizations"
    out.append(f"| **Origin** | {origin} |")
    out.append(f"| **Description** | {p['desc'] or '_Not set._'} |")
    out.append("")
    out.append("## Persona")
    out.append("")
    out.append(persona)
    out.append("")
    out.append("## Object permissions")
    out.append("")
    if p["obj_perms"]:
        out.append("| Object | Read | Create | Edit | Delete | View All | Modify All | Notes |")
        out.append("|---|---|---|---|---|---|---|---|")
        any_custom = False
        for obj, flg in p["obj_perms"]:
            note = ""
            if obj in CUSTOM_OBJECTS:
                note = "engagement custom object"
                any_custom = True
            elif flg["modifyAllRecords"] or flg["viewAllRecords"]:
                note = "elevated (View/Modify All)"
            out.append(f"| `{obj}` | {fmt_check(flg['allowRead'])} | {fmt_check(flg['allowCreate'])} | {fmt_check(flg['allowEdit'])} | {fmt_check(flg['allowDelete'])} | {fmt_check(flg['viewAllRecords'])} | {fmt_check(flg['modifyAllRecords'])} | {note} |")
        if not any_custom:
            out.append("")
            out.append("_No engagement custom-object access._")
    else:
        out.append("_No object permissions declared in source — uses minimum-access defaults._")
    out.append("")
    out.append("## Field-level security overrides")
    out.append("")
    if p["fls_overrides"]:
        out.append("| Object | Field | Default | This profile | Why |")
        out.append("|---|---|---|---|---|")
        for obj, fld, r, e in p["fls_overrides"][:25]:
            this = "Hidden" if not r else ("Read-only" if not e else "Editable")
            out.append(f"| `{obj}` | `{fld}` | per field meta | **{this}** | _unknown_ |")
        if len(p["fls_overrides"]) > 25:
            out.append(f"| _…and {len(p['fls_overrides']) - 25} more_ | | | | |")
    else:
        out.append("_No FLS overrides — uses default field visibility._")
    out.append("")
    out.append("## App access")
    out.append("")
    if p["apps_visible"]:
        for a in p["apps_visible"]:
            tag = " (default)" if a == p["default_app"] else ""
            out.append(f"- `{a}`{tag}")
    else:
        out.append("_Stock Salesforce app only._")
    out.append("")
    out.append("## Tab settings")
    out.append("")
    if p["tab_overrides"]:
        out.append("| Tab | This profile |")
        out.append("|---|---|")
        for t, v in p["tab_overrides"][:30]:
            out.append(f"| `{t}` | **{v}** |")
        if len(p["tab_overrides"]) > 30:
            out.append(f"| _…and {len(p['tab_overrides']) - 30} more_ | |")
    else:
        out.append("_All tabs use default visibility._")
    out.append("")
    out.append("## System permissions of note")
    out.append("")
    if p["sys_perms"]:
        for s in p["sys_perms"]:
            out.append(f"- **`{s}`** — Enabled.")
    else:
        out.append("_No notable system permission overrides._")
    out.append("")
    out.append("## Apex class access")
    out.append("")
    if p["classes"]:
        for c in p["classes"][:50]:
            out.append(f"- `{c}`")
        if len(p["classes"]) > 50:
            out.append(f"- _…and {len(p['classes']) - 50} more_")
    else:
        out.append("_No engagement-specific Apex class access._")
    out.append("")
    out.append("## Visualforce page access")
    out.append("")
    if p["pages"]:
        for pg in p["pages"][:50]:
            out.append(f"- `{pg}`")
        if len(p["pages"]) > 50:
            out.append(f"- _…and {len(p['pages']) - 50} more_")
    else:
        out.append("_No engagement-specific VF page access._")
    out.append("")
    out.append("## Connected App access")
    out.append("")
    if p["conn_apps"]:
        for c in p["conn_apps"]:
            out.append(f"- `{c}`")
    else:
        out.append("_No engagement-specific Connected App access._")
    out.append("")
    out.append("## Typically assigned with")
    out.append("")
    out.append("_None known; permission sets are assigned ad-hoc._")
    out.append("")
    out.append("## Related decisions")
    out.append("")
    out.append("_None._")
    return "\n".join(out) + "\n"


profiles_dir = pathlib.Path("force-app/main/default/profiles")
out_dir = pathlib.Path("docs/security/profiles")
out_dir.mkdir(parents=True, exist_ok=True)

written = []
preserved = []
inventory = []
for xml_path in sorted(profiles_dir.glob("*.profile-meta.xml")):
    p = parse_profile(xml_path)
    out_name = re.sub(r"\s+", "_", p["name"]) + ".md"
    out_path = out_dir / out_name
    if out_path.exists():
        existing = out_path.read_text(encoding="utf-8")
        m = re.search(r"^last_updated_by:\s*(.+)$", existing, re.MULTILINE)
        if m and not m.group(1).strip().startswith("archon-"):
            preserved.append({"doc": str(out_path), "reason": f"last_updated_by was '{m.group(1).strip()}'"})
            inventory.append((p["name"], out_name, p["license"], "Stock-customized" if not p["custom"] else "Custom", "preserved"))
            continue
    out_path.write_text(render_profile(p), encoding="utf-8")
    written.append(out_name)
    inventory.append((p["name"], out_name, p["license"], "Custom (engagement)" if p["custom"] else "Stock", "written"))

readme_lines = [
    "---",
    "title: Profiles",
    "audience: public",
    "last_updated: 2026-05-15",
    "last_updated_by: archon-discover",
    "related_tickets: []",
    "related_docs:",
    "  - ../README.md",
    "  - ../sharing-model.md",
    "---",
    "",
    "# Profiles — Meditrina",
    "",
    "One file per profile in `force-app/main/default/profiles/`. The org has 25 profiles retrieved into source; most are stock Salesforce profiles (some lightly customized), with `Osibtys Profile` and `System Admin Full` being the engagement-named variants of note.",
    "",
    "## Profile inventory",
    "",
    "| Profile | Origin | User license | Doc |",
    "|---|---|---|---|",
]
for name, fname, lic, origin, _status in sorted(inventory):
    readme_lines.append(f"| `{name}` | {origin} | {lic} | [`{fname}`](./{fname}) |")
readme_lines.append("")

(out_dir / "README.md").write_text("\n".join(readme_lines), encoding="utf-8")

print(f"profiles written: {len(written)}")
for f in written:
    print(f"  docs/security/profiles/{f}")
print(f"profiles preserved: {len(preserved)}")
print("README: docs/security/profiles/README.md")
