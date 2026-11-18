/**
 * Deletes old API logs. Bodies make these records large, so keep retention short.
 * Schedule: System.schedule('API log purge', '0 30 3 * * ?', new ApiLogPurge(30));
 */
public without sharing class ApiLogPurge implements Database.Batchable<SObject>, Schedulable {
    private Integer retentionDays;

    public ApiLogPurge(Integer retentionDays) {
        this.retentionDays = retentionDays;
    }

    public void execute(SchedulableContext context) {
        Database.executeBatch(this, 2000);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Datetime cutoff = Datetime.now().addDays(-retentionDays);
        return Database.getQueryLocator([SELECT Id FROM API_Log__c WHERE CreatedDate < :cutoff]);
    }

    public void execute(Database.BatchableContext context, List<API_Log__c> logs) {
        delete logs;
    }

    public void finish(Database.BatchableContext context) {}
}
