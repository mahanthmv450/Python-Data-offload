@IsTest
private class ErrorLoggerTest {
    private class WebhookMock implements HttpCalloutMock {
        public Integer status;
        public List<HttpRequest> requests = new List<HttpRequest>();
        public WebhookMock(Integer status) {
            this.status = status;
        }
        public HttpResponse respond(HttpRequest request) {
            requests.add(request);
            HttpResponse response = new HttpResponse();
            response.setStatusCode(status);
            return response;
        }
    }

    private static Error_Notification_Rule__mdt rule(String channel, String context, String minSeverity) {
        return new Error_Notification_Rule__mdt(
            Active__c = true,
            Active_In_Sandbox__c = false,
            Channel__c = channel,
            Context__c = context,
            Min_Severity__c = minSeverity,
            Destination__c = channel == 'Email' ? 'ops@example.com' : 'Ops_Webhook',
            Team__c = 'Ops'
        );
    }

    private static Error_Log__c savedLog(String context, String severity) {
        Error_Log__c log = new Error_Log__c(Context__c = context, Severity__c = severity, Message__c = 'Boom');
        insert log;
        return log;
    }

    private static String statusOf(Id logId) {
        return [SELECT Notification_Status__c FROM Error_Log__c WHERE Id = :logId].Notification_Status__c;
    }

    @IsTest
    static void exceptionIsSavedWithDetails() {
        ErrorNotifier.rulesOverride = new List<Error_Notification_Rule__mdt>();
        Id accountId = '001000000000001AAA';

        Test.startTest();
        ErrorLogger.log(new DmlException('Boom'), 'Billing', 'BILL-001', ErrorLogger.Severity.CRITICAL, accountId);
        Test.getEventBus().deliver();
        Test.stopTest();

        Error_Log__c log = [
            SELECT Context__c, Error_Code__c, Severity__c, Message__c, Exception_Type__c, Record_Id__c, User__c
            FROM Error_Log__c
        ];
        Assert.areEqual('Billing', log.Context__c);
        Assert.areEqual('BILL-001', log.Error_Code__c);
        Assert.areEqual('CRITICAL', log.Severity__c);
        Assert.areEqual('Boom', log.Message__c);
        Assert.areEqual('System.DmlException', log.Exception_Type__c);
        Assert.areEqual(String.valueOf(accountId), log.Record_Id__c);
        Assert.areEqual(UserInfo.getUserId(), log.User__c);
    }

    @IsTest
    static void shortOverloadsDefaultToErrorSeverity() {
        ErrorNotifier.rulesOverride = new List<Error_Notification_Rule__mdt>();
        Test.startTest();
        ErrorLogger.log(new DmlException('One'));
        ErrorLogger.log(new DmlException('Two'), 'Billing');
        ErrorLogger.log('Three', 'Billing', null, null, null);
        Test.getEventBus().deliver();
        Test.stopTest();
        Assert.areEqual(3, [SELECT COUNT() FROM Error_Log__c WHERE Severity__c = 'ERROR']);
    }

    @IsTest
    static void logSurvivesRollback() {
        ErrorNotifier.rulesOverride = new List<Error_Notification_Rule__mdt>();
        Test.startTest();
        Savepoint savepoint = Database.setSavepoint();
        ErrorLogger.log('Before rollback', 'Billing', null, ErrorLogger.Severity.ERROR, null);
        Database.rollback(savepoint);
        Test.getEventBus().deliver();
        Test.stopTest();
        Assert.areEqual(1, [SELECT COUNT() FROM Error_Log__c]);
    }

