/**
 * Created by Charles on 11/17/2020.
 */
trigger ProjectTrigger on Project__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
	if(trigger.isBefore){
        if(trigger.isInsert) ProjectUtils.handleBeforeInsert();
        else if(trigger.isUpdate) ProjectUtils.handleBeforeUpdate();
        else if(trigger.isDelete) ProjectUtils.handleBeforeDelete();
    }
    else if(trigger.isAfter){
        if(trigger.isInsert) ProjectUtils.handleAfterInsert();
        else if(trigger.isUpdate) ProjectUtils.handleAfterUpdate();
        else if(trigger.isDelete) ProjectUtils.handleAfterDelete();
        else if(trigger.isUndelete) ProjectUtils.handleAfterUndelete();
    }  
}