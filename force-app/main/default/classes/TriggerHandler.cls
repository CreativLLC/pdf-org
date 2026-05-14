public abstract with sharing class TriggerHandler {
    public void run() {
        if (!isEnabled()) {
            return;
        }
        if (Trigger.isBefore && Trigger.isInsert) {
            beforeInsert();
        }
        if (Trigger.isBefore && Trigger.isUpdate) {
            beforeUpdate();
        }
        if (Trigger.isBefore && Trigger.isDelete) {
            beforeDelete();
        }
        if (Trigger.isAfter && Trigger.isInsert) {
            afterInsert();
        }
        if (Trigger.isAfter && Trigger.isUpdate) {
            afterUpdate();
        }
        if (Trigger.isAfter && Trigger.isDelete) {
            afterDelete();
        }
        if (Trigger.isAfter && Trigger.isUndelete) {
            afterUndelete();
        }
    }

    protected virtual Boolean isEnabled() {
        return true;
    }

    protected virtual void beforeInsert() {}
    protected virtual void beforeUpdate() {}
    protected virtual void beforeDelete() {}
    protected virtual void afterInsert() {}
    protected virtual void afterUpdate() {}
    protected virtual void afterDelete() {}
    protected virtual void afterUndelete() {}
}
