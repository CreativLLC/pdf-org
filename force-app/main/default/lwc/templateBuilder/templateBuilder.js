import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import MAMMOTH_URL from '@salesforce/resourceUrl/mammoth';
import PDFJS_URL from '@salesforce/resourceUrl/pdfjs';
import getContext from '@salesforce/apex/TemplateBuilderController.getContext';
import describeObject from '@salesforce/apex/TemplateBuilderController.describeObject';
import listSampleRecords from '@salesforce/apex/TemplateBuilderController.listSampleRecords';
import previewTemplate from '@salesforce/apex/TemplateBuilderController.previewTemplate';
import saveTemplate from '@salesforce/apex/TemplateBuilderController.saveTemplate';

let _idCounter = 1;
const nextId = () => `b${_idCounter++}`;

const COLUMN_COUNT_OPTIONS = [
    { label: '1 column', value: '1' },
    { label: '2 columns', value: '2' },
    { label: '3 columns', value: '3' },
    { label: '4 columns', value: '4' },
    { label: '5 columns', value: '5' },
    { label: '6 columns', value: '6' }
];
const SIGNATURE_TYPE_OPTIONS = [
    { label: 'Patient', value: 'Patient' },
    { label: 'Physician', value: 'Physician' },
    { label: 'Witness', value: 'Witness' }
];

export default class TemplateBuilder extends LightningElement {
    @api recordId;
    @api templateVersionIdOverride;

    ctx;
    blocks = [];
    selectedBlockId;
    sampleRecordOptions = [];
    selectedSampleRecordId;
    objMeta = { fields: [], relations: [] };
    fieldOptions = [];
    isLoading = false;
    isSaving = false;
    isImporting = false;
    importStatus = '';
    previewHtml = '<div style="color:#888;text-align:center;padding:40px;">Add blocks from the left palette to start building.</div>';
    previewFontStack = '';
    errorText;
    dropIndicator = null;
    fieldDropTargetId = null;
    _previewTimer;
    _draggingPaletteItem;
    _dropTarget;
    _mammothLoaded = false;
    _pdfjsLoaded = false;

    /* ---------------- lifecycle ---------------- */

    get effectiveVersionId() {
        return this.templateVersionIdOverride || this.recordId;
    }

    async connectedCallback() {
        await this.loadAll();
    }

    renderedCallback() {
        const target = this.template.querySelector('.preview-content');
        if (target && target.dataset.lastHtml !== this.previewHtml) {
            target.innerHTML = this.previewHtml;
            target.dataset.lastHtml = this.previewHtml;
        }
    }

    async loadAll() {
        this.isLoading = true;
        this.errorText = null;
        try {
            const c = await getContext({ templateVersionId: this.effectiveVersionId });
            const meta = await describeObject({ objectApi: c.targetSObject });
            const samples = await listSampleRecords({ objectApi: c.targetSObject, maxRows: 50 });

            this.objMeta = meta || { fields: [], relations: [] };
            this.fieldOptions = (this.objMeta.fields || []).map(f => ({
                label: `${f.label}  (${f.apiName})`,
                value: f.apiName
            }));
            this.sampleRecordOptions = (samples || []).map(s => ({ label: s.name, value: s.id }));
            this.selectedSampleRecordId = c.sampleRecordId
                || (samples && samples.length > 0 ? samples[0].id : null);
            this.blocks = jsonToBlocks(c.definitionJson);
            this.ctx = c;
            await this.refreshPreview();
        } catch (e) {
            this.errorText = this.errMsg(e);
            this.toast('error', 'Failed to load builder', this.errorText, 'sticky');
        } finally {
            this.isLoading = false;
        }
    }

    /* ---------------- computed ---------------- */

    get selectedBlock() {
        if (!this.selectedBlockId) return null;
        return findBlockDeep(this.blocks, this.selectedBlockId);
    }

    get hasSelection() { return !!this.selectedBlock; }

    get propsPanelTitle() {
        const b = this.selectedBlock;
        if (!b) return 'Properties';
        const labels = {
            heading: 'Heading', text: 'Text Block',
            image: 'Image', table: 'Related List Table',
            row: 'Row', spacer: 'Spacer', rule: 'Horizontal Rule'
        };
        return labels[b.type] || b.type;
    }

    get isText() { return this.selectedBlock?.type === 'text'; }
    get isHeading() { return this.selectedBlock?.type === 'heading'; }
    get isTextOrHeading() { return this.isText || this.isHeading; }
    get isImage() { return this.selectedBlock?.type === 'image'; }
    get isTable() { return this.selectedBlock?.type === 'table'; }
    get isRow() { return this.selectedBlock?.type === 'row'; }
    get isSpacer() { return this.selectedBlock?.type === 'spacer'; }

    get spansForRender() {
        const b = this.selectedBlock;
        if (!b || !this.isTextOrHeading || !Array.isArray(b.props?.spans)) return [];
        return b.props.spans.map((s, i) => ({
            key: `${b.id}_span_${i}`,
            index: String(i),
            isText: s.kind === 'text',
            isToken: s.kind === 'token',
            value: s.value,
            isEmptyToken: s.kind === 'token' && !s.value,
            boldVariant: s.bold ? 'brand' : 'border',
            italicVariant: s.italic ? 'brand' : 'border'
        }));
    }

    get signatureTypeOptions() { return SIGNATURE_TYPE_OPTIONS; }
    get columnCountOptions() { return COLUMN_COUNT_OPTIONS; }
    get selectedColumnCountStr() {
        return String(this.selectedBlock?.props?.columnCount || 2);
    }

    get previewStyle() {
        const fontStack = this.previewFontStack || "'Helvetica Neue', Arial, sans-serif";
        return `font-family: ${fontStack}; font-size: 11pt; color: #222; padding: 0.5in; background: #fff;`;
    }

    get pdfUrl() {
        if (!this.ctx?.templateVersionId || !this.selectedSampleRecordId) return null;
        return `/apex/DocumentRender?templateVersionId=${this.ctx.templateVersionId}&recordId=${this.selectedSampleRecordId}`;
    }

    get rootDropIndicatorAtStart() {
        return this.dropIndicator?.containerKey === 'root' && this.dropIndicator?.index === 0;
    }

    get blocksForRender() {
        return this.blocks.map((b, idx) => {
            const dec = this.decorateBlock(b);
            dec.showDropIndicatorAfter =
                this.dropIndicator?.containerKey === 'root' && this.dropIndicator?.index === idx + 1;
            dec.dropAfterKey = b.id + '_drop';
            return dec;
        });
    }

    decorateBlock(b) {
        const isSelected = b.id === this.selectedBlockId;
        const isFieldTarget = b.id === this.fieldDropTargetId;
        const dec = {
            ...b,
            isHeading: b.type === 'heading',
            isText: b.type === 'text',
            isImage: b.type === 'image',
            isTable: b.type === 'table',
            isRow: b.type === 'row',
            isSpacer: b.type === 'spacer',
            isRule: b.type === 'rule',
            isSelected,
            cssClass: 'canvas-block'
                + (isSelected ? ' canvas-block_selected' : '')
                + (isFieldTarget ? ' canvas-block_field-drop' : ''),
            summary: blockSummary(b)
        };
        if (b.type === 'row') {
            const colWidth = `${(100 / (b.props.columnCount || 1)).toFixed(2)}%`;
            const indicatorKey = (colId) => `col:${colId}`;
            dec.columnsForRender = (b.columns || []).map(col => {
                const colChildren = (col.children || []);
                const childrenForRender = colChildren.map((c, ci) => {
                    const cd = this.decorateBlock(c);
                    cd.showDropIndicatorAfter =
                        this.dropIndicator?.containerKey === indicatorKey(col.id) &&
                        this.dropIndicator?.index === ci + 1;
                    cd.dropAfterKey = c.id + '_drop';
                    return cd;
                });
                return {
                    id: col.id,
                    widthStyle: `width: ${colWidth};`,
                    hasChildren: colChildren.length > 0,
                    childrenForRender,
                    showDropIndicatorAtStart:
                        this.dropIndicator?.containerKey === indicatorKey(col.id) &&
                        this.dropIndicator?.index === 0,
                    dropStartKey: col.id + '_drop_start'
                };
            });
        }
        return dec;
    }

