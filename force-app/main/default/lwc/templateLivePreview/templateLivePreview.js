import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getContext from '@salesforce/apex/TemplateBuilderController.getContext';
import listSampleRecords from '@salesforce/apex/TemplateBuilderController.listSampleRecords';
import previewTemplate from '@salesforce/apex/TemplateBuilderController.previewTemplate';
import saveTemplate from '@salesforce/apex/TemplateBuilderController.saveTemplate';

export default class TemplateLivePreview extends NavigationMixin(LightningElement) {
    @api recordId; // Template_Version__c id when placed on the record page
    @api templateVersionIdOverride; // optional design-time override for app pages

    ctx;
    sampleRecordOptions = [];
    selectedSampleRecordId;
    json = '';
    initialJson = '';
    previewHtml = '';
    previewFontStack = '';
    isLoading = false;
    isSaving = false;
    errorText;

    get effectiveVersionId() {
        return this.templateVersionIdOverride || this.recordId;
    }

    get isDirty() {
        return this.json !== this.initialJson;
    }

    get saveLabel() {
        return this.isDirty ? 'Save *' : 'Save';
    }

    get previewStyle() {
        const fontStack = this.previewFontStack || "'Helvetica Neue', Arial, sans-serif";
        return `font-family: ${fontStack}; font-size: 11pt; color: #222; padding: 0.5in; background: #fff;`;
    }

    get pdfUrl() {
        if (!this.ctx?.templateVersionId || !this.selectedSampleRecordId) return null;
        return `/apex/DocumentRender?templateVersionId=${this.ctx.templateVersionId}&recordId=${this.selectedSampleRecordId}`;
    }

    async connectedCallback() {
        await this.loadContext();
    }

    renderedCallback() {
        const target = this.template.querySelector('.preview-content');
        if (target && target.dataset.lastHtml !== this.previewHtml) {
            target.innerHTML = this.previewHtml || '';
            target.dataset.lastHtml = this.previewHtml || '';
        }
    }

    async loadContext() {
        this.errorText = null;
        this.isLoading = true;
        try {
            const c = await getContext({ templateVersionId: this.effectiveVersionId });
            this.ctx = c;
            this.json = c.definitionJson || '';
            this.initialJson = this.json;

            const samples = await listSampleRecords({ objectApi: c.targetSObject, maxRows: 50 });
            this.sampleRecordOptions = samples.map(s => ({ label: s.name, value: s.id }));
            this.selectedSampleRecordId = c.sampleRecordId
                || (samples.length > 0 ? samples[0].id : null);

            if (this.selectedSampleRecordId) {
                await this.refreshPreview();
            }
        } catch (e) {
            this.errorText = this.errMsg(e);
            this.toast('error', 'Failed to load template', this.errorText, 'sticky');
        } finally {
            this.isLoading = false;
        }
    }

    handleJsonChange(e) {
        this.json = e.target.value;
    }

    handleSampleChange(e) {
        this.selectedSampleRecordId = e.detail.value;
    }

    async handleRefreshPreview() {
        await this.refreshPreview();
    }

    async refreshPreview() {
        if (!this.json || !this.selectedSampleRecordId) return;
        this.errorText = null;
        try {
            const result = await previewTemplate({
                defJson: this.json,
                targetSObject: this.ctx.targetSObject,
                sampleRecordId: this.selectedSampleRecordId
            });
            this.previewHtml = result.html;
            this.previewFontStack = result.fontStack;
        } catch (e) {
            this.errorText = this.errMsg(e);
        }
    }

    async handleSave() {
        if (!this.ctx?.templateVersionId) return;
        this.isSaving = true;
        try {
            await saveTemplate({
                templateVersionId: this.ctx.templateVersionId,
                defJson: this.json,
                sampleRecordId: this.selectedSampleRecordId
            });
            this.initialJson = this.json;
            this.toast('success', 'Saved', 'Template definition updated.');
            await this.refreshPreview();
        } catch (e) {
            this.toast('error', 'Save failed', this.errMsg(e), 'sticky');
        } finally {
            this.isSaving = false;
        }
    }

    async handleSaveAndPreview() {
        await this.handleSave();
    }

    handleOpenPdf() {
        if (!this.pdfUrl) {
            this.toast('warning', 'No sample record', 'Pick a sample record first.');
            return;
        }
        window.open(this.pdfUrl, '_blank');
    }

    handleFormatJson() {
        try {
            const parsed = JSON.parse(this.json);
            this.json = JSON.stringify(parsed, null, 2);
        } catch (e) {
            this.toast('error', 'JSON invalid', e.message, 'sticky');
        }
    }

    toast(variant, title, message, mode = 'dismissable') {
        this.dispatchEvent(new ShowToastEvent({ variant, title, message, mode }));
    }

    errMsg(e) {
        return e?.body?.message ?? e?.message ?? 'Unknown error';
    }
}
