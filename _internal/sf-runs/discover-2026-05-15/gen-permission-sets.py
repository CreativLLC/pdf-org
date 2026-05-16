import os, re, xml.etree.ElementTree as ET, pathlib

os.chdir(r"c:\Users\m0gul\Documents\meditrinaPOCsandbox\archonJiraDemoOrg")

NS = "{http://soap.sforce.com/2006/04/metadata}"


def parse_psg_membership():
    """Map: ps_name -> [psg_names that include it]."""
    mem = {}
    psg_dir = pathlib.Path("force-app/main/default/permissionsetgroups")
    if not psg_dir.exists():
        return mem
    for x in psg_dir.glob("*.permissionsetgroup-meta.xml"):
        psg = x.stem.replace(".permissionsetgroup-meta", "")
        tree = ET.parse(x)
        root = tree.getroot()
        for ps in root.findall(f"{NS}permissionSets"):
            mem.setdefault(ps.text, []).append(psg)
    return mem


def parse_ps(path):
    tree = ET.parse(path)
    root = tree.getroot()
    name = path.stem.replace(".permissionset-meta", "")
    label = (root.findtext(f"{NS}label") or name).strip()
    license = (root.findtext(f"{NS}license") or "").strip() or None
    desc = (root.findtext(f"{NS}description") or "").strip() or None
    has_act = (root.findtext(f"{NS}hasActivationRequired") or "false").strip() == "true"

    obj_perms = []
    for op in root.findall(f"{NS}objectPermissions"):
        obj = op.findtext(f"{NS}object") or ""
        flags = {k: (op.findtext(f"{NS}{k}") or "false") == "true"
                 for k in ("allowRead","allowCreate","allowEdit","allowDelete","viewAllRecords","modifyAllRecords")}
        if any(flags.values()):
            obj_perms.append((obj, flags))
    obj_perms.sort()

    fls = []
    for fp in root.findall(f"{NS}fieldPermissions"):
        field = fp.findtext(f"{NS}field") or ""
        readable = (fp.findtext(f"{NS}readable") or "false") == "true"
        editable = (fp.findtext(f"{NS}editable") or "false") == "true"
        if readable or editable:
            obj_part, _, field_part = field.partition(".")
            fls.append((obj_part, field_part, readable, editable))
    fls.sort()

    apps = []
    default_app = None
    for av in root.findall(f"{NS}applicationVisibilities"):
        a = av.findtext(f"{NS}application") or ""
        if (av.findtext(f"{NS}visible") or "false") == "true":
            apps.append(a)
        if (av.findtext(f"{NS}default") or "false") == "true":
            default_app = a
    apps.sort()

    tabs = []
    for ts in root.findall(f"{NS}tabSettings"):
        t = ts.findtext(f"{NS}tab") or ""
        v = ts.findtext(f"{NS}visibility") or ""
        if v in ("Visible", "Available", "Hidden", "DefaultOff"):
            tabs.append((t, v))
    tabs.sort()

    sys_perms = []
    for up in root.findall(f"{NS}userPermissions"):
        n = up.findtext(f"{NS}name") or ""
        en = (up.findtext(f"{NS}enabled") or "false") == "true"
        if en:
            sys_perms.append(n)
    sys_perms.sort()

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
    cps = sorted([
        cp.findtext(f"{NS}name")
        for cp in root.findall(f"{NS}customPermissions")
        if (cp.findtext(f"{NS}enabled") or "false") == "true"
    ])

    return {
        "name": name, "label": label, "license": license, "desc": desc,
        "has_activation": has_act, "obj_perms": obj_perms, "fls": fls,
        "apps": apps, "default_app": default_app, "tabs": tabs,
        "sys_perms": sys_perms, "classes": classes, "pages": pages,
        "conn_apps": conn_apps, "custom_perms": cps,
    }


PURPOSE = {
    "PdfGeneratorAdmin": "Authoring + administration of the PDF template-builder feature. Grants CRUD on `Document_Template__c`, `Template_Version__c`, `Template_Mapping__c`, plus tab/page/class access for the builder LWC + render Visualforce. _(inferred)_",
    "Manage_Billing": "Adds CRUD on the billing/invoice surface for users whose base profile is finance-restricted. _(inferred from naming)_",
    "View_Invoices": "Read-only view of `Invoice__c` for users who don't otherwise have invoice access. _(inferred from naming)_",
    "System_Admin_Extra_Perms": "Bundle of high-impact system permissions reserved for named admins layered on top of the `Admin` profile. _(inferred from naming)_",
    "MFA_Required": "Carrier permission set used to flag user populations subject to mandatory multi-factor authentication. Likely empty of grants — exists for assignment tracking rather than access. _(inferred from naming)_",
    "TEST": "Engagement-internal test/sandbox permission set. Likely temporary; revisit before promoting to production. _(inferred from naming)_",
    "sfdcInternalInt__sfdc_nc_constraints_engine_deploy": "Salesforce-internal permission set (managed namespace `sfdcInternalInt__`); not authored by the engagement. _(stock SFDC managed)_",
}