    /* ---------------- palette: add via click ---------------- */

    handleAddHeading()    { this.appendTopLevelBlock(makeHeading()); }
    handleAddText()       { this.appendTopLevelBlock(makeText()); }
    handleAddRow()        { this.appendTopLevelBlock(makeRow(2)); }
    handleAddImage()      { this.appendTopLevelBlock(makeImage()); }
    handleAddTable()      { this.appendTopLevelBlock(makeSignaturesTable()); }
    handleAddSpacer()     { this.appendTopLevelBlock(makeSpacer()); }
    handleAddRule()       { this.appendTopLevelBlock(makeRule()); }

    handleAddField(event) {
        const fieldApi = event.currentTarget.dataset.field;
        if (!fieldApi) return;
        const f = (this.objMeta?.fields || []).find(x => x.apiName === fieldApi);
        this.appendTopLevelBlock(makeMerge(f ? f.label : fieldApi, fieldApi));
    }

    /* ---------------- drag ---------------- */

    handlePaletteDragStart(event) {
        const kind = event.currentTarget.dataset.kind;
        const fieldApi = event.currentTarget.dataset.field || '';
        this._draggingPaletteItem = { kind, fieldApi };
        try {
            event.dataTransfer.setData('text/plain', JSON.stringify(this._draggingPaletteItem));
            event.dataTransfer.effectAllowed = 'copy';
        } catch (_e) { /* some browsers restrict */ }
    }

    handleBlockDragStart(event) {
        event.stopPropagation();
        const blockId = event.currentTarget.dataset.blockId;
        if (!blockId) return;
        this._draggingPaletteItem = { kind: 'move', blockId };
        try {
            event.dataTransfer.setData('text/plain', JSON.stringify(this._draggingPaletteItem));
            event.dataTransfer.effectAllowed = 'move';
        } catch (_e) { /* ignore */ }
    }

    /**
     * Fires when ANY drag ends (successful drop, escape, dropped outside a zone).
     * Always clear the indicator + cached payload so nothing stays "stuck" visually.
     */
    handleDragEnd() {
        this._draggingPaletteItem = null;
        this.fieldDropTargetId = null;
        this.clearDropIndicator();
    }

    /* ---------------- Document upload (DOCX / PDF -> blocks) ---------------- */

    handleUploadClick() {
        const input = this.template.querySelector('input.file-import-input');
        if (input) input.click();
    }

    async handleFileSelected(event) {
        let stage = 'init';
        let file;
        try {
            stage = 'reading file from input';
            file = event.target.files?.[0];
            event.target.value = '';
            if (!file) {
                // eslint-disable-next-line no-console
                console.log('[BUILDER] no file selected');
                return;
            }
            // eslint-disable-next-line no-console
            console.log('[BUILDER] file picked:', file.name, file.type, file.size, 'bytes');

            if (this.blocks.length > 0) {
                stage = 'confirm';
                const ok = window.confirm(
                    `Import "${file.name}"?\n\nThis will REPLACE the current canvas with content extracted from the document.`
                );
                // eslint-disable-next-line no-console
                console.log('[BUILDER] confirm result:', ok);
                if (!ok) return;
            }

            this.isImporting = true;
            this.importStatus = `Reading ${file.name}…`;
            this.errorText = null;

            stage = 'reading arrayBuffer';
            const arrayBuffer = await file.arrayBuffer();
            // eslint-disable-next-line no-console
            console.log('[BUILDER] arrayBuffer bytes:', arrayBuffer?.byteLength);

            const ext = (file.name.split('.').pop() || '').toLowerCase();
            let newBlocks;
            if (ext === 'docx') {
                stage = 'loading mammoth';
                this.importStatus = 'Loading DOCX parser…';
                await this.ensureMammothLoaded();
                stage = 'parsing docx';
                this.importStatus = 'Extracting text from DOCX…';
                newBlocks = await this.parseDocx(arrayBuffer);
            } else if (ext === 'pdf') {
                stage = 'loading pdf.js';
                this.importStatus = 'Loading PDF parser…';
                await this.ensurePdfJsLoaded();
                stage = 'parsing pdf';
                this.importStatus = 'Extracting text from PDF…';
                newBlocks = await this.parsePdf(arrayBuffer);
            } else {
                throw new Error(`Unsupported file type: .${ext}. Use .docx or .pdf.`);
            }
            // eslint-disable-next-line no-console
            console.log('[BUILDER] parsed', newBlocks?.length, 'blocks');

            if (!newBlocks || newBlocks.length === 0) {
                throw new Error('No content extracted from the document.');
            }

            stage = 'applying blocks';
            this.blocks = newBlocks;
            this.selectedBlockId = null;
            const matched = this._lastAutoMatchCount || 0;
            const matchedSuffix = matched > 0
                ? ` Auto-matched ${matched} merge field${matched === 1 ? '' : 's'} by label.`
                : '';
            this.toast('success', 'Document imported',
                `Extracted ${newBlocks.length} block${newBlocks.length === 1 ? '' : 's'} from ${file.name}.${matchedSuffix} Drop fields onto the text blocks to fill remaining slots.`);
            this.schedulePreview();
        } catch (e) {
            /* eslint-disable no-console */
            console.error(`[BUILDER] Import failed at stage [${stage}]`);
            console.error('[BUILDER]   raw error:', e);
            console.error('[BUILDER]   typeof:', typeof e);
            console.error('[BUILDER]   String(e):', String(e));
            try { console.error('[BUILDER]   JSON.stringify:', JSON.stringify(e)); } catch (_jse) { /* ignore */ }
            if (e && typeof e === 'object') {
                console.error('[BUILDER]   keys:', Object.keys(e));
                console.error('[BUILDER]   stack:', e.stack);
            }
            /* eslint-enable no-console */
            const msg = `Failed at stage "${stage}": ${this.detailedErrMsg(e)}`;
            this.toast('error', 'Import failed', msg, 'sticky');
        } finally {
            this.isImporting = false;
            this.importStatus = '';
        }
    }

    detailedErrMsg(e) {
        if (!e) return 'Unknown error (no error object).';
        if (typeof e === 'string') return e;
        const parts = [];
        if (e.name) parts.push(e.name);
        if (e.message) parts.push(e.message);
        if (e.body?.message) parts.push(e.body.message);
        const out = parts.join(': ');
        if (out) return out + ' (see browser console for full stack)';
        try { return JSON.stringify(e) + ' (see browser console)'; } catch (_e) {
            return 'Error has no readable message — check browser console.';
        }
    }

    /**
     * LWS-safe lookup of a global library. `window` is the only reliable global
     * inside the LWC sandbox; `globalThis` is shadowed/undefined in some orgs.
     */
    findGlobal(name) {
        if (typeof window !== 'undefined' && window[name]) return window[name];
        return null;
    }

