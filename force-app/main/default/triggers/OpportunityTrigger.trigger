/*
The one and only Opportunity Trigger
	- Test Classes: RateQuoteController, SupportQuoteController, InvoiceCreationController
	- 1/6/2013 - Initial  Version - Charles Howard
*/
trigger OpportunityTrigger on Opportunity (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    if(trigger.isBefore){
        if(trigger.isInsert) OpportunityUtils.handleBeforeInsert();
        else if(trigger.isUpdate) OpportunityUtils.handleBeforeUpdate();
        else if(trigger.isDelete) OpportunityUtils.handleBeforeDelete();
    }
    else if(trigger.isAfter){
        if(trigger.isInsert) OpportunityUtils.handleAfterInsert();
        else if(trigger.isUpdate) OpportunityUtils.handleAfterUpdate();
        else if(trigger.isDelete) OpportunityUtils.handleAfterDelete();
        else if(trigger.isUndelete) OpportunityUtils.handleAfterUndelete();
    }  
}