CUSTOM_OBJECTS = {
    "Document_Template__c","Form__c","Signature__c","Template_Mapping__c","Template_Version__c",
    "Contact_Role__c","Project__c","Project_Allocation__c","Invoice__c","Time_Sheet__c",
    "Transaction__c","Requirement_Use_Case__c","Acct__c",
}


def fmt_check(b):
    return "✓" if b else "—"


def render_ps(p, psg_membership):
    name = p["name"]
    purpose = PURPOSE.get(name, "_Inferred purpose unavailable from source — verify with engagement._")
    psgs = psg_membership.get(name, [])
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
    if psgs:
        out.append("  - ../permission-set-groups.md")
    out.append("---")
    out.append("")
    out.append(f"# `{name}`")
    out.append("")
    out.append("## Identity")
    out.append("")
    out.append("| | |")
    out.append("|---|---|")
    out.append(f"| **API name** | `{name}` |")
    out.append(f"| **Label** | {p['label']} |")
    out.append(f"| **License** | {p['license'] or '_None (does not require a permission set license)._'} |")
    if psgs:
        out.append(f"| **PSG membership** | {', '.join(f'[`{g}`](../permission-set-groups.md)' for g in psgs)} |")
    else:
        out.append("| **PSG membership** | _Not a member of any Permission Set Group._ |")
    if name.startswith("sfdcInternalInt__"):
        origin = "Stock SFDC (managed namespace)"
    elif name in PURPOSE:
        origin = "Engagement-authored"
    else:
        origin = "_Unknown_"
    out.append(f"| **Origin** | {origin} |")
    out.append(f"| **Description** | {p['desc'] or '_Not set._'} |")
    out.append(f"| **Activation required** | {'Yes' if p['has_activation'] else 'No'} |")
    out.append("")
    out.append("## Purpose")
    out.append("")
    out.append(purpose)
    out.append("")
    out.append("## Object permissions added")
    out.append("")
    if p["obj_perms"]:
        out.append("| Object | Read | Create | Edit | Delete | View All | Modify All | Notes |")
        out.append("|---|---|---|---|---|---|---|---|")
        for obj, flg in p["obj_perms"]:
            note = "engagement custom object" if obj in CUSTOM_OBJECTS else (
                "elevated (View/Modify All)" if (flg["modifyAllRecords"] or flg["viewAllRecords"]) else "")
            out.append(f"| `{obj}` | {fmt_check(flg['allowRead'])} | {fmt_check(flg['allowCreate'])} | {fmt_check(flg['allowEdit'])} | {fmt_check(flg['allowDelete'])} | {fmt_check(flg['viewAllRecords'])} | {fmt_check(flg['modifyAllRecords'])} | {note} |")
    else:
        out.append("_No object permissions added._")
    out.append("")
    out.append("## Field-level security added")
    out.append("")
    if p["fls"]:
        out.append("| Object | Field | Read | Edit |")
        out.append("|---|---|---|---|")
        for obj, fld, r, e in p["fls"][:50]:
            out.append(f"| `{obj}` | `{fld}` | {fmt_check(r)} | {fmt_check(e)} |")
        if len(p["fls"]) > 50:
            out.append(f"| _…and {len(p['fls']) - 50} more_ | | | |")
    else:
        out.append("_No field-level security added._")
    out.append("")
    out.append("## App access added")
    out.append("")
    if p["apps"]:
        for a in p["apps"]:
            tag = " (default)" if a == p["default_app"] else ""
            out.append(f"- `{a}`{tag}")
    else:
        out.append("_No app access added._")
    out.append("")
    out.append("## Tab settings overrides")
    out.append("")
    if p["tabs"]:
        out.append("| Tab | Setting |")
        out.append("|---|---|")
        for t, v in p["tabs"][:30]:
            out.append(f"| `{t}` | **{v}** |")
        if len(p["tabs"]) > 30:
            out.append(f"| _…and {len(p['tabs']) - 30} more_ | |")
    else:
        out.append("_No tab settings overrides._")
    out.append("")
    out.append("## System permissions added")
    out.append("")
    if p["sys_perms"]:
        for s in p["sys_perms"]:
            out.append(f"- **`{s}`** — Enabled.")
    else:
        out.append("_No system permissions added._")
    out.append("")
    out.append("## Custom Permissions granted")
    out.append("")
    if p["custom_perms"]:
        for c in p["custom_perms"]:
            out.append(f"- [`{c}`](../custom-permissions.md) — _gating context not yet documented_")
    else:
        out.append("_No Custom Permissions granted._")
    out.append("")
    out.append("## Apex class access added")
    out.append("")
    if p["classes"]:
        for c in p["classes"][:30]:
            out.append(f"- `{c}`")
        if len(p["classes"]) > 30:
            out.append(f"- _…and {len(p['classes']) - 30} more_")
    else:
        out.append("_No Apex class access added._")
    out.append("")
    out.append("## Visualforce page access added")
    out.append("")
    if p["pages"]:
        for pg in p["pages"][:30]:
            out.append(f"- `{pg}`")
        if len(p["pages"]) > 30:
            out.append(f"- _…and {len(p['pages']) - 30} more_")
    else:
        out.append("_No Visualforce page access added._")
    out.append("")
    out.append("## Connected App access added")
    out.append("")
    if p["conn_apps"]:
        for c in p["conn_apps"]:
            out.append(f"- `{c}`")
    else:
        out.append("_No Connected App access added._")
    out.append("")
    out.append("## Typical assignment pattern")
    out.append("")
    if psgs:
        out.append(f"Assigned via PSG membership: {', '.join(f'`{g}`' for g in psgs)}.")
    else:
        out.append("_Assignment pattern not documented; check Setup or the engagement's onboarding runbook._")
    out.append("")
    out.append("## Related decisions")
    out.append("")
    out.append("_None._")
    return "\n".join(out) + "\n"