    async ensureMammothLoaded() {
        if (this._mammothLoaded && this.findGlobal('mammoth')) return;
        // Known LWC bug salesforce/lwc#2640: loadScript can reject with `undefined`
        // even when the script DID actually load. So we catch+ignore the rejection
        // and check the global afterward; only treat as failure if the global is missing.
        try {
            await loadScript(this, MAMMOTH_URL);
        } catch (loadErr) {
            // eslint-disable-next-line no-console
            console.warn('[BUILDER] loadScript(mammoth) rejected (may be benign LWC bug #2640):', loadErr);
        }
        const lib = this.findGlobal('mammoth');
        // eslint-disable-next-line no-console
        console.log('[BUILDER] mammoth probe', { found: !!lib, type: typeof lib });
        if (!lib) {
            throw new Error('mammoth.js did not register on window after script load. ' +
                'Lightning Web Security may have blocked the script.');
        }
        this._mammothLoaded = true;
    }

    async ensurePdfJsLoaded() {
        if (this._pdfjsLoaded && this.findGlobal('pdfjsLib')) return;
        try {
            await loadScript(this, PDFJS_URL + '/pdf.min.js');
        } catch (loadErr) {
            // eslint-disable-next-line no-console
            console.warn('[BUILDER] loadScript(pdf.js) rejected (may be benign LWC bug #2640):', loadErr);
        }
        const lib = this.findGlobal('pdfjsLib');
        // eslint-disable-next-line no-console
        console.log('[BUILDER] pdfjs probe', {
            found: !!lib,
            type: typeof lib,
            keys: lib ? Object.keys(lib).slice(0, 10) : null
        });
        if (!lib) {
            throw new Error('pdf.js did not register on window after script load. ' +
                'Lightning Web Security may have blocked it. PDF import is unsupported in this org; use DOCX.');
        }
        this._pdfjsLoaded = true;
    }

    async parseDocx(arrayBuffer) {
        const mammoth = this.findGlobal('mammoth');
        if (!mammoth) {
            throw new Error('mammoth library did not register on window after loadScript. ' +
                'This usually means Lightning Web Security blocked it.');
        }
        if (typeof mammoth.convertToHtml !== 'function') {
            throw new Error('mammoth loaded but convertToHtml() is missing — version mismatch?');
        }
        const result = await mammoth.convertToHtml({ arrayBuffer });
        // eslint-disable-next-line no-console
        if (result.messages?.length) console.log('[BUILDER] mammoth messages:', result.messages);
        let blocks = htmlStringToBlocks(result.value || '');
        // Two-pass: try to auto-match empty token spans to fields on the target object
        const matched = autoMatchTokens(blocks, this.objMeta?.fields || []);
        blocks = matched.blocks;
        if (matched.matchCount > 0) {
            // eslint-disable-next-line no-console
            console.log('[BUILDER] auto-matched', matched.matchCount, 'fields from labels');
            this._lastAutoMatchCount = matched.matchCount;
        } else {
            this._lastAutoMatchCount = 0;
        }
        return blocks;
    }

    async parsePdf(arrayBuffer) {
        const pdfjsLib = window.pdfjsLib || globalThis.pdfjsLib;
        if (!pdfjsLib) {
            throw new Error('pdf.js library did not register on window after loadScript.');
        }
        // Force sync (no Web Worker) — Lightning Web Security blocks the worker URL.
        // Slower for large PDFs, but reliable. Two ways to disable: disableWorker option
        // and a no-op workerSrc. Set both to be safe across pdf.js versions.
        if (pdfjsLib.GlobalWorkerOptions) {
            pdfjsLib.GlobalWorkerOptions.workerSrc = '';
        }
        const loadingTask = pdfjsLib.getDocument({
            data: arrayBuffer,
            disableWorker: true,
            useWorkerFetch: false,
            isEvalSupported: false,    // skip the Function-constructor JPEG decode path
            disableFontFace: true,     // avoid more dynamic-code paths LWS may block
            useSystemFonts: true
        });
        const pdf = await loadingTask.promise;
        const blocks = [];
        for (let pageNum = 1; pageNum <= pdf.numPages; pageNum++) {
            const page = await pdf.getPage(pageNum);
            const textContent = await page.getTextContent();
            const lines = groupItemsIntoLines(textContent.items);
            for (const line of lines) {
                const text = line.trim();
                if (!text) continue;
                blocks.push(makeTextFromString(text));
            }
            if (pageNum < pdf.numPages) {
                blocks.push(makeSpacer());
            }
        }
        return blocks;
    }

    /* ---------------- field drops onto text/heading blocks ---------------- */

    handleBlockDragOver(event) {
        // Only accept field drops here; let other drag types bubble to canvas/column.
        if (this._draggingPaletteItem?.kind !== 'field') return;
        const blockId = event.currentTarget.dataset.blockId;
        const block = findBlockDeep(this.blocks, blockId);
        if (!block || (block.type !== 'text' && block.type !== 'heading')) return;
        event.preventDefault();
        event.stopPropagation();
        try { event.dataTransfer.dropEffect = 'copy'; } catch (_e) { /* ignore */ }
        if (this.fieldDropTargetId !== blockId) this.fieldDropTargetId = blockId;
        // Hide the line indicator while we're targeting a block — would be confusing
        if (this.dropIndicator) this.dropIndicator = null;
    }

    handleBlockDrop(event) {
        if (this._draggingPaletteItem?.kind !== 'field') return;
        const blockId = event.currentTarget.dataset.blockId;
        const block = findBlockDeep(this.blocks, blockId);
        if (!block || (block.type !== 'text' && block.type !== 'heading')) return;
        event.preventDefault();
        event.stopPropagation();
        const fieldApi = this._draggingPaletteItem.fieldApi;
        this.appendTokenSpanToBlock(blockId, fieldApi);
        this.fieldDropTargetId = null;
        this._draggingPaletteItem = null;
        this.clearDropIndicator();
    }

    handleBlockDragLeave(event) {
        if (event.currentTarget === event.target) {
            this.fieldDropTargetId = null;
        }
    }

    appendTokenSpanToBlock(blockId, fieldApi) {
        this.blocks = updateBlockDeep(this.blocks, blockId, b => {
            const spans = [...(b.props.spans || [])];
            // If the block already has an EMPTY token span (placeholder from a
            // "Label: ___" import), fill the LAST one instead of appending.
            // This makes dropping a field on an imported labeled block "just work".
            for (let i = spans.length - 1; i >= 0; i--) {
                if (spans[i].kind === 'token' && !spans[i].value) {
                    spans[i] = { ...spans[i], value: fieldApi };
                    return { ...b, props: { ...b.props, spans } };
                }
            }
            spans.push({ kind: 'token', value: fieldApi });
            return { ...b, props: { ...b.props, spans } };
        });
        this.selectedBlockId = blockId;
        this.schedulePreview();
    }

    /* ---------------- span editor handlers ---------------- */

    handleSpanTextChange(event) {
        const idx = parseInt(event.target.dataset.spanIndex, 10);
        this.replaceSpan(idx, { kind: 'text', value: event.target.value });
    }

    handleSpanTokenChange(event) {
        const idx = parseInt(event.target.dataset.spanIndex, 10);
        this.replaceSpan(idx, { kind: 'token', value: event.detail.value });
    }

    handleSpanDelete(event) {
        const idx = parseInt(event.currentTarget.dataset.spanIndex, 10);
        this.removeSpan(idx);
    }

    handleSpanMoveUp(event) {
        const idx = parseInt(event.currentTarget.dataset.spanIndex, 10);
        this.moveSpan(idx, -1);
    }

    handleSpanMoveDown(event) {
        const idx = parseInt(event.currentTarget.dataset.spanIndex, 10);
        this.moveSpan(idx, +1);
    }

    handleAddTextSpan() {
        this.appendSpan({ kind: 'text', value: 'New text' });
    }

    handleAddTokenSpan(event) {
        const value = event.detail.value;
        if (!value) return;
        this.appendSpan({ kind: 'token', value });
        // Reset combobox so the user can pick the same field again
        event.target.value = null;
    }

