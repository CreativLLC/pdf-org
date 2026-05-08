/**
 * VF page controller for /apex/DocumentRender. Reads templateVersionId + recordId from
 * URL params, asks PdfTemplateService for the rendered PageModel, exposes it for the
 * page bindings. The page itself is renderAs="pdf" so getContentAsPdf() works downstream.
 */
public with sharing class DocumentRenderController {

    public PdfTemplateService.PageModel pageModel { get; private set; }
    public String errorMessage { get; private set; }

    public DocumentRenderController() {
        // Always provide a default PageModel so the page-level CSS bindings never NPE,
        // even when the URL is missing parameters or the template fails to load.
        pageModel = new PdfTemplateService.PageModel();
        pageModel.page = new PdfTemplateService.PageProps();
        pageModel.page.size = 'LETTER';
        pageModel.page.orientation = 'portrait';
        pageModel.page.margins = '0.5in';
        pageModel.page.fontStack = '\'Helvetica Neue\', Arial, sans-serif';
        pageModel.page.bodyCss = '';
        pageModel.htmlBlocks = new List<String>();

        try {
            String tvIdParam = ApexPages.currentPage().getParameters().get('templateVersionId');
            String recordIdParam = ApexPages.currentPage().getParameters().get('recordId');
            if (String.isBlank(tvIdParam) || String.isBlank(recordIdParam)) {
                errorMessage = 'Missing required URL parameters: templateVersionId and recordId.';
                return;
            }
            pageModel = PdfTemplateService.build((Id) tvIdParam, (Id) recordIdParam);
        } catch (Exception e) {
            errorMessage = e.getMessage();
        }
    }
}
