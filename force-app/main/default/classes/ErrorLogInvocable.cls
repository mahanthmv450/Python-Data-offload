/** Lets a Flow fault path write to the error log. */
public without sharing class ErrorLogInvocable {
    public class Input {
        @InvocableVariable(label='Message' required=true)
        public String message;
        @InvocableVariable(label='Context' description='Business area, used for routing. Example: Billing')
        public String context;
        @InvocableVariable(label='Error Code')
        public String errorCode;
        @InvocableVariable(label='Severity' description='INFO, WARNING, ERROR or CRITICAL. Defaults to ERROR.')
        public String severity;
        @InvocableVariable(label='Record Id')
        public Id recordId;
    }

    @InvocableMethod(label='Log Error' category='Logging' description='Writes an entry to the error log')
    public static void logErrors(List<Input> inputs) {
        for (Input input : inputs) {
            ErrorLogger.log(input.message, input.context, input.errorCode, toSeverity(input.severity), input.recordId);
        }
    }

    private static ErrorLogger.Severity toSeverity(String value) {
        for (ErrorLogger.Severity level : ErrorLogger.Severity.values()) {
            if (level.name().equalsIgnoreCase(value)) {
                return level;
            }
        }
        return ErrorLogger.Severity.ERROR;
    }
}