    replaceSpan(idx, span) {
        const block = this.selectedBlock;
        if (!block) return;
        const spans = [...(block.props.spans || [])];
        spans[idx] = span;
        this.applySpans(block.id, spans);
    }

    removeSpan(idx) {
        const block = this.selectedBlock;
        if (!block) return;
        const spans = [...(block.props.spans || [])];
        spans.splice(idx, 1);
        this.applySpans(block.id, spans);
    }

    moveSpan(idx, delta) {
        const block = this.selectedBlock;
        if (!block) return;
        const spans = [...(block.props.spans || [])];
        const target = idx + delta;
        if (target < 0 || target >= spans.length) return;
        [spans[idx], spans[target]] = [spans[target], spans[idx]];
        this.applySpans(block.id, spans);
    }

    appendSpan(span) {
        const block = this.selectedBlock;
        if (!block) return;
        const spans = [...(block.props.spans || []), span];
        this.applySpans(block.id, spans);
    }

    handleSpanToggleBold(event) {
        const idx = parseInt(event.currentTarget.dataset.spanIndex, 10);
        this.toggleSpanFlag(idx, 'bold');
    }

    handleSpanToggleItalic(event) {
        const idx = parseInt(event.currentTarget.dataset.spanIndex, 10);
        this.toggleSpanFlag(idx, 'italic');
    }

    toggleSpanFlag(idx, flag) {
        const block = this.selectedBlock;
        if (!block) return;
        const spans = [...(block.props.spans || [])];
        if (idx < 0 || idx >= spans.length) return;
        spans[idx] = { ...spans[idx], [flag]: !spans[idx][flag] };
        this.applySpans(block.id, spans);
    }

    applySpans(blockId, spans) {
        this.blocks = updateBlockDeep(this.blocks, blockId, b => ({
            ...b,
            props: { ...b.props, spans }
        }));
        this.schedulePreview();
    }

    handleCanvasDragOver(event) {
        event.preventDefault();
        try {
            // dropEffect must be compatible with the drag source's effectAllowed.
            // Block moves use 'move'; palette additions use 'copy'.
            event.dataTransfer.dropEffect =
                this._draggingPaletteItem?.kind === 'move' ? 'move' : 'copy';
        } catch (_e) { /* ignore */ }
        const idx = this.computeDropIndex(event, '.canvas');
        if (this._dropTarget?.container !== 'root' || this._dropTarget?.index !== idx) {
            this._dropTarget = { container: 'root', index: idx };
            this.dropIndicator = { containerKey: 'root', index: idx };
        }
    }

    handleCanvasDrop(event) {
        event.preventDefault();
        event.stopPropagation();
        const payload = this.readDragPayload(event);
        this.clearDropIndicator();
        if (!payload) return;
        const insertIndex = this.computeDropIndex(event, '.canvas');
        if (payload.kind === 'move') {
            this.moveBlockTo(payload.blockId, { container: 'root', index: insertIndex });
            return;
        }
        const block = makeBlockFor(payload.kind, payload.fieldApi, this.objMeta);
        if (!block) return;
        this.insertTopLevelBlock(block, insertIndex);
    }

    handleCanvasDragLeave(event) {
        // Only clear if we leave the canvas itself, not a child element
        if (event.currentTarget === event.target) {
            this.clearDropIndicator();
        }
    }

    handleColumnDragOver(event) {
        event.preventDefault();
        event.stopPropagation();
        try {
            event.dataTransfer.dropEffect =
                this._draggingPaletteItem?.kind === 'move' ? 'move' : 'copy';
        } catch (_e) { /* ignore */ }
        const colId = event.currentTarget.dataset.colId;
        const idx = this.computeColumnDropIndex(event, colId);
        const key = `col:${colId}`;
        if (this._dropTarget?.containerKey !== key || this._dropTarget?.index !== idx) {
            this._dropTarget = { containerKey: key, index: idx };
            this.dropIndicator = { containerKey: key, index: idx };
        }
    }

    handleColumnDrop(event) {
        event.preventDefault();
        event.stopPropagation();
        const payload = this.readDragPayload(event);
        this.clearDropIndicator();
        if (!payload) return;
        const colId = event.currentTarget.dataset.colId;
        const rowId = event.currentTarget.dataset.rowId;
        const insertIndex = this.computeColumnDropIndex(event, colId);
        if (payload.kind === 'move') {
            // Disallow moving a row into a column
            const sourceBlock = findBlockDeep(this.blocks, payload.blockId);
            if (sourceBlock?.type === 'row') {
                this.toast('warning', 'Cannot nest rows', 'Rows can only live at the top level.');
                return;
            }
            this.moveBlockTo(payload.blockId, {
                container: 'column', rowId, colId, index: insertIndex
            });
            return;
        }
        if (payload.kind === 'row') {
            this.toast('warning', 'Cannot nest rows', 'Rows can only live at the top level.');
            return;
        }
        const block = makeBlockFor(payload.kind, payload.fieldApi, this.objMeta);
        if (!block) return;
        this.insertIntoColumnAt(rowId, colId, block, insertIndex);
    }

    handleColumnDragLeave(event) {
        if (event.currentTarget === event.target) {
            this.clearDropIndicator();
        }
    }

    clearDropIndicator() {
        this._dropTarget = null;
        this.dropIndicator = null;
    }

    readDragPayload(event) {
        let payload = this._draggingPaletteItem;
        if (!payload) {
            try { payload = JSON.parse(event.dataTransfer.getData('text/plain')); } catch (_e) { return null; }
        }
        this._draggingPaletteItem = null;
        return payload;
    }

    computeDropIndex(event, containerSelector) {
        const container = this.template.querySelector(containerSelector);
        if (!container) return this.blocks.length;
        const blockEls = container.querySelectorAll(':scope > .canvas-block-wrap');
        for (let i = 0; i < blockEls.length; i++) {
            const r = blockEls[i].getBoundingClientRect();
            if (event.clientY < r.top + r.height / 2) return i;
        }
        return blockEls.length;
    }

    computeColumnDropIndex(event, colId) {
        const colEl = this.template.querySelector(`[data-col-id="${colId}"]`);
        if (!colEl) return 0;
        const blockEls = colEl.querySelectorAll(':scope > .canvas-block-wrap');
        for (let i = 0; i < blockEls.length; i++) {
            const r = blockEls[i].getBoundingClientRect();
            if (event.clientY < r.top + r.height / 2) return i;
        }
        return blockEls.length;
    }

    /* ---------------- block ops (top-level + nested) ---------------- */

    appendTopLevelBlock(b) {
        this.blocks = [...this.blocks, b];
        this.selectedBlockId = b.id;
        this.schedulePreview();
    }

    insertTopLevelBlock(b, idx) {
        const arr = [...this.blocks];
        arr.splice(idx, 0, b);
        this.blocks = arr;
        this.selectedBlockId = b.id;
        this.schedulePreview();
    }

    insertIntoColumn(rowId, colId, b) {
        this.insertIntoColumnAt(rowId, colId, b, Number.MAX_SAFE_INTEGER);
    }

    insertIntoColumnAt(rowId, colId, b, index) {
        const newBlocks = this.blocks.map(blk => {
            if (blk.id !== rowId || blk.type !== 'row') return blk;
            const newCols = (blk.columns || []).map(col => {
                if (col.id !== colId) return col;
                const arr = [...(col.children || [])];
                const idx = (index < 0 || index > arr.length) ? arr.length : index;
                arr.splice(idx, 0, b);
                return { ...col, children: arr };
            });
            return { ...blk, columns: newCols };
        });
        this.blocks = newBlocks;
        this.selectedBlockId = b.id;
        this.schedulePreview();
    }