    @IsTest
    static void handlerQueuesNotifierWhenRulesExist() {
        ErrorNotifier.rulesOverride = new List<Error_Notification_Rule__mdt>{ rule('Slack', null, null) };
        ErrorNotifier.sandboxOverride = false;
        Test.setMock(HttpCalloutMock.class, new WebhookMock(200));

        Test.startTest();
        ErrorLogger.log('Queued', 'Billing', null, ErrorLogger.Severity.ERROR, null);
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'ErrorNotifier']);
    }

    @IsTest
    static void rulesMatchOnContextCodeAndSeverity() {
        Error_Log__c log = new Error_Log__c(Context__c = 'Billing', Error_Code__c = 'B1', Severity__c = 'ERROR');

        Assert.isTrue(ErrorNotifier.matches(rule('Slack', null, null), log), 'A blank rule matches everything');
        Assert.isTrue(ErrorNotifier.matches(rule('Slack', 'Sales, billing', 'WARNING'), log));
        Assert.isFalse(ErrorNotifier.matches(rule('Slack', 'Sales', null), log));
        Assert.isFalse(ErrorNotifier.matches(rule('Slack', null, 'CRITICAL'), log));

        Error_Notification_Rule__mdt codeRule = rule('Slack', null, null);
        codeRule.Error_Code__c = 'B2';
        Assert.isFalse(ErrorNotifier.matches(codeRule, log));
    }

    @IsTest
    static void slackReceivesOneMessagePerBatch() {
        ErrorNotifier.rulesOverride = new List<Error_Notification_Rule__mdt>{ rule('Slack', 'Billing', null) };
        ErrorNotifier.sandboxOverride = false;
        WebhookMock mock = new WebhookMock(200);
        Test.setMock(HttpCalloutMock.class, mock);
        Set<Id> ids = new Set<Id>();
        for (Integer index = 0; index < 7; index++) {
            ids.add(savedLog('Billing', 'ERROR').Id);
        }

        Test.startTest();
        new ErrorNotifier(ids).execute(null);
        Test.stopTest();

        Assert.areEqual(1, mock.requests.size());
        Assert.areEqual('callout:Ops_Webhook', mock.requests[0].getEndpoint());
        Assert.isTrue(mock.requests[0].getBody().contains('and 2 more'));
        Assert.areEqual('Slack Ops sent', statusOf(new List<Id>(ids)[0]));
    }

    @IsTest
    static void teamsReceivesAdaptiveCard() {
        ErrorNotifier.rulesOverride = new List<Error_Notification_Rule__mdt>{ rule('Teams', null, null) };
        ErrorNotifier.sandboxOverride = false;
        WebhookMock mock = new WebhookMock(202);
        Test.setMock(HttpCalloutMock.class, mock);
        Error_Log__c log = savedLog('Billing', 'CRITICAL');

        Test.startTest();
        new ErrorNotifier(new Set<Id>{ log.Id }).execute(null);
        Test.stopTest();

        Assert.isTrue(mock.requests[0].getBody().contains('AdaptiveCard'));
        Assert.areEqual('Teams Ops sent', statusOf(log.Id));
    }

    @IsTest
    static void emailRunsAfterWebhooks() {
        ErrorNotifier.rulesOverride = new List<Error_Notification_Rule__mdt>{
            rule('Email', null, null),
            rule('Slack', null, null)
        };
        ErrorNotifier.sandboxOverride = false;
        WebhookMock mock = new WebhookMock(200);
        Test.setMock(HttpCalloutMock.class, mock);
        Error_Log__c log = savedLog('Billing', 'ERROR');

        Test.startTest();
        new ErrorNotifier(new Set<Id>{ log.Id }).execute(null);
        Test.stopTest();

        String status = statusOf(log.Id);
        Assert.isTrue(status.startsWith('Slack Ops sent; Email Ops'), status);
    }

    @IsTest
    static void failedWebhookIsRecordedOnTheLog() {
        ErrorNotifier.rulesOverride = new List<Error_Notification_Rule__mdt>{ rule('Slack', null, null) };
        ErrorNotifier.sandboxOverride = false;
        Test.setMock(HttpCalloutMock.class, new WebhookMock(500));
        Error_Log__c log = savedLog('Billing', 'ERROR');

        Test.startTest();
        new ErrorNotifier(new Set<Id>{ log.Id }).execute(null);
        Test.stopTest();

        Assert.areEqual('Slack Ops failed: HTTP 500', statusOf(log.Id));
    }

    @IsTest
    static void sandboxStaysSilentUnlessRuleAllowsIt() {
        Error_Notification_Rule__mdt silent = rule('Slack', null, null);
        Error_Notification_Rule__mdt allowed = rule('Slack', null, null);
        allowed.Active_In_Sandbox__c = true;
        ErrorNotifier.sandboxOverride = true;

        ErrorNotifier.rulesOverride = new List<Error_Notification_Rule__mdt>{ silent };
        Assert.isFalse(ErrorNotifier.hasActiveRules());

        ErrorNotifier.rulesOverride = new List<Error_Notification_Rule__mdt>{ allowed };
        Assert.isTrue(ErrorNotifier.hasActiveRules());
    }

    @IsTest
    static void unmatchedLogIsMarked() {
        ErrorNotifier.rulesOverride = new List<Error_Notification_Rule__mdt>{ rule('Slack', 'Sales', null) };
        ErrorNotifier.sandboxOverride = false;
        Error_Log__c log = savedLog('Billing', 'INFO');

        Test.startTest();
        new ErrorNotifier(new Set<Id>{ log.Id }).execute(null);
        Test.stopTest();

        Assert.areEqual('No matching rule', statusOf(log.Id));
    }

    @IsTest
    static void flowActionLogsWithSeverity() {
        ErrorNotifier.rulesOverride = new List<Error_Notification_Rule__mdt>();
        ErrorLogInvocable.Input input = new ErrorLogInvocable.Input();
        input.message = 'Flow fault';
        input.context = 'Flow';
        input.severity = 'warning';
        ErrorLogInvocable.Input unknown = new ErrorLogInvocable.Input();
        unknown.message = 'Unknown severity';
        unknown.severity = 'nonsense';

        Test.startTest();
        ErrorLogInvocable.logErrors(new List<ErrorLogInvocable.Input>{ input, unknown });
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.areEqual(1, [SELECT COUNT() FROM Error_Log__c WHERE Severity__c = 'WARNING']);
        Assert.areEqual(1, [SELECT COUNT() FROM Error_Log__c WHERE Severity__c = 'ERROR']);
    }

    @IsTest
    static void purgeRemovesOnlyOldLogs() {
        Error_Log__c oldLog = savedLog('Billing', 'ERROR');
        Test.setCreatedDate(oldLog.Id, Datetime.now().addDays(-100));
        Error_Log__c newLog = savedLog('Billing', 'ERROR');

        Test.startTest();
        new ErrorLogPurge(90).execute((SchedulableContext) null);
        Test.stopTest();

        List<Error_Log__c> remaining = [SELECT Id FROM Error_Log__c];
        Assert.areEqual(1, remaining.size());
        Assert.areEqual(newLog.Id, remaining[0].Id);
    }
}
