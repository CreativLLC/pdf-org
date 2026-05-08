trigger TimeSheetTrigger on Time_Sheet__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
	if(trigger.isBefore){
        if(trigger.isInsert) TimeSheetUtils.beforeInsert();
        else if(trigger.isUpdate) TimeSheetUtils.beforeUpdate();
        // else if(trigger.isDelete) TimeSheetUtils.beforeDelete();
    }
    // else if(trigger.isAfter){
        // if(trigger.isInsert) TimeSheetUtils.afterInsert();
        // else if(trigger.isUpdate) TimeSheetUtils.afterUpdate();
        // else if(trigger.isDelete) TimeSheetUtils.afterDelete();
        // else if(trigger.isUndelete) TimeSheetUtils.afterUndelete();
    // }  
}