    moveBlockTo(blockId, target) {
        const sourceLocation = findBlockLocation(this.blocks, blockId);
        if (!sourceLocation) return;

        // Adjust target index for same-container moves where the source sits before the drop position.
        let targetIndex = target.index;
        const sameContainer =
            sourceLocation.container === target.container &&
            sourceLocation.rowId === target.rowId &&
            sourceLocation.colId === target.colId;
        if (sameContainer && sourceLocation.index < targetIndex) {
            targetIndex -= 1;
        }

        const { block, blocks: blocksMinusSource } = extractBlockDeep(this.blocks, blockId);
        if (!block) return;

        let newBlocks;
        if (target.container === 'root') {
            newBlocks = [...blocksMinusSource];
            const idx = Math.max(0, Math.min(targetIndex, newBlocks.length));
            newBlocks.splice(idx, 0, block);
        } else {
            newBlocks = blocksMinusSource.map(blk => {
                if (blk.id !== target.rowId || blk.type !== 'row') return blk;
                return {
                    ...blk,
                    columns: (blk.columns || []).map(col => {
                        if (col.id !== target.colId) return col;
                        const arr = [...(col.children || [])];
                        const idx = Math.max(0, Math.min(targetIndex, arr.length));
                        arr.splice(idx, 0, block);
                        return { ...col, children: arr };
                    })
                };
            });
        }
        this.blocks = newBlocks;
        this.selectedBlockId = blockId;
        this.schedulePreview();
    }

    handleBlockClick(event) {
        event.stopPropagation();
        this.selectedBlockId = event.currentTarget.dataset.blockId;
    }

    handleBlockDelete(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.blockId;
        this.blocks = removeBlockDeep(this.blocks, id);
        if (this.selectedBlockId === id) this.selectedBlockId = null;
        this.schedulePreview();
    }

    handleBlockMoveUp(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.blockId;
        this.blocks = moveBlockDeep(this.blocks, id, -1);
        this.schedulePreview();
    }

    handleBlockMoveDown(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.blockId;
        this.blocks = moveBlockDeep(this.blocks, id, +1);
        this.schedulePreview();
    }

    /* ---------------- properties panel ---------------- */

    handlePropertyChange(event) {
        const block = this.selectedBlock;
        if (!block) return;
        const key = event.target.dataset.key;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.blocks = updateBlockDeep(this.blocks, block.id, b => ({
            ...b,
            props: { ...b.props, [key]: value }
        }));
        this.schedulePreview();
    }

    handleColumnCountChange(event) {
        const block = this.selectedBlock;
        if (!block || block.type !== 'row') return;
        const newCount = parseInt(event.detail.value, 10);
        if (Number.isNaN(newCount) || newCount < 1) return;
        this.blocks = updateBlockDeep(this.blocks, block.id, b => {
            const cols = b.columns || [];
            let newCols;
            if (newCount > cols.length) {
                newCols = [...cols];
                for (let i = cols.length; i < newCount; i++) {
                    newCols.push({ id: nextId(), children: [] });
                }
            } else {
                // Shrinking: keep first N-1 columns intact, merge rest into the last surviving column
                newCols = cols.slice(0, newCount).map(c => ({ ...c, children: [...c.children] }));
                const overflow = cols.slice(newCount).flatMap(c => c.children);
                if (overflow.length && newCols.length > 0) {
                    newCols[newCols.length - 1].children.push(...overflow);
                }
            }
            return { ...b, props: { ...b.props, columnCount: newCount }, columns: newCols };
        });
        this.schedulePreview();
    }

    /* ---------------- save / preview ---------------- */

    async handleSave() {
        if (!this.ctx?.templateVersionId) return;
        this.isSaving = true;
        try {
            const json = JSON.stringify(blocksToJson(this.blocks, this.ctx), null, 2);
            await saveTemplate({
                templateVersionId: this.ctx.templateVersionId,
                defJson: json,
                sampleRecordId: this.selectedSampleRecordId
            });
            this.toast('success', 'Saved', 'Template definition updated.');
            await this.refreshPreview();
        } catch (e) {
            this.toast('error', 'Save failed', this.errMsg(e), 'sticky');
        } finally {
            this.isSaving = false;
        }
    }

    schedulePreview() {
        clearTimeout(this._previewTimer);
        this._previewTimer = setTimeout(() => this.refreshPreview(), 150);
    }

    async refreshPreview() {
        if (!this.ctx || !this.selectedSampleRecordId) return;
        try {
            const json = JSON.stringify(blocksToJson(this.blocks, this.ctx));
            const result = await previewTemplate({
                defJson: json,
                targetSObject: this.ctx.targetSObject,
                sampleRecordId: this.selectedSampleRecordId
            });
            this.previewHtml = result.html || '<div style="color:#888;text-align:center;padding:40px;">Empty preview.</div>';
            this.previewFontStack = result.fontStack;
            this.errorText = null;
            // Write to the DOM directly. The .preview-content div uses lwc:dom="manual"
            // so no template binding observes previewHtml — relying on renderedCallback
            // alone misses updates when ONLY previewHtml changes (no other reactive
            // properties shifted). This call guarantees the preview reflects every change.
            this.applyPreviewToDom();
        } catch (e) {
            this.errorText = this.errMsg(e);
        }
    }

    applyPreviewToDom() {
        const target = this.template.querySelector('.preview-content');
        if (target) {
            target.innerHTML = this.previewHtml || '';
            if (target.dataset) target.dataset.lastHtml = this.previewHtml || '';
        }
    }

    handleSampleChange(event) {
        this.selectedSampleRecordId = event.detail.value;
        this.refreshPreview();
    }

    handleOpenPdf() {
        if (this.pdfUrl) window.open(this.pdfUrl, '_blank');
    }

    /* ---------------- helpers ---------------- */

    toast(variant, title, message, mode = 'dismissable') {
        this.dispatchEvent(new ShowToastEvent({ variant, title, message, mode }));
    }

    errMsg(e) {
        return e?.body?.message ?? e?.message ?? 'Unknown error';
    }
}

/* ============================================================
 *  Block factories
 * ============================================================ */

function makeHeading() {
    return {
        id: nextId(),
        type: 'heading',
        props: {
            spans: [{ kind: 'text', value: 'Heading' }],
            align: 'center', size: '20pt', bold: true
        }
    };
}
function makeText() {
    return {
        id: nextId(),
        type: 'text',
        props: {
            spans: [{ kind: 'text', value: 'Plain text. Click to edit.' }],
            align: 'left', size: '11pt', bold: false
        }
    };
}
function makeFieldText(label, token) {
    return {
        id: nextId(),
        type: 'text',
        props: {
            spans: [
                { kind: 'text', value: (label || 'Field') + ': ' },
                { kind: 'token', value: token }
            ],
            align: 'left', size: '11pt', bold: true
        }
    };
}
function makeRow(columnCount) {
    const n = Math.max(1, Math.min(6, columnCount || 2));
    const columns = [];
    for (let i = 0; i < n; i++) columns.push({ id: nextId(), children: [] });
    return { id: nextId(), type: 'row', props: { columnCount: n }, columns };
}
function makeImage() {
    return { id: nextId(), type: 'image', props: { signatureType: 'Physician', width: '180px', height: '50px' } };
}
function makeSignaturesTable() {
    return {
        id: nextId(),
        type: 'table',
        props: {
            relation: 'Signatures__r',
            columns: [
                { header: 'Type',      token: 'row.Signature_Type__c', width: '20%' },
                { header: 'Signed By', token: 'row.Signed_By__c',      width: '40%' },
                { header: 'Signed At', token: 'row.Signed_At__c',      width: '40%' }
            ]
        }
    };
}
function makeSpacer() { return { id: nextId(), type: 'spacer', props: { height: '12px' } }; }
function makeRule()   { return { id: nextId(), type: 'rule', props: {} }; }

