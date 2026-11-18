/** Saves published API log entries. */
public without sharing class ApiLogEventHandler {
    public static void handle(List<API_Log_Event__e> events) {
        List<API_Log__c> logs = new List<API_Log__c>();
        for (API_Log_Event__e event : events) {
            logs.add(new API_Log__c(
                Direction__c = event.Direction__c,
                Source__c = event.Source__c,
                Context__c = event.Context__c,
                Endpoint__c = event.Endpoint__c,
                Method__c = event.Method__c,
                Status_Code__c = event.Status_Code__c,
                Success__c = event.Success__c,
                Duration_Ms__c = event.Duration_Ms__c,
                Request_Body__c = event.Request_Body__c,
                Response_Body__c = event.Response_Body__c,
                Request_Headers__c = event.Request_Headers__c,
                Error_Message__c = event.Error_Message__c,
                Client_Ip__c = event.Client_Ip__c,
                Request_Id__c = event.Request_Id__c,
                User__c = event.User_Id__c,
                Logged_At__c = event.Logged_At__c
            ));
        }
        for (Database.SaveResult result : Database.insert(logs, false)) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'API_Log__c insert failed: ' + result.getErrors());
            }
        }
    }
}
