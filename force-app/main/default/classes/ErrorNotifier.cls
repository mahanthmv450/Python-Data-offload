/**
 * Sends notifications for saved errors using Error_Notification_Rule__mdt.
 *
 * Each rule gets one message per batch, listing a sample of the matching errors,
 * so a burst of failures can't exhaust email limits or flood a channel.
 *
 * Rules stay silent in sandboxes unless Active_In_Sandbox__c is set, so a refreshed
 * sandbox can't alert production channels through the copied rules.
 *
 * This class reports its own failures on the log record, not through ErrorLogger,
 * so a broken channel can't start a loop of errors about errors.
 */
public without sharing class ErrorNotifier implements Queueable, Database.AllowsCallouts {
    private static final List<String> SEVERITY_ORDER = new List<String>{ 'INFO', 'WARNING', 'ERROR', 'CRITICAL' };
    private static final Integer SAMPLE_SIZE = 5;

    @TestVisible
    private static List<Error_Notification_Rule__mdt> rulesOverride;
    @TestVisible
    private static Boolean sandboxOverride;

    private Set<Id> logIds;

    public ErrorNotifier(Set<Id> logIds) {
        this.logIds = logIds;
    }

    public static Boolean hasActiveRules() {
        return !activeRules().isEmpty();
    }

    public void execute(QueueableContext context) {
        List<Error_Log__c> logs = [
            SELECT Id, Name, Context__c, Error_Code__c, Severity__c, Message__c, Notification_Status__c
            FROM Error_Log__c
            WHERE Id IN :logIds
        ];
        Map<Id, List<String>> statusByLog = new Map<Id, List<String>>();
        for (Error_Log__c log : logs) {
            statusByLog.put(log.Id, new List<String>());
        }

        // Webhooks go first: a callout after sendEmail fails with uncommitted work pending.
        List<Error_Notification_Rule__mdt> rules = activeRules();
        for (Error_Notification_Rule__mdt rule : rules) {
            if (rule.Channel__c != 'Email') {
                deliver(rule, logs, statusByLog);
            }
        }
        for (Error_Notification_Rule__mdt rule : rules) {
            if (rule.Channel__c == 'Email') {
                deliver(rule, logs, statusByLog);
            }
        }

        for (Error_Log__c log : logs) {
            List<String> statuses = statusByLog.get(log.Id);
            log.Notification_Status__c = statuses.isEmpty()
                ? 'No matching rule'
                : String.join(statuses, '; ').left(255);
        }
        update logs;
    }

    private static void deliver(
        Error_Notification_Rule__mdt rule,
        List<Error_Log__c> logs,
        Map<Id, List<String>> statusByLog
    ) {
        List<Error_Log__c> matched = new List<Error_Log__c>();
        for (Error_Log__c log : logs) {
            if (matches(rule, log)) {
                matched.add(log);
            }
        }
        if (matched.isEmpty()) {
            return;
        }

        String outcome;
        try {
            outcome = rule.Channel__c == 'Email' ? sendEmail(rule, matched) : sendWebhook(rule, matched);
        } catch (Exception error) {
            outcome = 'failed: ' + error.getMessage();
        }
        for (Error_Log__c log : matched) {
            statusByLog.get(log.Id).add(rule.Channel__c + ' ' + rule.Team__c + ' ' + outcome);
        }
    }

    @TestVisible
    private static Boolean matches(Error_Notification_Rule__mdt rule, Error_Log__c log) {
        return listIncludes(rule.Context__c, log.Context__c)
            && listIncludes(rule.Error_Code__c, log.Error_Code__c)
            && rank(log.Severity__c) >= rank(rule.Min_Severity__c);
    }

    /** A blank rule value matches everything. Otherwise the value must be in its comma-separated list. */
    private static Boolean listIncludes(String allowed, String value) {
        if (String.isBlank(allowed)) {
            return true;
        }
        for (String candidate : allowed.split(',')) {
            if (candidate.trim().equalsIgnoreCase(value)) {
                return true;
            }
        }
        return false;
    }

    private static Integer rank(String severity) {
        return String.isBlank(severity) ? 0 : SEVERITY_ORDER.indexOf(severity.toUpperCase());
    }

    private static List<Error_Notification_Rule__mdt> activeRules() {
        List<Error_Notification_Rule__mdt> candidates = rulesOverride != null
            ? rulesOverride
            : Error_Notification_Rule__mdt.getAll().values();
        Boolean sandbox = isSandbox();
        List<Error_Notification_Rule__mdt> active = new List<Error_Notification_Rule__mdt>();
        for (Error_Notification_Rule__mdt rule : candidates) {
            if (rule.Active__c && (!sandbox || rule.Active_In_Sandbox__c)) {
                active.add(rule);
            }
        }
        return active;
    }

    private static Boolean isSandbox() {
        return sandboxOverride != null ? sandboxOverride : [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
    }

    private static String sendWebhook(Error_Notification_Rule__mdt rule, List<Error_Log__c> logs) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint('callout:' + rule.Destination__c);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setTimeout(20000);
        String text = title(logs) + '\n' + details(logs);
        request.setBody(JSON.serialize(rule.Channel__c == 'Teams' ? teamsPayload(text) : new Map<String, Object>{ 'text' => text }));

        HttpResponse response = new Http().send(request);
        Integer status = response.getStatusCode();
        return status >= 200 && status < 300 ? 'sent' : 'failed: HTTP ' + status;
    }

    /** Adaptive Card, the format Teams Workflows webhooks accept. */
    private static Map<String, Object> teamsPayload(String text) {
        return new Map<String, Object>{
            'type' => 'message',
            'attachments' => new List<Object>{
                new Map<String, Object>{
                    'contentType' => 'application/vnd.microsoft.card.adaptive',
                    'content' => new Map<String, Object>{
                        '$schema' => 'http://adaptivecards.io/schemas/adaptive-card.json',
                        'type' => 'AdaptiveCard',
                        'version' => '1.4',
                        'body' => new List<Object>{
                            new Map<String, Object>{ 'type' => 'TextBlock', 'text' => text, 'wrap' => true }
                        }
                    }
                }
            }
        };
    }

    private static String sendEmail(Error_Notification_Rule__mdt rule, List<Error_Log__c> logs) {
        List<String> addresses = new List<String>();
        for (String address : rule.Destination__c.split(',')) {
            addresses.add(address.trim());
        }
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(addresses);
        email.setSubject(title(logs));
        email.setPlainTextBody(details(logs));
        Messaging.SendEmailResult result = Messaging.sendEmail(new List<Messaging.Email>{ email }, false)[0];
        return result.isSuccess() ? 'sent' : 'failed: ' + result.getErrors()[0].getMessage();
    }

    private static String title(List<Error_Log__c> logs) {
        String highest = 'INFO';
        for (Error_Log__c log : logs) {
            if (rank(log.Severity__c) > rank(highest)) {
                highest = log.Severity__c;
            }
        }
        return '[' + highest + '] ' + logs.size() + ' Salesforce error(s) in ' + UserInfo.getOrganizationName();
    }

    private static String details(List<Error_Log__c> logs) {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        List<String> lines = new List<String>();
        for (Integer index = 0; index < Math.min(logs.size(), SAMPLE_SIZE); index++) {
            Error_Log__c log = logs[index];
            lines.add(
                log.Name + ' | ' + log.Context__c + ' | ' + log.Error_Code__c + ' | '
                + (log.Message__c == null ? '' : log.Message__c.left(200))
                + '\n' + baseUrl + '/' + log.Id
            );
        }
        if (logs.size() > SAMPLE_SIZE) {
            lines.add('and ' + (logs.size() - SAMPLE_SIZE) + ' more');
        }
        return String.join(lines, '\n');
    }
}
