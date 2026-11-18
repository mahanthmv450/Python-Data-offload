/** Saves published errors, then hands them to ErrorNotifier for routing. */
public without sharing class ErrorLogEventHandler {
    public static void handle(List<Error_Log_Event__e> events) {
        List<Error_Log__c> logs = new List<Error_Log__c>();
        for (Error_Log_Event__e event : events) {
            logs.add(new Error_Log__c(
                Context__c = event.Context__c,
                Error_Code__c = event.Error_Code__c,
                Severity__c = event.Severity__c,
                Message__c = event.Message__c,
                Stack_Trace__c = event.Stack_Trace__c,
                Exception_Type__c = event.Exception_Type__c,
                Record_Id__c = event.Record_Id__c,
                User__c = event.User_Id__c,
                Request_Id__c = event.Request_Id__c,
                Quiddity__c = event.Quiddity__c
            ));
        }

        Set<Id> savedIds = new Set<Id>();
        for (Database.SaveResult result : Database.insert(logs, false)) {
            if (result.isSuccess()) {
                savedIds.add(result.getId());
            } else {
                System.debug(LoggingLevel.ERROR, 'Error_Log__c insert failed: ' + result.getErrors());
            }
        }
        if (!savedIds.isEmpty() && ErrorNotifier.hasActiveRules()) {
            System.enqueueJob(new ErrorNotifier(savedIds));
        }
    }
}
