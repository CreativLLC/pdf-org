/**
 * Created by Charles on 11/17/2020.
 */

trigger InvoiceTrigger on Invoice__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    if(trigger.isBefore){
        if(trigger.isInsert) InvoiceUtils.handleBeforeInsert();
        else if(trigger.isUpdate) InvoiceUtils.handleBeforeUpdate();
        else if(trigger.isDelete) InvoiceUtils.handleBeforeDelete();
    }
    else if(trigger.isAfter){
        if(trigger.isInsert) InvoiceUtils.handleAfterInsert();
        else if(trigger.isUpdate) InvoiceUtils.handleAfterUpdate();
        else if(trigger.isDelete) InvoiceUtils.handleAfterDelete();
        else if(trigger.isUndelete) InvoiceUtils.handleAfterUndelete();
    }
}