function makeBlockFor(kind, fieldApi, objMeta) {
    switch (kind) {
        case 'heading': return makeHeading();
        case 'text': return makeText();
        case 'row': return makeRow(2);
        case 'image': return makeImage();
        case 'table': return makeSignaturesTable();
        case 'spacer': return makeSpacer();
        case 'rule': return makeRule();
        case 'field': {
            const f = (objMeta?.fields || []).find(x => x.apiName === fieldApi);
            return makeFieldText(f ? f.label : fieldApi, fieldApi);
        }
        default: return null;
    }
}

/* ============================================================
 *  Recursive block ops (handle nested blocks inside row columns)
 * ============================================================ */

function findBlockDeep(blocks, id) {
    for (const b of blocks) {
        if (b.id === id) return b;
        if (b.type === 'row' && Array.isArray(b.columns)) {
            for (const col of b.columns) {
                const found = findBlockDeep(col.children || [], id);
                if (found) return found;
            }
        }
    }
    return null;
}

function removeBlockDeep(blocks, id) {
    return blocks
        .filter(b => b.id !== id)
        .map(b => {
            if (b.type !== 'row') return b;
            return {
                ...b,
                columns: (b.columns || []).map(col => ({
                    ...col,
                    children: removeBlockDeep(col.children || [], id)
                }))
            };
        });
}

function updateBlockDeep(blocks, id, updater) {
    return blocks.map(b => {
        if (b.id === id) return updater(b);
        if (b.type === 'row') {
            return {
                ...b,
                columns: (b.columns || []).map(col => ({
                    ...col,
                    children: updateBlockDeep(col.children || [], id, updater)
                }))
            };
        }
        return b;
    });
}

function findBlockLocation(blocks, id) {
    const topIdx = blocks.findIndex(b => b.id === id);
    if (topIdx !== -1) return { container: 'root', index: topIdx };
    for (const b of blocks) {
        if (b.type !== 'row') continue;
        for (const col of (b.columns || [])) {
            const idx = (col.children || []).findIndex(c => c.id === id);
            if (idx !== -1) return { container: 'column', rowId: b.id, colId: col.id, index: idx };
        }
    }
    return null;
}

function extractBlockDeep(blocks, id) {
    let extracted = null;
    const topIdx = blocks.findIndex(b => b.id === id);
    if (topIdx !== -1) {
        extracted = blocks[topIdx];
        const newBlocks = [...blocks];
        newBlocks.splice(topIdx, 1);
        return { block: extracted, blocks: newBlocks };
    }
    const newBlocks = blocks.map(b => {
        if (extracted || b.type !== 'row') return b;
        const newCols = (b.columns || []).map(col => {
            if (extracted) return col;
            const idx = (col.children || []).findIndex(c => c.id === id);
            if (idx === -1) return col;
            extracted = col.children[idx];
            const newChildren = [...col.children];
            newChildren.splice(idx, 1);
            return { ...col, children: newChildren };
        });
        return { ...b, columns: newCols };
    });
    return { block: extracted, blocks: newBlocks };
}

function moveBlockDeep(blocks, id, delta) {
    // Try top level first
    const idx = blocks.findIndex(b => b.id === id);
    if (idx !== -1) {
        const target = idx + delta;
        if (target < 0 || target >= blocks.length) return blocks;
        const arr = [...blocks];
        [arr[idx], arr[target]] = [arr[target], arr[idx]];
        return arr;
    }
    // Recurse into row columns
    return blocks.map(b => {
        if (b.type !== 'row') return b;
        let touched = false;
        const newCols = (b.columns || []).map(col => {
            const ci = (col.children || []).findIndex(c => c.id === id);
            if (ci === -1) return col;
            touched = true;
            const target = ci + delta;
            if (target < 0 || target >= col.children.length) return col;
            const arr = [...col.children];
            [arr[ci], arr[target]] = [arr[target], arr[ci]];
            return { ...col, children: arr };
        });
        return touched ? { ...b, columns: newCols } : b;
    });
}

function spansToSummaryString(spans) {
    return (spans || [])
        .map(s => s.kind === 'token' ? `{{${s.value}}}` : (s.value || ''))
        .join('');
}

function blockSummary(b) {
    switch (b.type) {
        case 'heading':    return `Heading: "${spansToSummaryString(b.props?.spans).substring(0, 80)}"`;
        case 'text': {
            const txt = spansToSummaryString(b.props?.spans);
            const trimmed = txt.trim();
            // Hint: ":" with no token after = a label awaiting a merge field
            const hasToken = (b.props?.spans || []).some(s => s.kind === 'token');
            const isLabel = trimmed.endsWith(':') && !hasToken;
            const prefix = isLabel ? '⤵ Drop a field here  ·  ' : '';
            return `${prefix}Text: "${txt.substring(0, 80)}"`;
        }
        case 'image':      return `Image: ${b.props.signatureType} signature (${b.props.width} × ${b.props.height})`;
        case 'table':      return `Table from ${b.props.relation} · ${(b.props.columns || []).length} cols`;
        case 'row':        return `Row · ${b.props.columnCount} column${b.props.columnCount === 1 ? '' : 's'}`;
        case 'spacer':     return `Spacer (${b.props.height})`;
        case 'rule':       return `Horizontal Rule`;
        default:           return b.type;
    }
}

/* ============================================================
 *  Block <-> renderer JSON
 * ============================================================ */

function blocksToJson(blocks, _ctx) {
    const rootChildren = [];
    const tables = [];
    for (const b of blocks) {
        if (b.type === 'table') {
            tables.push(blockToTableNode(b));
        } else {
            rootChildren.push(blockToNode(b));
        }
    }
    return {
        page: { size: 'LETTER', orientation: 'portrait', margins: '0.5in' },
        fontStack: "'Helvetica Neue', Helvetica, Arial, sans-serif",
        root: {
            type: 'row',
            children: [{
                type: 'col',
                props: { width: '100%', padding: '0' },
                children: rootChildren
            }]
        },
        tables: tables
    };
}

function spansToRendererSpans(spans, blockBold) {
    return (spans || []).map(s => {
        if (s.kind === 'token') {
            const out = { token: s.value || '' };
            if (s.bold) out.bold = true;
            if (s.italic) out.italic = true;
            return out;
        }
        // Per-span bold/italic flags take precedence; fall back to block-level bold.
        const out = { text: s.value || '' };
        if (s.bold || (!('bold' in s) && blockBold)) out.bold = true;
        if (s.italic) out.italic = true;
        return out;
    });
}

function blockToNode(b) {
    const p = b.props || {};
    switch (b.type) {
        case 'heading':
            return { type: 'text', props: {
                align: p.align || 'center', fontSize: p.size || '20pt', marginBottom: '8px',
                spans: spansToRendererSpans(p.spans, p.bold)
            }};
        case 'text':
            return { type: 'text', props: {
                align: p.align || 'left', fontSize: p.size || '11pt', marginBottom: '6px',
                spans: spansToRendererSpans(p.spans, p.bold)
            }};
        case 'image':
            return { type: 'image', props: {
                source: 'relatedFile', fromRelation: 'Signatures__r',
                filterExpr: `Signature_Type__c == '${p.signatureType || 'Patient'}'`,
                width: p.width || '180px', height: p.height || '50px'
            }};
        case 'row': {
            const n = p.columnCount || (b.columns || []).length || 1;
            const colWidth = `${(100 / n).toFixed(2)}%`;
            return {
                type: 'row',
                children: (b.columns || []).map(col => ({
                    type: 'col',
                    props: { width: colWidth, padding: '0 6px' },
                    children: (col.children || []).map(blockToNode)
                }))
            };
        }
        case 'spacer': return { type: 'spacer', props: { height: p.height || '12px' } };
        case 'rule':   return { type: 'rule' };
        default:       return { type: 'text', props: { spans: [{ text: '[unknown block]' }] } };
    }
}

