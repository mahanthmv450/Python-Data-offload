/**
 * Records API traffic that passes through Apex.
 *
 * Outbound, replacing new Http().send(request):
 *     HttpResponse response = ApiLogger.send(request, 'Payments');
 *
 * Inbound, in an @RestResource class:
 *     ApiLogger.Inbound call = ApiLogger.startInbound('Orders');
 *     try { ... } catch (Exception e) { call.fail(e); throw e; } finally { call.finish(); }
 *
 * Platform events keep entries through a rollback and, because they publish
 * immediately, don't block later callouts the way a normal insert would.
 *
 * Traffic that bypasses Apex can't be seen here. ApiEventLogImporter covers it
 * where the org has Event Monitoring data.
 *
 * Secrets are masked and bodies truncated, but bodies can still hold personal
 * data. Turn off Log_Bodies__c on API_Log_Setting__mdt if that isn't acceptable.
 */
public without sharing class ApiLogger {
    private static final String DIRECTION_INBOUND = 'Inbound';
    private static final String DIRECTION_OUTBOUND = 'Outbound';
    private static final Integer DEFAULT_MAX_BODY = 32000;
    private static final String SECRET_PATTERN =
        '(?i)("?(?:password|passwd|secret|client_secret|token|access_token|refresh_token|api[_-]?key|apikey|authorization)"?\\s*[:=]\\s*"?)[^",&\\s}]+';
    private static final Set<String> SECRET_HEADERS = new Set<String>{
        'authorization', 'cookie', 'set-cookie', 'x-api-key', 'proxy-authorization'
    };

    @TestVisible
    private static API_Log_Setting__mdt settingOverride;

    public static HttpResponse send(HttpRequest request, String context) {
        Long startedAt = System.currentTimeMillis();
        API_Log_Event__e event = newEvent(DIRECTION_OUTBOUND, 'Apex Callout', context);
        event.Endpoint__c = mask(request.getEndpoint()).left(255);
        event.Method__c = request.getMethod();
        event.Request_Body__c = bodyForLog(request.getBody());

        try {
            HttpResponse response = new Http().send(request);
            event.Status_Code__c = response.getStatusCode();
            event.Success__c = response.getStatusCode() >= 200 && response.getStatusCode() < 300;
            event.Response_Body__c = bodyForLog(response.getBody());
            return response;
        } catch (Exception error) {
            event.Success__c = false;
            event.Error_Message__c = error.getMessage().left(32000);
            throw error;
        } finally {
            event.Duration_Ms__c = System.currentTimeMillis() - startedAt;
            publish(event);
        }
    }

    public static Inbound startInbound(String context) {
        return new Inbound(context);
    }

    public class Inbound {
        private String context;
        private Long startedAt = System.currentTimeMillis();
        private String errorMessage;

        private Inbound(String context) {
            this.context = context;
        }

        public void fail(Exception error) {
            errorMessage = error.getMessage();
        }

        /** Call from a finally block so failed requests are recorded too. */
        public void finish() {
            RestRequest request = RestContext.request;
            RestResponse response = RestContext.response;
            API_Log_Event__e event = newEvent(DIRECTION_INBOUND, 'Apex REST', context);
            if (request != null) {
                event.Endpoint__c = mask(request.requestURI).left(255);
                event.Method__c = request.httpMethod;
                event.Client_Ip__c = request.remoteAddress;
                event.Request_Headers__c = headersForLog(request.headers);
                event.Request_Body__c = bodyForLog(request.requestBody == null ? null : request.requestBody.toString());
            }
            Integer status = response != null && response.statusCode != null ? response.statusCode : 200;
            if (errorMessage != null && status < 400) {
                status = 500;
            }
            event.Status_Code__c = status;
            event.Success__c = errorMessage == null && status < 400;
            event.Error_Message__c = errorMessage == null ? null : errorMessage.left(32000);
            if (response != null && response.responseBody != null) {
                event.Response_Body__c = bodyForLog(response.responseBody.toString());
            }
            event.Duration_Ms__c = System.currentTimeMillis() - startedAt;
            publish(event);
        }
    }

    private static API_Log_Event__e newEvent(String direction, String source, String context) {
        return new API_Log_Event__e(
            Direction__c = direction,
            Source__c = source,
            Context__c = context == null ? null : context.left(80),
            User_Id__c = UserInfo.getUserId(),
            Request_Id__c = Request.getCurrent().getRequestId(),
            Logged_At__c = Datetime.now()
        );
    }

    private static void publish(API_Log_Event__e event) {
        if (!setting().Enabled__c) {
            return;
        }
        try {
            Database.SaveResult result = EventBus.publish(event);
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'ApiLogger publish failed: ' + result.getErrors());
            }
        } catch (Exception publishError) {
            System.debug(LoggingLevel.ERROR, 'ApiLogger publish failed: ' + publishError.getMessage());
        }
    }

    private static API_Log_Setting__mdt setting() {
        if (settingOverride != null) {
            return settingOverride;
        }
        API_Log_Setting__mdt configured = API_Log_Setting__mdt.getInstance('Default');
        return configured != null
            ? configured
            : new API_Log_Setting__mdt(Enabled__c = true, Log_Bodies__c = true, Max_Body_Length__c = DEFAULT_MAX_BODY);
    }

    private static String bodyForLog(String body) {
        API_Log_Setting__mdt current = setting();
        if (String.isBlank(body) || !current.Log_Bodies__c) {
            return null;
        }
        Integer maxLength = current.Max_Body_Length__c == null ? DEFAULT_MAX_BODY : current.Max_Body_Length__c.intValue();
        return mask(body.left(maxLength));
    }

    private static String headersForLog(Map<String, String> headers) {
        if (headers == null) {
            return null;
        }
        List<String> lines = new List<String>();
        for (String name : headers.keySet()) {
            lines.add(name + ': ' + (SECRET_HEADERS.contains(name.toLowerCase()) ? '***' : headers.get(name)));
        }
        return String.join(lines, '\n').left(32000);
    }

    /** Drops text it can't safely mask: a secret must never reach the log. */
    @TestVisible
    private static String mask(String value) {
        if (value == null) {
            return '';
        }
        try {
            return value.replaceAll(SECRET_PATTERN, '$1***');
        } catch (Exception regexError) {
            return '[not logged: could not mask content]';
        }
    }
}
