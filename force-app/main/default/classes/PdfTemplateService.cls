/**
 * Renders a Template_Version__c JSON definition against a source SObject record into
 * a flat list of pre-rendered XHTML blocks suitable for Visualforce renderAs="pdf".
 *
 * All recursion (rows/cols/nested children) and conditional evaluation happens here in
 * Apex; the VF page is a dumb repeater. This sidesteps apex:repeat's no-recursion limit
 * and keeps a single source of truth for merge logic shared between live preview and
 * the eventual PDF render.
 *
 * Public entry point: build(templateVersionId, recordId) -> PageModel.
 */
public with sharing class PdfTemplateService {

    /* ---------- Public DTOs ---------- */

    public class PageModel {
        public PageProps page { get; set; }
        public List<String> htmlBlocks { get; set; }
    }

    public class PageProps {
        public String size { get; set; }
        public String orientation { get; set; }
        public String margins { get; set; }
        public String fontStack { get; set; }
        public String bodyCss { get; set; }
    }

    public class TemplateException extends Exception {}

    /* ---------- Build context ---------- */

    public class BuildContext {
        public String targetSObject;
        public String rootAlias;
        public Id recordId;
        public SObject rootRow;
        public Map<String, List<SObject>> relatedRows = new Map<String, List<SObject>>();
        public SObject currentRowObj;
    }

    private static final Integer MAX_RELATED_ROWS_DEFAULT = 1000;
    private static final Integer MAX_PARENT_HOPS = 5;

    /* =========================================================================
     *  ENTRY POINT
     * ========================================================================= */

    public static PageModel build(Id templateVersionId, Id recordId) {
        if (templateVersionId == null || recordId == null) {
            throw new TemplateException('Both templateVersionId and recordId are required.');
        }

        Template_Version__c tv = [
            SELECT Id, Document_Template__c, Definition_Json__c, Status__c
            FROM Template_Version__c
            WHERE Id = :templateVersionId
            LIMIT 1
        ];
        Document_Template__c dt = [
            SELECT Id, Target_SObject__c
            FROM Document_Template__c
            WHERE Id = :tv.Document_Template__c
            LIMIT 1
        ];

        String defJson = loadDefinitionJson(tv);
        return buildFromJson(defJson, dt.Target_SObject__c, recordId);
    }

    /**
     * Same render pipeline as build(), but takes JSON + target object directly.
     * Used by the live preview LWC to render unsaved template edits.
     */
    public static PageModel buildFromJson(String defJson, String targetSObject, Id recordId) {
        if (String.isBlank(defJson) || String.isBlank(targetSObject) || recordId == null) {
            throw new TemplateException('defJson, targetSObject, and recordId are all required.');
        }
        Map<String, Object> def;
        try {
            def = (Map<String, Object>) JSON.deserializeUntyped(defJson);
        } catch (Exception e) {
            throw new TemplateException('Definition JSON is not valid: ' + e.getMessage());
        }

        BuildContext ctx = new BuildContext();
        ctx.targetSObject = targetSObject;
        ctx.recordId = recordId;
        ctx.rootAlias = targetSObject;

        FieldCollector collector = new FieldCollector();
        collector.collect(def);

        ctx.rootRow = queryRoot(ctx.targetSObject, recordId, collector.rootFields, collector.parentTraversals);
        ctx.relatedRows = queryRelated(ctx.targetSObject, recordId, collector.relations);

        PageModel model = new PageModel();
        model.page = parsePageProps(def);
        model.htmlBlocks = new List<String>();

        Object root = def.get('root');
        if (root instanceof Map<String, Object>) {
            renderNode((Map<String, Object>) root, ctx, model.htmlBlocks);
        }
        Object tables = def.get('tables');
        if (tables instanceof List<Object>) {
            for (Object t : (List<Object>) tables) {
                if (t instanceof Map<String, Object>) {
                    renderNode((Map<String, Object>) t, ctx, model.htmlBlocks);
                }
            }
        }
        return model;
    }

    private static String loadDefinitionJson(Template_Version__c tv) {
        if (String.isNotBlank(tv.Definition_Json__c)) {
            return tv.Definition_Json__c;
        }
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :tv.Id
        ];
        if (links.isEmpty()) {
            throw new TemplateException('Template_Version__c has no Definition JSON and no spillover file.');
        }
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink l : links) docIds.add(l.ContentDocumentId);
        List<ContentVersion> cvs = [
            SELECT Id, Title, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds AND IsLatest = true AND Title = 'definition.json'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (cvs.isEmpty()) {
            throw new TemplateException('Spillover file "definition.json" not found on Template_Version__c.');
        }
        return cvs[0].VersionData.toString();
    }

    private static PageProps parsePageProps(Map<String, Object> def) {
        PageProps p = new PageProps();
        p.size = 'LETTER';
        p.orientation = 'portrait';
        p.margins = '0.5in';
        p.fontStack = '\'Helvetica Neue\', Arial, sans-serif';
        p.bodyCss = '';
        Object pageObj = def.get('page');
        if (pageObj instanceof Map<String, Object>) {
            Map<String, Object> pp = (Map<String, Object>) pageObj;
            if (pp.get('size') instanceof String) p.size = (String) pp.get('size');
            if (pp.get('orientation') instanceof String) p.orientation = (String) pp.get('orientation');
            if (pp.get('margins') instanceof String) p.margins = (String) pp.get('margins');
        }
        if (def.get('fontStack') instanceof String) p.fontStack = (String) def.get('fontStack');
        if (def.get('bodyCss') instanceof String) p.bodyCss = (String) def.get('bodyCss');
        return p;
    }

    /* =========================================================================
     *  Field collection
     * ========================================================================= */

    public class FieldCollector {
        public Set<String> rootFields = new Set<String>{ 'Id', 'Name' };
        public Map<String, Set<String>> parentTraversals = new Map<String, Set<String>>();
        public Map<String, Set<String>> relations = new Map<String, Set<String>>();

        public void collect(Map<String, Object> def) {
            walkNode(def.get('root'));
            Object tables = def.get('tables');
            if (tables instanceof List<Object>) {
                for (Object t : (List<Object>) tables) walkNode(t);
            }
        }

        private void walkNode(Object n) {
            if (!(n instanceof Map<String, Object>)) return;
            Map<String, Object> m = (Map<String, Object>) n;
            String t = (String) m.get('type');
            Map<String, Object> props = m.get('props') instanceof Map<String, Object>
                ? (Map<String, Object>) m.get('props') : new Map<String, Object>();

            if (m.get('visibleIf') instanceof String) collectFromExpr((String) m.get('visibleIf'));

            if (t == 'text' && props.get('spans') instanceof List<Object>) {
                for (Object s : (List<Object>) props.get('spans')) {
                    if (s instanceof Map<String, Object>) {
                        Map<String, Object> sm = (Map<String, Object>) s;
                        if (sm.get('token') instanceof String) collectToken((String) sm.get('token'));
                    }
                }
            }
            if (t == 'image') {
                if (props.get('fromRelation') instanceof String) {
                    String rel = (String) props.get('fromRelation');
                    if (!relations.containsKey(rel)) relations.put(rel, new Set<String>{ 'Id' });
                }
                if (props.get('filterExpr') instanceof String) collectFromExpr((String) props.get('filterExpr'));
            }
            if (t == 'table') {
                String rel = (String) props.get('fromRelation');
                if (String.isNotBlank(rel)) {
                    if (!relations.containsKey(rel)) relations.put(rel, new Set<String>{ 'Id' });
                    if (props.get('rowVisibleIf') instanceof String) collectFromExpr((String) props.get('rowVisibleIf'), rel);
                    Object cols = props.get('columns');
                    if (cols instanceof List<Object>) {
                        for (Object c : (List<Object>) cols) {
                            if (!(c instanceof Map<String, Object>)) continue;
                            Map<String, Object> cm = (Map<String, Object>) c;
                            Object spans = cm.get('spans');
                            if (spans instanceof List<Object>) {
                                for (Object s : (List<Object>) spans) {
                                    if (s instanceof Map<String, Object>) {
                                        Map<String, Object> sm = (Map<String, Object>) s;
                                        if (sm.get('token') instanceof String) {
                                            collectToken((String) sm.get('token'), rel);
                                        }
                                    }
                                }
                            }
                            if (cm.get('cellExpr') instanceof String) collectFromExpr((String) cm.get('cellExpr'), rel);
                        }
                    }
                }
            }

            Object children = m.get('children');
            if (children instanceof List<Object>) {
                for (Object c : (List<Object>) children) walkNode(c);
            }
        }

        public void collectToken(String token) { collectToken(token, null); }

        public void collectToken(String token, String relationContext) {
            if (String.isBlank(token)) return;
            if (token.startsWith('$')) return;
            if (token.startsWith('row.') && relationContext != null) {
                String f = token.substring(4);
                Set<String> fs = relations.get(relationContext);
                if (fs == null) { fs = new Set<String>{ 'Id' }; relations.put(relationContext, fs); }
                fs.add(f);
                return;
            }
            List<String> parts = token.split('\\.');
            if (parts.size() == 1) {
                rootFields.add(parts[0]);
                return;
            }
            String parentPath = '';
            Integer hopLimit = Math.min(parts.size() - 1, MAX_PARENT_HOPS);
            for (Integer i = 0; i < hopLimit; i++) {
                parentPath = (parentPath == '') ? parts[i] : parentPath + '.' + parts[i];
            }
            String fieldName = parts[parts.size() - 1];
            if (!parentTraversals.containsKey(parentPath)) {
                parentTraversals.put(parentPath, new Set<String>());
            }
            parentTraversals.get(parentPath).add(fieldName);
        }

        public void collectFromExpr(String expr) { collectFromExpr(expr, null); }

        public void collectFromExpr(String expr, String relationContext) {
            if (String.isBlank(expr)) return;
            Matcher m = Pattern.compile('([A-Za-z_][A-Za-z_0-9]*(?:\\.[A-Za-z_][A-Za-z_0-9]*)+)').matcher(expr);
            while (m.find()) collectToken(m.group(1), relationContext);
        }
    }

    /* =========================================================================
     *  SOQL
     * ========================================================================= */

    private static SObject queryRoot(String objectApi, Id recordId, Set<String> directFields, Map<String, Set<String>> parents) {
        Set<String> selectClauses = new Set<String>();
        for (String f : directFields) selectClauses.add(escapeFieldPath(f));
        for (String parentPath : parents.keySet()) {
            for (String f : parents.get(parentPath)) {
                selectClauses.add(escapeFieldPath(parentPath + '.' + f));
            }
        }
        if (selectClauses.isEmpty()) selectClauses.add('Id');
        String soql = 'SELECT ' + String.join(new List<String>(selectClauses), ', ')
            + ' FROM ' + escapeIdentifier(objectApi)
            + ' WHERE Id = :recordId LIMIT 1';
        List<SObject> rows = Database.query(soql);
        if (rows.isEmpty()) {
            throw new TemplateException('Source record not found: ' + recordId);
        }
        return rows[0];
    }

    private static Map<String, List<SObject>> queryRelated(String objectApi, Id recordId, Map<String, Set<String>> relations) {
        Map<String, List<SObject>> out = new Map<String, List<SObject>>();
        if (relations.isEmpty()) return out;

        Schema.SObjectType rootType = Schema.getGlobalDescribe().get(objectApi);
        if (rootType == null) {
            throw new TemplateException('Unknown SObject: ' + objectApi);
        }
        Map<String, Schema.ChildRelationship> childByName = new Map<String, Schema.ChildRelationship>();
        for (Schema.ChildRelationship cr : rootType.getDescribe().getChildRelationships()) {
            String relName = cr.getRelationshipName();
            if (relName != null) childByName.put(relName, cr);
        }

        for (String relName : relations.keySet()) {
            String stripped = relName.endsWith('__r') ? relName.removeEnd('__r') : relName;
            Schema.ChildRelationship cr = childByName.get(stripped);
            if (cr == null) cr = childByName.get(relName);
            if (cr == null) {
                out.put(relName, new List<SObject>());
                continue;
            }
            String childObj = cr.getChildSObject().getDescribe().getName();
            String fkField = cr.getField().getDescribe().getName();
            Set<String> fields = relations.get(relName);
            fields.add('Id');
            fields.add(fkField);

            String soql = 'SELECT ' + String.join(escapeFieldList(fields), ', ')
                + ' FROM ' + escapeIdentifier(childObj)
                + ' WHERE ' + escapeIdentifier(fkField) + ' = :recordId'
                + ' LIMIT ' + MAX_RELATED_ROWS_DEFAULT;
            out.put(relName, Database.query(soql));
        }
        return out;
    }

    private static List<String> escapeFieldList(Set<String> fields) {
        List<String> out = new List<String>();
        for (String f : fields) out.add(escapeFieldPath(f));
        return out;
    }

    private static String escapeFieldPath(String path) {
        if (!Pattern.matches('[A-Za-z_][A-Za-z_0-9]*(\\.[A-Za-z_][A-Za-z_0-9]*)*', path)) {
            throw new TemplateException('Illegal field path: ' + path);
        }
        return path;
    }

    private static String escapeIdentifier(String name) {
        if (!Pattern.matches('[A-Za-z_][A-Za-z_0-9]*', name)) {
            throw new TemplateException('Illegal identifier: ' + name);
        }
        return name;
    }

    /* =========================================================================
     *  Rendering
     * ========================================================================= */

    private static void renderNode(Map<String, Object> node, BuildContext ctx, List<String> blocks) {
        if (node == null) return;
        String visibleIf = node.get('visibleIf') instanceof String ? (String) node.get('visibleIf') : null;
        if (visibleIf != null && !evalBool(visibleIf, ctx)) return;

        String type = (String) node.get('type');
        Map<String, Object> props = node.get('props') instanceof Map<String, Object>
            ? (Map<String, Object>) node.get('props') : new Map<String, Object>();

        if (type == 'row')   { blocks.add(renderRow(node, ctx));   return; }
        if (type == 'col')   { blocks.add(renderCol(node, ctx));   return; }
        if (type == 'text')  { blocks.add(renderText(props, ctx)); return; }
        if (type == 'image') { blocks.add(renderImage(props, ctx)); return; }
        if (type == 'table') { blocks.add(renderTable(props, ctx)); return; }
        if (type == 'spacer'){ blocks.add(renderSpacer(props));     return; }
        if (type == 'rule')  { blocks.add('<hr style="border: none; border-top: 1px solid #888; margin: 8px 0;" />'); return; }
    }

    private static String renderRow(Map<String, Object> node, BuildContext ctx) {
        List<String> childBlocks = new List<String>();
        Object children = node.get('children');
        if (children instanceof List<Object>) {
            for (Object c : (List<Object>) children) {
                if (c instanceof Map<String, Object>) {
                    List<String> sub = new List<String>();
                    renderNode((Map<String, Object>) c, ctx, sub);
                    childBlocks.addAll(sub);
                }
            }
        }
        Map<String, Object> props = node.get('props') instanceof Map<String, Object>
            ? (Map<String, Object>) node.get('props') : new Map<String, Object>();
        String gap = props.get('gap') instanceof String ? (String) props.get('gap') : '0';
        String style = 'display: table; width: 100%; margin-bottom: ' + escapeHtml(gap) + ';';
        return '<div style="' + style + '">' + String.join(childBlocks, '') + '</div>';
    }

    private static String renderCol(Map<String, Object> node, BuildContext ctx) {
        List<String> childBlocks = new List<String>();
        Object children = node.get('children');
        if (children instanceof List<Object>) {
            for (Object c : (List<Object>) children) {
                if (c instanceof Map<String, Object>) {
                    List<String> sub = new List<String>();
                    renderNode((Map<String, Object>) c, ctx, sub);
                    childBlocks.addAll(sub);
                }
            }
        }
        Map<String, Object> props = node.get('props') instanceof Map<String, Object>
            ? (Map<String, Object>) node.get('props') : new Map<String, Object>();
        String width = props.get('width') instanceof String ? (String) props.get('width') : 'auto';
        String pad = props.get('padding') instanceof String ? (String) props.get('padding') : '0 8px';
        String valign = props.get('vAlign') instanceof String ? (String) props.get('vAlign') : 'top';
        String style = 'display: table-cell; vertical-align: ' + escapeHtml(valign)
            + '; width: ' + escapeHtml(width) + '; padding: ' + escapeHtml(pad) + ';';
        return '<div style="' + style + '">' + String.join(childBlocks, '') + '</div>';
    }

    private static String renderText(Map<String, Object> props, BuildContext ctx) {
        String align = props.get('align') instanceof String ? (String) props.get('align') : 'left';
        String fs = props.get('fontSize') instanceof String ? (String) props.get('fontSize') : '11pt';
        String mb = props.get('marginBottom') instanceof String ? (String) props.get('marginBottom') : '6px';
        String style = 'text-align: ' + escapeHtml(align) + '; font-size: ' + escapeHtml(fs) + '; margin-bottom: ' + escapeHtml(mb) + ';';

        Object spansRaw = props.get('spans');
        List<String> out = new List<String>();
        if (spansRaw instanceof List<Object>) {
            for (Object s : (List<Object>) spansRaw) {
                if (!(s instanceof Map<String, Object>)) continue;
                Map<String, Object> sm = (Map<String, Object>) s;
                String content = '';
                if (sm.get('text') instanceof String) {
                    content = escapeHtml((String) sm.get('text'));
                } else if (sm.get('token') instanceof String) {
                    content = escapeHtml(resolveToken((String) sm.get('token'), ctx));
                }
                content = wrapStyled(content, sm);
                out.add(content);
            }
        }
        return '<div style="' + style + '">' + String.join(out, '') + '</div>';
    }

    private static String wrapStyled(String content, Map<String, Object> sm) {
        List<String> styles = new List<String>();
        if (sm.get('bold') == true) styles.add('font-weight: bold');
        if (sm.get('italic') == true) styles.add('font-style: italic');
        if (sm.get('underline') == true) styles.add('text-decoration: underline');
        if (sm.get('color') instanceof String) styles.add('color: ' + escapeHtml((String) sm.get('color')));
        if (sm.get('fontSize') instanceof String) styles.add('font-size: ' + escapeHtml((String) sm.get('fontSize')));
        if (styles.isEmpty()) return content;
        return '<span style="' + String.join(styles, '; ') + ';">' + content + '</span>';
    }

    private static String renderImage(Map<String, Object> props, BuildContext ctx) {
        String dataUri = resolveImageDataUri(props, ctx);
        if (String.isBlank(dataUri)) return '';
        String maxW = props.get('maxWidth') instanceof String ? (String) props.get('maxWidth') : 'auto';
        String maxH = props.get('maxHeight') instanceof String ? (String) props.get('maxHeight') : 'auto';
        String fixedW = props.get('width') instanceof String ? (String) props.get('width') : null;
        String fixedH = props.get('height') instanceof String ? (String) props.get('height') : null;
        String align = props.get('align') instanceof String ? (String) props.get('align') : 'left';

        List<String> styleParts = new List<String>();
        if (fixedW != null) styleParts.add('width: ' + escapeHtml(fixedW));
        if (fixedH != null) styleParts.add('height: ' + escapeHtml(fixedH));
        if (fixedW == null) styleParts.add('max-width: ' + escapeHtml(maxW));
        if (fixedH == null) styleParts.add('max-height: ' + escapeHtml(maxH));
        String style = String.join(styleParts, '; ') + ';';
        String wrapper = 'text-align: ' + escapeHtml(align) + '; margin: 4px 0;';
        return '<div style="' + wrapper + '"><img src="' + dataUri + '" style="' + style + '" /></div>';
    }

    private static String renderTable(Map<String, Object> props, BuildContext ctx) {
        String relName = (String) props.get('fromRelation');
        if (String.isBlank(relName)) return '';
        Object cols = props.get('columns');
        if (!(cols instanceof List<Object>)) return '';
        List<Map<String, Object>> columns = new List<Map<String, Object>>();
        for (Object c : (List<Object>) cols) {
            if (c instanceof Map<String, Object>) columns.add((Map<String, Object>) c);
        }

        String headerBg = props.get('headerBackground') instanceof String ? (String) props.get('headerBackground') : '#CCCCCC';
        String borderColor = props.get('borderColor') instanceof String ? (String) props.get('borderColor') : '#333333';
        String maxRowsRaw = props.get('maxRows') instanceof String ? (String) props.get('maxRows') : null;
        Integer maxRows = String.isNotBlank(maxRowsRaw) ? Integer.valueOf(maxRowsRaw) : MAX_RELATED_ROWS_DEFAULT;
        String rowVisibleIf = props.get('rowVisibleIf') instanceof String ? (String) props.get('rowVisibleIf') : null;

        List<SObject> rows = ctx.relatedRows.containsKey(relName) ? ctx.relatedRows.get(relName) : new List<SObject>();

        List<String> html = new List<String>();
        html.add('<table style="width: 100%; border-collapse: collapse; margin: 8px 0;" cellspacing="0" cellpadding="4">');
        html.add('<thead><tr>');
        for (Map<String, Object> c : columns) {
            String hdr = c.get('header') instanceof String ? (String) c.get('header') : '';
            String width = c.get('width') instanceof String ? ' width: ' + escapeHtml((String) c.get('width')) + ';' : '';
            html.add('<th style="border: 1px solid ' + escapeHtml(borderColor) + '; background-color: ' + escapeHtml(headerBg) + '; text-align: left;' + width + '">' + escapeHtml(hdr) + '</th>');
        }
        html.add('</tr></thead><tbody>');

        Integer count = 0;
        SObject prevRow = ctx.currentRowObj;
        for (SObject row : rows) {
            if (count >= maxRows) break;
            ctx.currentRowObj = row;
            if (rowVisibleIf != null && !evalBool(rowVisibleIf, ctx)) continue;
            html.add('<tr>');
            for (Map<String, Object> c : columns) {
                String width = c.get('width') instanceof String ? ' width: ' + escapeHtml((String) c.get('width')) + ';' : '';
                html.add('<td style="border: 1px solid ' + escapeHtml(borderColor) + '; vertical-align: top;' + width + '">');
                html.add(renderTableCell(c, ctx));
                html.add('</td>');
            }
            html.add('</tr>');
            count++;
        }
        ctx.currentRowObj = prevRow;
        html.add('</tbody></table>');
        return String.join(html, '');
    }

    private static String renderTableCell(Map<String, Object> col, BuildContext ctx) {
        if (col.get('cellExpr') instanceof String) {
            return escapeHtml(evalString((String) col.get('cellExpr'), ctx));
        }
        if (col.get('spans') instanceof List<Object>) {
            List<String> out = new List<String>();
            for (Object s : (List<Object>) col.get('spans')) {
                if (!(s instanceof Map<String, Object>)) continue;
                Map<String, Object> sm = (Map<String, Object>) s;
                String content = '';
                if (sm.get('text') instanceof String) content = escapeHtml((String) sm.get('text'));
                else if (sm.get('token') instanceof String) content = escapeHtml(resolveToken((String) sm.get('token'), ctx));
                out.add(wrapStyled(content, sm));
            }
            return String.join(out, '');
        }
        return '';
    }

    private static String renderSpacer(Map<String, Object> props) {
        String h = props.get('height') instanceof String ? (String) props.get('height') : '12px';
        return '<div style="height: ' + escapeHtml(h) + ';"></div>';
    }

    private static String escapeHtml(String s) {
        if (s == null) return '';
        return s.replace('&', '&amp;')
                .replace('<', '&lt;')
                .replace('>', '&gt;')
                .replace('"', '&quot;')
                .replace('\'', '&#39;');
    }

    /* =========================================================================
     *  Token resolution
     * ========================================================================= */

    public static String resolveToken(String token, BuildContext ctx) {
        if (String.isBlank(token)) return '';
        if (token.startsWith('$')) return resolveSystemToken(token);

        if (token.startsWith('row.')) {
            if (ctx.currentRowObj == null) return '';
            String f = token.substring(4);
            return formatValue(getFieldByPath(ctx.currentRowObj, f));
        }

        if (token.contains('[') && token.contains(']')) {
            return resolveFilteredPick(token, ctx);
        }

        return formatValue(getFieldByPath(ctx.rootRow, token));
    }

    private static String resolveSystemToken(String token) {
        if (token == '$User.Email') return UserInfo.getUserEmail();
        if (token == '$User.Name') return UserInfo.getName();
        if (token == '$User.Id') return UserInfo.getUserId();
        if (token == '$Now') return String.valueOf(System.now());
        if (token == '$Today') return String.valueOf(System.today());
        return '';
    }

    private static String resolveFilteredPick(String token, BuildContext ctx) {
        Matcher m = Pattern.compile('^([A-Za-z_0-9]+)\\[([^\\]]+)\\]\\.(.+)$').matcher(token);
        if (!m.matches()) return '';
        String rel = m.group(1);
        String filter = m.group(2);
        String pick = m.group(3);
        List<SObject> rows = ctx.relatedRows.get(rel);
        if (rows == null) return '';
        SObject prev = ctx.currentRowObj;
        for (SObject r : rows) {
            ctx.currentRowObj = r;
            if (evalBool(filter, ctx)) {
                ctx.currentRowObj = prev;
                return formatValue(getFieldByPath(r, pick));
            }
        }
        ctx.currentRowObj = prev;
        return '';
    }

    private static Object getFieldByPath(SObject row, String path) {
        if (row == null || String.isBlank(path)) return null;
        List<String> segs = path.split('\\.');
        SObject current = row;
        for (Integer i = 0; i < segs.size() - 1; i++) {
            Object next = safeGet(current, segs[i]);
            if (next instanceof SObject) current = (SObject) next;
            else return null;
        }
        return safeGet(current, segs[segs.size() - 1]);
    }

    private static Object safeGet(SObject row, String field) {
        try { return row.get(field); } catch (Exception e) { return null; }
    }

    private static String formatValue(Object v) {
        if (v == null) return '';
        if (v instanceof Date) return ((Date) v).format();
        if (v instanceof Datetime) return ((Datetime) v).format();
        if (v instanceof Decimal) return ((Decimal) v).toPlainString();
        return String.valueOf(v);
    }

    /* =========================================================================
     *  Image embedding
     * ========================================================================= */

    public static String resolveImageDataUri(Map<String, Object> props, BuildContext ctx) {
        String src = (String) props.get('source');
        if (src == 'staticResource') return '';
        if (src != 'relatedFile') return '';
        String rel = (String) props.get('fromRelation');
        if (String.isBlank(rel)) return '';
        List<SObject> rows = ctx.relatedRows.get(rel);
        if (rows == null || rows.isEmpty()) return '';
        String filter = (String) props.get('filterExpr');

        Id pickedRowId = null;
        SObject prev = ctx.currentRowObj;
        for (SObject r : rows) {
            ctx.currentRowObj = r;
            if (filter == null || evalBool(filter, ctx)) {
                pickedRowId = (Id) r.get('Id');
                break;
            }
        }
        ctx.currentRowObj = prev;
        if (pickedRowId == null) return '';

        return loadFirstFileAsDataUri(pickedRowId);
    }

    public static String loadFirstFileAsDataUri(Id linkedEntityId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :linkedEntityId
            LIMIT 5
        ];
        if (links.isEmpty()) return '';
        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink l : links) docIds.add(l.ContentDocumentId);
        List<ContentVersion> cvs = [
            SELECT VersionData, FileExtension, FileType
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds AND IsLatest = true
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (cvs.isEmpty() || cvs[0].VersionData == null) return '';
        String mime = mimeFor(cvs[0].FileExtension);
        return 'data:' + mime + ';base64,' + EncodingUtil.base64Encode(cvs[0].VersionData);
    }

    private static String mimeFor(String ext) {
        if (ext == null) return 'image/png';
        String e = ext.toLowerCase();
        if (e == 'jpg' || e == 'jpeg') return 'image/jpeg';
        if (e == 'gif') return 'image/gif';
        if (e == 'svg') return 'image/svg+xml';
        return 'image/png';
    }

    /* =========================================================================
     *  Expression evaluator (recursive descent)
     * ========================================================================= */

    public static Boolean evalBool(String expr, BuildContext ctx) {
        if (String.isBlank(expr)) return true;
        Parser p = new Parser(expr);
        Object v = p.parseOr(ctx);
        return toBool(v);
    }

    public static String evalString(String expr, BuildContext ctx) {
        if (String.isBlank(expr)) return '';
        Parser p = new Parser(expr);
        Object v = p.parseTernary(ctx);
        if (v == null) return '';
        return String.valueOf(v);
    }

    public static Boolean toBool(Object v) {
        if (v == null) return false;
        if (v instanceof Boolean) return (Boolean) v;
        if (v instanceof String) return String.isNotBlank((String) v);
        if (v instanceof Decimal) return ((Decimal) v) != 0;
        return true;
    }

    public class Parser {
        private String src;
        private Integer pos;

        public Parser(String s) {
            this.src = s;
            this.pos = 0;
        }

        public Object parseTernary(BuildContext ctx) {
            Object cond = parseOr(ctx);
            skipWs();
            if (peek('?')) {
                consume('?');
                skipWs();
                String trueStr = parseStringLiteral();
                skipWs();
                consume(':');
                skipWs();
                String falseStr = parseStringLiteral();
                return PdfTemplateService.toBool(cond) ? trueStr : falseStr;
            }
            return cond;
        }

        public Object parseOr(BuildContext ctx) {
            Object left = parseAnd(ctx);
            skipWs();
            while (peekKeyword('OR')) {
                consumeKeyword('OR');
                Object right = parseAnd(ctx);
                left = PdfTemplateService.toBool(left) || PdfTemplateService.toBool(right);
                skipWs();
            }
            return left;
        }

        public Object parseAnd(BuildContext ctx) {
            Object left = parseComparison(ctx);
            skipWs();
            while (peekKeyword('AND')) {
                consumeKeyword('AND');
                Object right = parseComparison(ctx);
                left = PdfTemplateService.toBool(left) && PdfTemplateService.toBool(right);
                skipWs();
            }
            return left;
        }

        public Object parseComparison(BuildContext ctx) {
            Object left = parsePrimary(ctx);
            skipWs();
            if (peekKeyword('IS_NULL')) {
                consumeKeyword('IS_NULL');
                return isNullish(left);
            }
            if (peekKeyword('IS_NOT_NULL')) {
                consumeKeyword('IS_NOT_NULL');
                return !isNullish(left);
            }
            String op = peekOp();
            if (op != null) {
                consumeOp(op);
                skipWs();
                Object right = parsePrimary(ctx);
                return compare(left, op, right);
            }
            return left;
        }

        public Object parsePrimary(BuildContext ctx) {
            skipWs();
            if (pos >= src.length()) return null;
            String c = src.substring(pos, pos + 1);
            if (c == '(') {
                pos++;
                Object v = parseOr(ctx);
                skipWs();
                consume(')');
                return v;
            }
            if (c == '\'' || c == '"') return parseStringLiteral();
            if (c == '-' || isDigit(c)) return parseNumberLiteral();
            String ident = readIdentifier();
            if (ident.equalsIgnoreCase('true')) return true;
            if (ident.equalsIgnoreCase('false')) return false;
            if (ident.equalsIgnoreCase('null')) return null;
            return PdfTemplateService.resolveToken(ident, ctx);
        }

        private String parseStringLiteral() {
            skipWs();
            String quote = src.substring(pos, pos + 1);
            if (quote != '\'' && quote != '"') {
                return readIdentifier();
            }
            pos++;
            Integer start = pos;
            while (pos < src.length() && src.substring(pos, pos + 1) != quote) {
                if (src.substring(pos, pos + 1) == '\\' && pos + 1 < src.length()) pos += 2;
                else pos++;
            }
            String s = src.substring(start, pos);
            if (pos < src.length()) pos++;
            return s.replace('\\\'', '\'').replace('\\"', '"').replace('\\\\', '\\');
        }

        private Decimal parseNumberLiteral() {
            Integer start = pos;
            if (src.substring(pos, pos + 1) == '-') pos++;
            while (pos < src.length() && (isDigit(src.substring(pos, pos + 1)) || src.substring(pos, pos + 1) == '.')) pos++;
            return Decimal.valueOf(src.substring(start, pos));
        }

        private String readIdentifier() {
            Integer start = pos;
            while (pos < src.length()) {
                String ch = src.substring(pos, pos + 1);
                if (isLetter(ch) || isDigit(ch) || ch == '_' || ch == '.' || ch == '$') pos++;
                else break;
            }
            return src.substring(start, pos);
        }

        private void skipWs() {
            while (pos < src.length() && ' \t\n\r'.contains(src.substring(pos, pos + 1))) pos++;
        }

        private Boolean peek(String c) {
            skipWs();
            return pos < src.length() && src.substring(pos, pos + 1) == c;
        }

        private void consume(String c) {
            skipWs();
            if (pos >= src.length() || src.substring(pos, pos + 1) != c) {
                throw new TemplateException('Expected ' + c + ' at position ' + pos + ' in: ' + src);
            }
            pos++;
        }

        private Boolean peekKeyword(String kw) {
            skipWs();
            Integer endPos = pos + kw.length();
            if (endPos > src.length()) return false;
            if (!src.substring(pos, endPos).equalsIgnoreCase(kw)) return false;
            if (endPos < src.length()) {
                String next = src.substring(endPos, endPos + 1);
                if (isLetter(next) || isDigit(next) || next == '_') return false;
            }
            return true;
        }

        private void consumeKeyword(String kw) {
            skipWs();
            pos += kw.length();
        }

        private String peekOp() {
            skipWs();
            if (pos + 2 <= src.length()) {
                String two = src.substring(pos, pos + 2);
                if (two == '==' || two == '!=' || two == '<=' || two == '>=') return two;
            }
            if (pos < src.length()) {
                String one = src.substring(pos, pos + 1);
                if (one == '<' || one == '>') return one;
            }
            return null;
        }

        private void consumeOp(String op) { pos += op.length(); }

        private Boolean isLetter(String c) {
            if (c == null || c.length() == 0) return false;
            Integer code = c.charAt(0);
            return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
        }

        private Boolean isDigit(String c) {
            if (c == null || c.length() == 0) return false;
            Integer code = c.charAt(0);
            return code >= 48 && code <= 57;
        }

        private Boolean isNullish(Object v) {
            if (v == null) return true;
            if (v instanceof String) return String.isBlank((String) v);
            return false;
        }

        private Boolean compare(Object left, String op, Object right) {
            if (left instanceof Decimal && right instanceof String) {
                try { right = Decimal.valueOf((String) right); } catch (Exception e) {}
            } else if (right instanceof Decimal && left instanceof String) {
                try { left = Decimal.valueOf((String) left); } catch (Exception e) {}
            }
            if (op == '==') return objectsEqual(left, right);
            if (op == '!=') return !objectsEqual(left, right);
            Decimal l = toDecimal(left);
            Decimal r = toDecimal(right);
            if (l == null || r == null) {
                String ls = String.valueOf(left);
                String rs = String.valueOf(right);
                Integer cmp = ls.compareTo(rs);
                if (op == '<')  return cmp < 0;
                if (op == '<=') return cmp <= 0;
                if (op == '>')  return cmp > 0;
                if (op == '>=') return cmp >= 0;
            }
            if (op == '<')  return l < r;
            if (op == '<=') return l <= r;
            if (op == '>')  return l > r;
            if (op == '>=') return l >= r;
            return false;
        }

        private Boolean objectsEqual(Object a, Object b) {
            if (a == null && b == null) return true;
            if (a == null || b == null) return false;
            if (a instanceof Decimal && b instanceof Decimal) return ((Decimal) a) == ((Decimal) b);
            return String.valueOf(a).equals(String.valueOf(b));
        }

        private Decimal toDecimal(Object v) {
            if (v instanceof Decimal) return (Decimal) v;
            if (v instanceof String) {
                try { return Decimal.valueOf((String) v); } catch (Exception e) { return null; }
            }
            return null;
        }
    }
}
