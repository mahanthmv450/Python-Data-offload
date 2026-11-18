/**
 * Deletes old error logs so they don't fill org storage.
 * Schedule: System.schedule('Error log purge', '0 0 3 * * ?', new ErrorLogPurge(90));
 */
public without sharing class ErrorLogPurge implements Database.Batchable<SObject>, Schedulable {
    private Integer retentionDays;

    public ErrorLogPurge(Integer retentionDays) {
        this.retentionDays = retentionDays;
    }

    public void execute(SchedulableContext context) {
        Database.executeBatch(this, 2000);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Datetime cutoff = Datetime.now().addDays(-retentionDays);
        return Database.getQueryLocator([SELECT Id FROM Error_Log__c WHERE CreatedDate < :cutoff]);
    }

    public void execute(Database.BatchableContext context, List<Error_Log__c> logs) {
        delete logs;
    }

    public void finish(Database.BatchableContext context) {}
}
