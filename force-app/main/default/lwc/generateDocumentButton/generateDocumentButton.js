import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import generateAndSave from '@salesforce/apex/PdfGeneratorController.generateAndSave';
import generateAndSaveByName from '@salesforce/apex/PdfGeneratorController.generateAndSaveByName';

export default class GenerateDocumentButton extends NavigationMixin(LightningElement) {
    @api recordId;
    @api documentTemplateId;
    @api documentTemplateName;
    @api buttonLabel = 'Generate PDF';
    @api buttonVariant = 'brand';
    @api iconName = 'utility:download';

    isGenerating = false;
    lastResult;

    get isMisconfigured() {
        return !this.documentTemplateId && !this.documentTemplateName;
    }

    get effectiveLabel() {
        return this.buttonLabel || 'Generate PDF';
    }

    async handleClick() {
        if (this.isMisconfigured) {
            this.toast(
                'error',
                'Button is not configured',
                'Edit this Lightning page and set either Document Template ID or Document Template Name on the component.',
                'sticky'
            );
            return;
        }
        this.isGenerating = true;
        this.lastResult = undefined;
        try {
            const result = this.documentTemplateId
                ? await generateAndSave({ templateId: this.documentTemplateId, recordId: this.recordId })
                : await generateAndSaveByName({ templateName: this.documentTemplateName, recordId: this.recordId });
            this.lastResult = result;
            this.toast('success', 'PDF generated', `Saved as ${result.fileName}.`);
        } catch (err) {
            const msg = err?.body?.message ?? err?.message ?? 'Unknown error';
            this.toast('error', 'Generation failed', msg, 'sticky');
        } finally {
            this.isGenerating = false;
        }
    }

    handleOpenFile() {
        if (!this.lastResult?.contentDocumentId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: this.lastResult.contentDocumentId }
        });
    }

    toast(variant, title, message, mode = 'dismissable') {
        this.dispatchEvent(new ShowToastEvent({ variant, title, message, mode }));
    }
}
