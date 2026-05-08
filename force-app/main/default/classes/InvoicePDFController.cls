public class InvoicePDFController {
    public Invoice__c invoice { get; set; }
    public List<Time_Sheet__c> timeSheets { get; set; }
    public List<DetailRow> detailRows { get; set; }
    public Decimal totalHours { get; set; }
    public Decimal totalAmount { get; set; }
    public Decimal totalWork { get; set; }
    public Decimal totalRate { get; set; }
    public Decimal creditApplied { get; set; }
    private String detailRowBgColor = '#FFF;';
    private String subtotalRowBgColor = '#EEE;';
    
    public InvoicePDFController() {
        // Get Invoice Id from URL Parameters
        Map<String, String> params = ApexPages.currentPage().getParameters();
        Id invoiceId = (Id) params.get('id');
        
        // Get the invoice record in question along with Account and Project information
        invoice = [SELECT Id, Name, Invoice_Start_Date__c, Invoice_End_Date__c, Invoice_Due_Date__c, Project__c, Project__r.Name,
                   	Deposit_Invoice__c, Deposit_Invoice__r.Name, Applied_Credit__c, Project__r.PO_Number__c, Invoice_Total__c,
                    Invoiced_To__r.Name, Invoiced_To__r.Account_Legal_Name__c, Invoiced_To__r.Invoice_Attn_Line__c, 
                   	Invoiced_To__r.BillingStreet, Invoiced_To__r.BillingCity, Invoiced_To__r.BillingState, Invoiced_To__r.BillingPostalCode,
                   	Invoiced_To__r.Billing_Type__c
                   FROM Invoice__c where Id = :invoiceId];
        
        timeSheets = [SELECT Id, Name, Epic__c, Resource_Type__c, Hours__c, Total_Billable_Amount__c, Done_By_Name__c
                      FROM Time_Sheet__c 
                      where Project__c = :invoice.Project__c 
                      and Date__c >= :invoice.Invoice_Start_Date__c
                      and Date__c <= :invoice.Invoice_End_Date__c];
        
        List<String> fileNameElements = new List<String>();
        fileNameElements.add(invoice.Invoiced_To__r.Name);
        fileNameElements.add(invoice.Name);
        fileNameElements.add(invoice.Invoice_Start_Date__c.format());
        fileNameElements.add(invoice.Invoice_End_Date__c.format());
        String fileName = String.join(fileNameElements, '-');
        
		Apexpages.currentPage().getHeaders().put('content-disposition', 'attachment; filename=' + fileName + '.pdf');
        
        // Group TimeSheets by Epic and Resource
        Map<String, Map<String, List<Time_Sheet__c>>> epicMap = new Map<String, Map<String, List<Time_Sheet__c>>>();
        for(Time_Sheet__c ts : timeSheets){
            if(ts.Epic__c == null) ts.Epic__c = 'General Support';
            Map<String, List<Time_Sheet__c>> resourceMap = epicMap.get(ts.Epic__c);
            if(resourceMap == null) resourceMap = new Map<String, List<Time_Sheet__c>>();
            
            String resourceKey = invoice.Invoiced_To__r.Billing_Type__c == 'Individual' ? ts.Done_By_Name__c : ts.Resource_Type__c;
            List<Time_Sheet__c> timeSheetList = resourceMap.get(resourceKey);
            if(timeSheetList == null) timeSheetList = new List<Time_Sheet__c>();
            timeSheetList.add(ts);
            resourceMap.put(resourceKey, timeSheetList);
            epicMap.put(ts.Epic__c, resourceMap);
        }
        
        // Calculate sums averages and totals
        detailRows = new List<DetailRow>();
        totalHours = 0.00;                                             
        totalWork = 0.00;
        for(String epicKey : epicMap.keySet()){
            Map<String, List<Time_Sheet__c>> resourceMap = epicMap.get(epicKey);
            Boolean isFirstRow = true;
            Decimal epicHours = 0.00;                                             
            Decimal epicAmount = 0.00;
            for(String resourceKey : resourceMap.keySet()){
                List<Time_Sheet__c> tsList = resourceMap.get(resourceKey);
                Decimal resourceHours = 0.00;                                             
                Decimal resourceAmount = 0.00;
                for(Time_Sheet__c ts : tsList){
                    resourceHours = resourceHours + ts.Hours__c.setScale(2);
                    resourceAmount = resourceAmount + ts.Total_Billable_Amount__c;
                }
                Decimal resourceRate = resourceAmount/resourceHours;
                String epicValue = isFirstRow ? epicKey : null;
                detailRows.add(new DetailRow(epicValue, resourceKey, resourceHours, resourceRate, resourceAmount, detailRowBgColor));
                isFirstRow = false;
                epicHours = epicHours + resourceHours;
                epicAmount = epicAmount + resourceAmount;
            }
            
            Decimal epicRate = epicAmount/epicHours;
            
            detailRows.add(new DetailRow('Subtotal', null, epicHours, epicRate, epicAmount, subtotalRowBgColor));
            
            totalHours = totalHours + epicHours;
            totalWork = totalWork + epicAmount;
        }
        totalRate = totalWork/totalHours;
        
        totalAmount = invoice.Applied_Credit__c != null ? totalWork - invoice.Applied_Credit__c : totalWork;
        creditApplied = invoice.Applied_Credit__c != null ? -invoice.Applied_Credit__c : null;
    }
    
    public class DetailRow{
        public String project { get; set; }
        public String resource  { get; set; }
        public Decimal hours  { get; set; }
        public Decimal rate  { get; set; }
        public Decimal amount  { get; set; }
        public String bgColor  { get; set; }
        
        public DetailRow(String project){
            this.project = project;
            this.resource = null;
            this.hours = null;
            this.rate = null;
            this.amount = null;
            this.bgColor = '#FFFFFF';
        }
        
        public DetailRow(String project, String resource, Decimal hours, Decimal rate, Decimal amount, String bgColor){
            this.project = project;
            this.resource = resource;
            this.hours = hours;
            this.rate = rate;
            this.amount = amount;
            this.bgColor = bgColor;
        }
    }
}