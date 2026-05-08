/**
 * Created by charl on 3/10/2023.
 */

trigger ContactRoleTrigger on Contact_Role__c (before insert, before update, before delete, after insert, after update, after delete, after undelete) {
    if(trigger.isBefore){
        if(trigger.isInsert) ContactRoleUtils.handleBeforeInsert();
        else if(trigger.isUpdate) ContactRoleUtils.handleBeforeUpdate();
        else if(trigger.isDelete) ContactRoleUtils.handleBeforeDelete();
    }
    else if(trigger.isAfter){
        if(trigger.isInsert) ContactRoleUtils.handleAfterInsert();
        else if(trigger.isUpdate) ContactRoleUtils.handleAfterUpdate();
        else if(trigger.isDelete) ContactRoleUtils.handleAfterDelete();
        else if(trigger.isUndelete) ContactRoleUtils.handleAfterUndelete();
    }
}