psg_mem = parse_psg_membership()
ps_dir = pathlib.Path("force-app/main/default/permissionsets")
out_dir = pathlib.Path("docs/security/permission-sets")
out_dir.mkdir(parents=True, exist_ok=True)

written = []
preserved = []
inventory = []
for xml_path in sorted(ps_dir.glob("*.permissionset-meta.xml")):
    p = parse_ps(xml_path)
    out_name = p["name"] + ".md"
    out_path = out_dir / out_name
    if out_path.exists():
        existing = out_path.read_text(encoding="utf-8")
        m = re.search(r"^last_updated_by:\s*(.+)$", existing, re.MULTILINE)
        if m and not m.group(1).strip().startswith("archon-"):
            preserved.append(out_name)
            inventory.append((p["name"], out_name, p["license"], psg_mem.get(p["name"], []), "preserved"))
            continue
    out_path.write_text(render_ps(p, psg_mem), encoding="utf-8")
    written.append(out_name)
    inventory.append((p["name"], out_name, p["license"], psg_mem.get(p["name"], []), "written"))

readme_lines = [
    "---",
    "title: Permission Sets",
    "audience: public",
    "last_updated: 2026-05-15",
    "last_updated_by: archon-discover",
    "related_tickets: []",
    "related_docs:",
    "  - ../README.md",
    "  - ../sharing-model.md",
    "  - ../permission-set-groups.md",
    "---",
    "",
    "# Permission Sets — Meditrina",
    "",
    "Permission sets are additive grants layered on top of a user's base profile. This index lists every permission set in `force-app/main/default/permissionsets/`; per-PS detail is in the linked file.",
    "",
    "## Permission set inventory",
    "",
    "| Permission Set | License | PSG membership | Doc |",
    "|---|---|---|---|",
]
for name, fname, lic, psgs, _status in sorted(inventory):
    psg_str = ", ".join(f"`{g}`" for g in psgs) if psgs else "_None_"
    readme_lines.append(f"| `{name}` | {lic or '_None_'} | {psg_str} | [`{fname}`](./{fname}) |")
readme_lines.append("")
readme_lines.append("## Permission Set Groups")
readme_lines.append("")
readme_lines.append("Two PSGs exist in source — both `force__` namespace (Salesforce-managed packages); see [`../permission-set-groups.md`](../permission-set-groups.md) for the section-level summary.")
readme_lines.append("")

(out_dir / "README.md").write_text("\n".join(readme_lines), encoding="utf-8")

print(f"permission sets written: {len(written)}")
for f in written:
    print(f"  docs/security/permission-sets/{f}")
print(f"preserved: {len(preserved)}")
print("README: docs/security/permission-sets/README.md")
