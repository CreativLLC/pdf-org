public class InvoiceUtils {
	public static void handleBeforeInsert(){
        Map<Id, Project__c> referencedProjects;
        Set<Id> projIds = new Set<Id>();
        for(Invoice__c inv : (List<Invoice__c>) trigger.new){
            projIds.add(inv.Project__c);
        }
        referencedProjects = new Map<Id, Project__c>([select Id, Net_Payment_Terms__c from Project__c where Id in :projIds]);
        for(Invoice__c inv : (List<Invoice__c>) trigger.new){
            if(inv.Payment_Days__c == null){
                Project__c proj = referencedProjects.get(inv.Project__c);
                switch on proj.Net_Payment_Terms__c {
                    when 'Net 7' {
                        inv.Payment_Days__c = 7;
                    }
                    when 'Net 15' {
                        inv.Payment_Days__c = 30;
                    }
                    when 'Net 30' {
                        inv.Payment_Days__c = 30;
                    }
                    when else {
                        inv.Payment_Days__c = 30;
                    }
                }
            }
            inv.Work_Done_Amount__c = inv.Work_Done_Amount__c == null ? 0 : inv.Work_Done_Amount__c;
            inv.Pre_Paid_Amount__c = inv.Pre_Paid_Amount__c == null ? 0 : inv.Pre_Paid_Amount__c;
            if(inv.Pre_Paid_Amount__c > 0)
            	inv.Invoice_Total__c = inv.Pre_Paid_Amount__c;    
            else
                inv.Invoice_Total__c = inv.Applied_Credit__c == null ? inv.Work_Done_Amount__c : inv.Work_Done_Amount__c - inv.Applied_Credit__c;
        }
    }
    public static void handleBeforeUpdate(){
        Map<Id, Project__c> referencedProjects;
        Set<Id> projIds = new Set<Id>();
        for(Invoice__c inv : (List<Invoice__c>) trigger.new){
            projIds.add(inv.Project__c);
        }
        referencedProjects = new Map<Id, Project__c>([select Id, Net_Payment_Terms__c from Project__c where Id in :projIds]);
        for(Invoice__c inv : (List<Invoice__c>) trigger.new){
            if(inv.Payment_Days__c == null){
                Project__c proj = referencedProjects.get(inv.Project__c);
                switch on proj.Net_Payment_Terms__c {
                    when 'Net 7' {
                        inv.Payment_Days__c = 7;
                    }
                    when 'Net 15' {
                        inv.Payment_Days__c = 30;
                    }
                    when 'Net 30' {
                        inv.Payment_Days__c = 30;
                    }
                    when else {
                        inv.Payment_Days__c = 30;
                    }
                }
            }
            inv.Work_Done_Amount__c = inv.Work_Done_Amount__c == null ? 0 : inv.Work_Done_Amount__c;
            inv.Pre_Paid_Amount__c = inv.Pre_Paid_Amount__c == null ? 0 : inv.Pre_Paid_Amount__c;
            if(inv.Pre_Paid_Amount__c > 0)
            	inv.Invoice_Total__c = inv.Pre_Paid_Amount__c;    
            else
                inv.Invoice_Total__c = inv.Applied_Credit__c == null ? inv.Work_Done_Amount__c : inv.Work_Done_Amount__c - inv.Applied_Credit__c;
        }
    }
    public static void handleBeforeDelete(){}
    public static void handleAfterInsert(){
        // Iterate through invoices and look for Referral or Commission type Contact Roles connected to the related Project record
        // Also look for references to deposit invoices that need to be updated
        Set<Id> relatedProjectIds = new Set<Id>();
        Set<Id> relatedDepositInvoiceIds = new Set<Id>();
        for(Invoice__c currentInvoice : (List<Invoice__c>) Trigger.new){
            if(currentInvoice.Project__c != null){
                relatedProjectIds.add(currentInvoice.Project__c);
            }
            if(currentInvoice.Deposit_Invoice__c != null){
                relatedDepositInvoiceIds.add(currentInvoice.Deposit_Invoice__c);
            }   
        }
        
        if(relatedProjectIds != null && relatedProjectIds.size() > 0){
            Id referralRecordTypeId = ContactRoleUtils.getRecordTypeId('Referral');
            Id salesTeamRecordTypeId = ContactRoleUtils.getRecordTypeId('Sales_Team');
            Set<Id> recordTypeFilter = new Set<Id>{referralRecordTypeId, salesTeamRecordTypeId};
            Map<Id, Project__c> projectsMap = new Map<Id, Project__c>([select Id, 
                                                                            (select Id
                                                                                from Project_Assignments__r 
                                                                                where RecordTypeId in :recordTypeFilter
                                                                                and Status__c = 'Active')
                                                                       from Project__c 
                                                                       where Id in :relatedProjectIds]);

            // Iterate back through the Invoices and look up Projects with Project Assignments that need a
            // Referral/Commission Payment created
            List<Referral_Commission_Payment__c> RCPaymentsToCreate = new List<Referral_Commission_Payment__c>();
            for(Invoice__c currentInvoice : (List<Invoice__c>) Trigger.new){
                if(currentInvoice.Project__c != null){
                    Project__c relatedProject = projectsMap.get(currentInvoice.Project__c);
                    if(relatedProject != null){
                        for(Contact_Role__c projectAssignment : relatedProject.Project_Assignments__r){
                            Referral_Commission_Payment__c RCPayment = new Referral_Commission_Payment__c();
                            RCPayment.Contact_Role__c = projectAssignment.Id;
                            RCPayment.Invoice__c = currentInvoice.Id;
                            RCPaymentsToCreate.add(RCPayment);
                        }
                    }
                }
            }
            if(RCPaymentsToCreate.size() > 0){
                Database.insert(RCPaymentsToCreate);
            }
        }
        if(relatedDepositInvoiceIds != null && relatedDepositInvoiceIds.size() > 0){
            List<Invoice__c> depositInvoices = [select Id, (select Id, Applied_Credit__c from AppliedToInvoices__r), Credit_Debt__c 
                                                from Invoice__c where Id in :relatedDepositInvoiceIds];
            for(Invoice__c depositInvoice : depositInvoices){
                Decimal totalUsed = 0.00;
                for(Invoice__c standardInvoice : depositInvoice.AppliedToInvoices__r){
                    standardInvoice.Applied_Credit__c = standardInvoice.Applied_Credit__c == null ? 0 : standardInvoice.Applied_Credit__c;
                    totalUsed = totalUsed + standardInvoice.Applied_Credit__c;
                }
                depositInvoice.Available_Credit__c = depositInvoice.Credit_Debt__c - totalUsed;
            }
            update depositInvoices;
        }
    }
    public static void handleAfterUpdate(){
        Set<Id> relatedDepositInvoiceIds = new Set<Id>();
        for(Invoice__c currentInvoice : (List<Invoice__c>) Trigger.new){
            if(currentInvoice.Deposit_Invoice__c != null){
                relatedDepositInvoiceIds.add(currentInvoice.Deposit_Invoice__c);
            }   
        }
        if(relatedDepositInvoiceIds != null && relatedDepositInvoiceIds.size() > 0){
            List<Invoice__c> depositInvoices = [select Id, (select Id, Applied_Credit__c from AppliedToInvoices__r), Credit_Debt__c 
                                                from Invoice__c where Id in :relatedDepositInvoiceIds];
            for(Invoice__c depositInvoice : depositInvoices){
                Decimal totalUsed = 0.00;
                for(Invoice__c standardInvoice : depositInvoice.AppliedToInvoices__r){
                    standardInvoice.Applied_Credit__c = standardInvoice.Applied_Credit__c == null ? 0 : standardInvoice.Applied_Credit__c;
                    totalUsed = totalUsed + standardInvoice.Applied_Credit__c;
                }
                depositInvoice.Available_Credit__c = depositInvoice.Credit_Debt__c - totalUsed;
            }
            update depositInvoices;
        }
    }
    public static void handleAfterDelete(){}
    public static void handleAfterUndelete(){}
    public static Invoice__c generateInvoice(Id projectId, Id accountId, Date invoiceStartDate, Date invoiceEndDate, Decimal workDoneAmount, Decimal prePaidAmount, String status, Boolean createRecord){
    // public static Invoice__c generateInvoice(Id projectId, Id accountId, Date invoiceStartDate, Date invoiceEndDate, Decimal invoiceTotal, String status, Boolean createRecord){
        Invoice__c newInvoice = new Invoice__c();
        newInvoice.Project__c = projectId;
        newInvoice.Invoiced_To__c = accountId;
        newInvoice.Invoice_Start_Date__c = invoiceStartDate == null ? Date.today().addDays(-30) : invoiceStartDate;
        newInvoice.Invoice_End_Date__c = invoiceEndDate == null ? Date.today().addDays(-2) : invoiceEndDate;
        newInvoice.Pre_Paid_Amount__c = prePaidAmount;
        newInvoice.Work_Done_Amount__c = workDoneAmount;
        // newInvoice.Invoice_Total__c = invoiceTotal;
        newInvoice.Status__c = status == null ? 'Created' : status;
        if(createRecord) insert newInvoice;
        return newInvoice;
    }
}