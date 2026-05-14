public with sharing class OpportunityTriggerHandler extends TriggerHandler {

    private static final String STAGE_NEGOTIATION = 'Negotiation/Review';
    private static final String STAGE_CLOSED_WON  = 'Closed Won';
    private static final String TASK_STATUS_NOT_STARTED = 'Not Started';

    public class FlsException extends Exception {}

    protected override void afterUpdate() {
        Map<Id, Opportunity> oldMap = (Map<Id, Opportunity>) Trigger.oldMap;
        List<Opportunity> newList   = (List<Opportunity>) Trigger.new;

        List<Opportunity> negotiationOpps = new List<Opportunity>();
        List<Opportunity> closedWonOpps   = new List<Opportunity>();

        for (Opportunity opp : newList) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            if (oldOpp == null) {
                continue;
            }
            if (opp.IsDeleted) {
                continue;
            }
            if (opp.OwnerId == null) {
                continue;
            }
            if (opp.StageName == oldOpp.StageName) {
                continue;
            }
            if (opp.StageName == STAGE_NEGOTIATION) {
                negotiationOpps.add(opp);
            } else if (opp.StageName == STAGE_CLOSED_WON) {
                closedWonOpps.add(opp);
            }
        }

        if (negotiationOpps.isEmpty() && closedWonOpps.isEmpty()) {
            return;
        }

        // For Closed Won, we need: prior CW counts on each Account, and Account.OwnerId.
        Map<Id, Integer> priorCwCountByAccount = new Map<Id, Integer>();
        Map<Id, Account> accountById          = new Map<Id, Account>();

        if (!closedWonOpps.isEmpty()) {
            Set<Id> accountIds   = new Set<Id>();
            Set<Id> currentOppIds = new Set<Id>();
            for (Opportunity opp : closedWonOpps) {
                if (opp.AccountId != null) {
                    accountIds.add(opp.AccountId);
                }
                currentOppIds.add(opp.Id);
            }

            if (!accountIds.isEmpty()) {
                // SOQL #1: count prior Closed Won Opps per Account (exclude current).
                for (AggregateResult ar : [
                    SELECT AccountId acctId, COUNT(Id) cnt
                    FROM Opportunity
                    WHERE AccountId IN :accountIds
                      AND StageName = :STAGE_CLOSED_WON
                      AND Id NOT IN :currentOppIds
                    WITH USER_MODE
                    GROUP BY AccountId
                ]) {
                    priorCwCountByAccount.put(
                        (Id) ar.get('acctId'),
                        (Integer) ar.get('cnt')
                    );
                }

                // FLS precheck per ticket: Account.OwnerId must be readable.
                if (!Schema.sObjectType.Account.fields.OwnerId.isAccessible()) {
                    throw new FlsException(
                        'OpportunityTriggerHandler: running user lacks read access to Account.OwnerId; cannot create welcome Task.'
                    );
                }

                // SOQL #2: Account name + owner.
                accountById = new Map<Id, Account>([
                    SELECT Id, Name, OwnerId
                    FROM Account
                    WHERE Id IN :accountIds
                    WITH USER_MODE
                ]);
            }
        }

        // CRUD/FLS precheck on Task per ticket requirements (explicit, layered atop AccessLevel.USER_MODE on DML).
        assertTaskCreateable();

        List<Task> tasksToInsert = new List<Task>();

        Date today = Date.today();

        for (Opportunity opp : negotiationOpps) {
            tasksToInsert.add(new Task(
                Subject      = 'Draft proposal for ' + opp.Name,
                WhatId       = opp.Id,
                OwnerId      = opp.OwnerId,
                ActivityDate = addBusinessDays(today, 3),
                Status       = TASK_STATUS_NOT_STARTED
            ));
        }

        for (Opportunity opp : closedWonOpps) {
            // Always: thank-you Task on the Opp owner.
            tasksToInsert.add(new Task(
                Subject      = 'Send thank-you + invoice for ' + opp.Name,
                WhatId       = opp.Id,
                OwnerId      = opp.OwnerId,
                ActivityDate = addBusinessDays(today, 1),
                Status       = TASK_STATUS_NOT_STARTED
            ));

            // Conditionally: welcome Task on the Account owner, if first Closed Won and AccountId present.
            if (opp.AccountId == null) {
                continue;
            }
            Integer priorCw = priorCwCountByAccount.get(opp.AccountId);
            if (priorCw != null && priorCw > 0) {
                continue;
            }
            Account acct = accountById.get(opp.AccountId);
            if (acct == null || acct.OwnerId == null) {
                continue;
            }
            tasksToInsert.add(new Task(
                Subject      = 'Welcome new customer: ' + acct.Name,
                WhatId       = acct.Id,
                OwnerId      = acct.OwnerId,
                ActivityDate = addBusinessDays(today, 2),
                Status       = TASK_STATUS_NOT_STARTED
            ));
        }

        if (!tasksToInsert.isEmpty()) {
            // One DML for all Tasks. AccessLevel.USER_MODE re-enforces FLS/CRUD at the database layer
            // (atop the explicit prechecks above, which the ticket requires).
            Database.insert(tasksToInsert, AccessLevel.USER_MODE);
        }
    }

    private static void assertTaskCreateable() {
        if (!Schema.sObjectType.Task.isCreateable()) {
            throw new FlsException('OpportunityTriggerHandler: running user lacks Create permission on Task.');
        }
        Map<String, Schema.SObjectField> fmap = Schema.sObjectType.Task.fields.getMap();
        String[] requiredFields = new String[]{ 'Subject', 'WhatId', 'OwnerId', 'ActivityDate', 'Status' };
        for (String fname : requiredFields) {
            Schema.SObjectField f = fmap.get(fname);
            if (f == null || !f.getDescribe().isCreateable()) {
                throw new FlsException(
                    'OpportunityTriggerHandler: running user lacks Create permission on Task.' + fname + '.'
                );
            }
        }
    }

    private static Date addBusinessDays(Date startDate, Integer days) {
        Date d = startDate;
        Integer added = 0;
        while (added < days) {
            d = d.addDays(1);
            Datetime dt = Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0));
            String dow = dt.format('EEE');
            if (dow != 'Sat' && dow != 'Sun') {
                added++;
            }
        }
        return d;
    }
}
