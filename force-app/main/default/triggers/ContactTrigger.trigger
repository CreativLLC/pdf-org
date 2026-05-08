trigger ContactTrigger on Contact (before insert) {
	if(trigger.isBefore){
        if(trigger.isInsert) ContactUtils.handleBeforeInsert();
        else if(trigger.isUpdate) ContactUtils.handleBeforeUpdate();
        else if(trigger.isDelete) ContactUtils.handleBeforeDelete();
    }
    else if(trigger.isAfter){
        if(trigger.isInsert) ContactUtils.handleAfterInsert();
        else if(trigger.isUpdate) ContactUtils.handleAfterUpdate();
        else if(trigger.isDelete) ContactUtils.handleAfterDelete();
        else if(trigger.isUndelete) ContactUtils.handleAfterUndelete();
    }  
}