function blockToTableNode(b) {
    const p = b.props || {};
    const cols = (p.columns || []).map(c => ({
        header: c.header || '',
        width: c.width || undefined,
        spans: c.token ? [{ token: c.token }] : (c.text ? [{ text: c.text }] : [])
    }));
    return { type: 'table', props: {
        fromRelation: p.relation || 'Signatures__r',
        headerBackground: '#EAEAEA',
        columns: cols
    }};
}

function jsonToBlocks(jsonStr) {
    if (!jsonStr) return [];
    let def;
    try { def = JSON.parse(jsonStr); } catch (_e) { return []; }
    const out = [];
    const root = def?.root;
    if (root?.type === 'row' && Array.isArray(root.children)) {
        for (const col of root.children) {
            if (col?.type !== 'col' || !Array.isArray(col.children)) continue;
            for (const child of col.children) {
                const b = nodeToBlock(child);
                if (b) out.push(b);
            }
        }
    }
    if (Array.isArray(def?.tables)) {
        for (const t of def.tables) {
            if (t?.type === 'table') out.push(tableNodeToBlock(t));
        }
    }
    return out;
}

function nodeToBlock(n) {
    if (!n || !n.type) return null;
    if (n.type === 'spacer') return { id: nextId(), type: 'spacer', props: { height: n.props?.height || '12px' } };
    if (n.type === 'rule')   return { id: nextId(), type: 'rule', props: {} };
    if (n.type === 'image') {
        const filter = n.props?.filterExpr || '';
        const m = /Signature_Type__c\s*==\s*'([^']+)'/.exec(filter);
        return { id: nextId(), type: 'image', props: {
            signatureType: m ? m[1] : 'Patient',
            width: n.props?.width || '180px',
            height: n.props?.height || '50px'
        }};
    }
    if (n.type === 'text') {
        const spans = n.props?.spans || [];
        const fs = n.props?.fontSize || '11pt';
        const sizeNum = parseFloat(fs);
        const ourSpans = spans.map(s => {
            if (s.token != null) {
                return { kind: 'token', value: s.token, bold: !!s.bold, italic: !!s.italic };
            }
            return { kind: 'text', value: s.text || '', bold: !!s.bold, italic: !!s.italic };
        });
        const anyBold = spans.some(s => s.text != null && s.bold);
        const isHeading = sizeNum >= 16 || (spans.length === 1 && spans[0].text != null && spans[0].bold);
        return {
            id: nextId(),
            type: isHeading ? 'heading' : 'text',
            props: {
                spans: ourSpans.length > 0 ? ourSpans : [{ kind: 'text', value: '' }],
                align: n.props?.align || (isHeading ? 'center' : 'left'),
                size: fs,
                bold: anyBold
            }
        };
    }
    if (n.type === 'row' && Array.isArray(n.children)) {
        const columns = n.children.map(col => ({
            id: nextId(),
            children: Array.isArray(col?.children)
                ? col.children.map(nodeToBlock).filter(Boolean)
                : []
        }));
        return {
            id: nextId(),
            type: 'row',
            props: { columnCount: columns.length || 1 },
            columns
        };
    }
    return null;
}

/* ============================================================
 *  Document-import parsers
 * ============================================================ */

function makeTextFromString(text, opts) {
    const o = opts || {};
    return {
        id: nextId(),
        type: o.heading ? 'heading' : 'text',
        props: {
            spans: [{ kind: 'text', value: text, bold: !!o.bold, italic: !!o.italic }],
            align: o.align || (o.heading ? 'center' : 'left'),
            size: o.size || (o.heading ? '20pt' : '11pt'),
            bold: !!o.bold
        }
    };
}

function htmlStringToBlocks(html) {
    if (!html) return [];
    const container = document.createElement('div');
    container.innerHTML = html;
    const blocks = [];
    const ctx = { isFirstContent: true };
    walkNodeForBlocks(container, blocks, ctx);
    return blocks;
}

function isWhollyBold(el) {
    const kids = Array.from(el.children);
    if (kids.length === 0) return false;
    return kids.every(c => /^(strong|b)$/i.test(c.tagName));
}

/**
 * Walk inline-content (text + <strong>/<b>/<em>/<i>/<u>) and emit a flat list
 * of spans with bold/italic flags preserved. Adjacent same-style runs are merged.
 */
function paragraphToSpans(paragraph) {
    const out = [];
    walkInline(paragraph, { bold: false, italic: false }, out);
    return mergeAdjacentSpans(out);
}

function walkInline(node, style, out) {
    for (const child of Array.from(node.childNodes)) {
        if (child.nodeType === 3) {
            const t = child.nodeValue;
            if (t) out.push({ kind: 'text', value: t, bold: style.bold, italic: style.italic });
            continue;
        }
        if (child.nodeType !== 1) continue;
        const tag = child.tagName.toLowerCase();
        if (tag === 'br') {
            out.push({ kind: 'text', value: '\n', bold: style.bold, italic: style.italic });
            continue;
        }
        const next = { ...style };
        if (tag === 'strong' || tag === 'b') next.bold = true;
        if (tag === 'em' || tag === 'i') next.italic = true;
        walkInline(child, next, out);
    }
}

function mergeAdjacentSpans(spans) {
    const out = [];
    for (const s of spans) {
        const last = out[out.length - 1];
        if (last && last.kind === 'text' && s.kind === 'text'
            && !!last.bold === !!s.bold && !!last.italic === !!s.italic) {
            last.value += s.value;
        } else {
            out.push({ ...s });
        }
    }
    return out;
}

const SIGNATURE_LABEL_RE = /(signature|signed\s+by|sign\s*here|initials?)/i;
const TRAILING_UNDERSCORES_RE = /^_{3,}$/;
const LABEL_PATTERN_RE = /^(.{1,80}?):\s*(_+\s*)?$/;

function isSignatureLabel(text) {
    return SIGNATURE_LABEL_RE.test(text);
}

function makeSignatureImageBlock() {
    return {
        id: nextId(),
        type: 'image',
        props: { signatureType: 'Patient', width: '180px', height: '50px' }
    };
}

function makeLabeledFieldBlock(labelText) {
    return {
        id: nextId(),
        type: 'text',
        props: {
            spans: [
                { kind: 'text', value: labelText.replace(/\s+$/, '') + ': ' },
                { kind: 'token', value: '' }
            ],
            align: 'left', size: '11pt', bold: false
        }
    };
}

function makeLabeledSignatureRow(labelText) {
    return {
        id: nextId(),
        type: 'row',
        props: { columnCount: 2 },
        columns: [
            { id: nextId(), children: [makeTextFromString(labelText.replace(/\s+$/, '') + ': ', { bold: true })] },
            { id: nextId(), children: [makeSignatureImageBlock()] }
        ]
    };
}

