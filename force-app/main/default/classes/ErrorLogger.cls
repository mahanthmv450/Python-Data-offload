/**
 * Records errors from Apex. Entries go through a platform event that publishes
 * immediately, so they are kept even when the failing transaction rolls back.
 *
 *   catch (Exception e) {
 *       ErrorLogger.log(e, 'Billing', 'BILL-001', ErrorLogger.Severity.CRITICAL, invoice.Id);
 *       throw e;
 *   }
 *
 * Context and error code drive routing: see Error_Notification_Rule__mdt.
 * Logging never throws, so it can't turn a handled error into a new failure.
 */
public without sharing class ErrorLogger {
    public enum Severity { INFO, WARNING, ERROR, CRITICAL }

    public static void log(Exception error) {
        log(error, null, null, Severity.ERROR, null);
    }

    public static void log(Exception error, String context) {
        log(error, context, null, Severity.ERROR, null);
    }

    public static void log(Exception error, String context, String errorCode, Severity level, Id recordId) {
        Error_Log_Event__e event = newEvent(error.getMessage(), context, errorCode, level, recordId);
        event.Exception_Type__c = error.getTypeName();
        event.Stack_Trace__c = error.getStackTraceString();
        publish(event);
    }

    /** For a problem that is not an exception, such as a rejected response. */
    public static void log(String message, String context, String errorCode, Severity level, Id recordId) {
        publish(newEvent(message, context, errorCode, level, recordId));
    }

    private static Error_Log_Event__e newEvent(
        String message,
        String context,
        String errorCode,
        Severity level,
        Id recordId
    ) {
        Request current = Request.getCurrent();
        return new Error_Log_Event__e(
            Message__c = message == null ? null : message.left(32768),
            Context__c = context == null ? null : context.left(80),
            Error_Code__c = errorCode == null ? null : errorCode.left(80),
            Severity__c = (level == null ? Severity.ERROR : level).name(),
            Record_Id__c = recordId,
            User_Id__c = UserInfo.getUserId(),
            Request_Id__c = current.getRequestId(),
            Quiddity__c = String.valueOf(current.getQuiddity())
        );
    }

    private static void publish(Error_Log_Event__e event) {
        try {
            Database.SaveResult result = EventBus.publish(event);
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'ErrorLogger publish failed: ' + result.getErrors());
            }
        } catch (Exception publishError) {
            System.debug(LoggingLevel.ERROR, 'ErrorLogger publish failed: ' + publishError.getMessage());
        }
    }
}
