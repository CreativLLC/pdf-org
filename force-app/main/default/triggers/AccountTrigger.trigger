trigger AccountTrigger on Account (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
	if(trigger.isBefore){
        if(trigger.isInsert) AccountUtils.handleBeforeInsert();
        else if(trigger.isUpdate) AccountUtils.handleBeforeUpdate();
        else if(trigger.isDelete) AccountUtils.handleBeforeDelete();
    }
    else if(trigger.isAfter){
        if(trigger.isInsert) AccountUtils.handleAfterInsert();
        else if(trigger.isUpdate) AccountUtils.handleAfterUpdate();
        else if(trigger.isDelete) AccountUtils.handleAfterDelete();
        else if(trigger.isUndelete) AccountUtils.handleAfterUndelete();
    }  
}