/**
 * Created by charl on 3/10/2023.
 */

trigger ProjectAllocationTrigger on Project_Allocation__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    if(trigger.isBefore){
        if(trigger.isInsert) ProjectAllocationUtils.handleBeforeInsert();
        else if(trigger.isUpdate) ProjectAllocationUtils.handleBeforeUpdate();
        else if(trigger.isDelete) ProjectAllocationUtils.handleBeforeDelete();
    }
    else if(trigger.isAfter){
        if(trigger.isInsert) ProjectAllocationUtils.handleAfterInsert();
        else if(trigger.isUpdate) ProjectAllocationUtils.handleAfterUpdate();
        else if(trigger.isDelete) ProjectAllocationUtils.handleAfterDelete();
        else if(trigger.isUndelete) ProjectAllocationUtils.handleAfterUndelete();
    }
}