function paragraphToBlock(p, ctx) {
    const fullText = (p.textContent || '').trim();
    if (!fullText) return null;

    // Pure underscore line → signature placeholder
    if (TRAILING_UNDERSCORES_RE.test(fullText)) {
        return makeSignatureImageBlock();
    }

    // "Label:" (optionally followed by underscores) → labeled merge slot or signature
    const labelMatch = LABEL_PATTERN_RE.exec(fullText);
    if (labelMatch) {
        const label = labelMatch[1].trim();
        if (label && isSignatureLabel(label)) {
            ctx.isFirstContent = false;
            return makeLabeledSignatureRow(label);
        }
        if (label) {
            ctx.isFirstContent = false;
            return makeLabeledFieldBlock(label);
        }
    }

    // First-paragraph heading rule (only fires before any other content has emitted)
    if (ctx.isFirstContent && fullText.length < 140 && !fullText.endsWith(':')) {
        ctx.isFirstContent = false;
        return makeTextFromString(fullText, { heading: true, size: '22pt', bold: true });
    }

    // Bold-only paragraph → section heading
    if (isWhollyBold(p) && fullText.length < 80) {
        ctx.isFirstContent = false;
        return makeTextFromString(fullText, { heading: true, size: '14pt', bold: true });
    }

    // Default: parse inline children, preserving bold/italic per span.
    const spans = paragraphToSpans(p);
    if (spans.length === 0 || spans.every(s => !s.value || !s.value.trim())) return null;
    ctx.isFirstContent = false;
    return {
        id: nextId(),
        type: 'text',
        props: {
            spans,
            align: 'left', size: '11pt', bold: false
        }
    };
}

function walkNodeForBlocks(node, blocks, ctx) {
    for (const child of Array.from(node.childNodes)) {
        if (child.nodeType !== 1) continue;
        const tag = child.tagName.toLowerCase();

        if (/^h[1-6]$/.test(tag)) {
            const level = parseInt(tag[1], 10);
            const sizeByLevel = { 1: '24pt', 2: '20pt', 3: '17pt', 4: '15pt', 5: '13pt', 6: '12pt' };
            const text = (child.textContent || '').trim();
            if (text) blocks.push(makeTextFromString(text, { heading: true, size: sizeByLevel[level] || '14pt', bold: true }));
            ctx.isFirstContent = false;
            continue;
        }

        if (tag === 'p') {
            const block = paragraphToBlock(child, ctx);
            if (block) blocks.push(block);
            continue;
        }

        if (tag === 'hr') {
            blocks.push(makeRule());
            ctx.isFirstContent = false;
            continue;
        }

        if (tag === 'ul' || tag === 'ol') {
            const items = child.querySelectorAll(':scope > li');
            for (const li of Array.from(items)) {
                const text = (li.textContent || '').trim();
                if (text) blocks.push(makeTextFromString('• ' + text));
            }
            ctx.isFirstContent = false;
            continue;
        }

        if (tag === 'table') {
            const rows = child.querySelectorAll(':scope tr');
            for (const row of Array.from(rows)) {
                const cells = Array.from(row.querySelectorAll(':scope th, :scope td'));
                if (cells.length === 0) continue;
                const cellTexts = cells.map(c => (c.textContent || '').trim());
                const cap = Math.min(cellTexts.length, 6);
                if (cap === 1) {
                    const single = cellTexts[0];
                    if (single) {
                        // Even single-cell rows can carry "Label:" structure
                        const lm = LABEL_PATTERN_RE.exec(single);
                        if (lm) blocks.push(makeLabeledFieldBlock(lm[1].trim()));
                        else blocks.push(makeTextFromString(single));
                    }
                    continue;
                }
                const cols = [];
                for (let i = 0; i < cap; i++) {
                    cols.push({
                        id: nextId(),
                        children: cellTexts[i] ? [makeTextFromString(cellTexts[i])] : []
                    });
                }
                blocks.push({
                    id: nextId(),
                    type: 'row',
                    props: { columnCount: cap },
                    columns: cols
                });
            }
            ctx.isFirstContent = false;
            continue;
        }

        if (tag === 'div' || tag === 'section' || tag === 'article') {
            walkNodeForBlocks(child, blocks, ctx);
            continue;
        }

        const text = (child.textContent || '').trim();
        if (text) {
            blocks.push(makeTextFromString(text));
            ctx.isFirstContent = false;
        }
    }
}

/* ============================================================
 *  Two-pass: auto-match empty token spans to fields by label
 * ============================================================ */

function normalizeForMatch(s) {
    return (s || '').toLowerCase().replace(/[^a-z0-9]/g, '');
}

function suggestFieldMatch(label, fields) {
    if (!fields || fields.length === 0) return null;
    const target = normalizeForMatch(label);
    if (!target) return null;
    // Exact label match
    let m = fields.find(f => normalizeForMatch(f.label) === target);
    if (m) return m.apiName;
    // Exact apiName-without-suffix match
    m = fields.find(f => normalizeForMatch((f.apiName || '').replace(/__c$/i, '')) === target);
    if (m) return m.apiName;
    // Substring (either way), prefer the shorter field name to avoid greedy matches
    const candidates = fields.filter(f => {
        const fl = normalizeForMatch(f.label);
        const fa = normalizeForMatch((f.apiName || '').replace(/__c$/i, ''));
        return (fl && (fl.includes(target) || target.includes(fl)))
            || (fa && (fa.includes(target) || target.includes(fa)));
    });
    if (candidates.length === 0) return null;
    candidates.sort((a, b) => (a.label || '').length - (b.label || '').length);
    return candidates[0].apiName;
}

function autoMatchTokens(blocks, fields) {
    let matchCount = 0;
    function patchSpans(b) {
        if (!b || (b.type !== 'text' && b.type !== 'heading')) return b;
        const spans = b.props?.spans || [];
        const out = spans.map((s, i) => {
            if (s.kind !== 'token' || s.value) return s;
            // Look at the immediately preceding text span for the label
            const prev = i > 0 ? spans[i - 1] : null;
            if (!prev || prev.kind !== 'text') return s;
            const label = prev.value.replace(/[:_\s]+$/g, '').trim();
            if (!label) return s;
            const match = suggestFieldMatch(label, fields);
            if (match) {
                matchCount++;
                return { ...s, value: match };
            }
            return s;
        });
        return { ...b, props: { ...b.props, spans: out } };
    }
    function recurse(arr) {
        return arr.map(b => {
            const patched = patchSpans(b);
            if (patched.type === 'row') {
                return {
                    ...patched,
                    columns: (patched.columns || []).map(col => ({
                        ...col,
                        children: recurse(col.children || [])
                    }))
                };
            }
            return patched;
        });
    }
    const patched = recurse(blocks);
    return { blocks: patched, matchCount };
}

function groupItemsIntoLines(items) {
    // pdf.js text items have a 6-element transform; index 5 is Y (top-of-page coord).
    // Group items whose Y is within ~2 units of each other as one visual line.
    const lines = [];
    let currentY = null;
    let currentLine = [];
    const epsilon = 2;
    for (const item of items) {
        if (!item || typeof item.str !== 'string') continue;
        const y = Array.isArray(item.transform) ? item.transform[5] : 0;
        if (currentY === null || Math.abs(y - currentY) > epsilon) {
            if (currentLine.length) lines.push(currentLine.map(i => i.str).join(''));
            currentLine = [item];
            currentY = y;
        } else {
            currentLine.push(item);
        }
    }
    if (currentLine.length) lines.push(currentLine.map(i => i.str).join(''));
    // Collapse consecutive blank lines
    const out = [];
    let prevBlank = false;
    for (const l of lines) {
        const blank = l.trim() === '';
        if (blank && prevBlank) continue;
        out.push(l);
        prevBlank = blank;
    }
    return out;
}

function tableNodeToBlock(t) {
    const p = t.props || {};
    const cols = (p.columns || []).map(c => ({
        header: c.header || '',
        token: c.spans?.[0]?.token || '',
        text: c.spans?.[0]?.text || '',
        width: c.width || ''
    }));
    return { id: nextId(), type: 'table', props: {
        relation: p.fromRelation || 'Signatures__r',
        columns: cols
    }};
}
