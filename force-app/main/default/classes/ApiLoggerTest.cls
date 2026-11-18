@IsTest
private class ApiLoggerTest {
    private class CalloutMock implements HttpCalloutMock {
        private Integer status;
        private Boolean shouldThrow;
        public CalloutMock(Integer status, Boolean shouldThrow) {
            this.status = status;
            this.shouldThrow = shouldThrow;
        }
        public HttpResponse respond(HttpRequest request) {
            if (shouldThrow) {
                throw new CalloutException('Read timed out');
            }
            HttpResponse response = new HttpResponse();
            response.setStatusCode(status);
            response.setBody('{"access_token":"abc123","ok":true}');
            return response;
        }
    }

    private static HttpRequest request() {
        HttpRequest request = new HttpRequest();
        request.setEndpoint('https://api.example.com/pay?api_key=secret123&x=1');
        request.setMethod('POST');
        request.setBody('{"password":"hunter2","amount":5}');
        return request;
    }

    private static void setting(Boolean enabled, Boolean logBodies, Integer maxLength) {
        ApiLogger.settingOverride = new API_Log_Setting__mdt(
            Enabled__c = enabled,
            Log_Bodies__c = logBodies,
            Max_Body_Length__c = maxLength
        );
    }

    @IsTest
    static void outboundCallIsLoggedWithSecretsMasked() {
        Test.setMock(HttpCalloutMock.class, new CalloutMock(201, false));

        Test.startTest();
        HttpResponse response = ApiLogger.send(request(), 'Payments');
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.areEqual(201, response.getStatusCode());
        API_Log__c log = [
            SELECT Direction__c, Source__c, Context__c, Endpoint__c, Method__c, Status_Code__c,
                Success__c, Request_Body__c, Response_Body__c, User__c, Duration_Ms__c
            FROM API_Log__c
        ];
        Assert.areEqual('Outbound', log.Direction__c);
        Assert.areEqual('Apex Callout', log.Source__c);
        Assert.areEqual('Payments', log.Context__c);
        Assert.areEqual('POST', log.Method__c);
        Assert.areEqual(201, log.Status_Code__c);
        Assert.isTrue(log.Success__c);
        Assert.areEqual(UserInfo.getUserId(), log.User__c);
        Assert.isNotNull(log.Duration_Ms__c);
        Assert.isFalse(log.Endpoint__c.contains('secret123'), log.Endpoint__c);
        Assert.isFalse(log.Request_Body__c.contains('hunter2'), log.Request_Body__c);
        Assert.isTrue(log.Request_Body__c.contains('"amount":5'), log.Request_Body__c);
        Assert.isFalse(log.Response_Body__c.contains('abc123'), log.Response_Body__c);
    }

    @IsTest
    static void loggingDoesNotBlockLaterCallouts() {
        Test.setMock(HttpCalloutMock.class, new CalloutMock(200, false));

        Test.startTest();
        ApiLogger.send(request(), 'First');
        ApiLogger.send(request(), 'Second');
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.areEqual(2, [SELECT COUNT() FROM API_Log__c]);
    }

    @IsTest
    static void failedCalloutIsLoggedAndRethrown() {
        Test.setMock(HttpCalloutMock.class, new CalloutMock(0, true));

        Test.startTest();
        try {
            ApiLogger.send(request(), 'Payments');
            Assert.fail('Expected the callout failure to be rethrown');
        } catch (CalloutException e) {
            Assert.areEqual('Read timed out', e.getMessage());
        }
        Test.getEventBus().deliver();
        Test.stopTest();

        API_Log__c log = [SELECT Success__c, Error_Message__c FROM API_Log__c];
        Assert.isFalse(log.Success__c);
        Assert.areEqual('Read timed out', log.Error_Message__c);
    }

    @IsTest
    static void bodiesCanBeTurnedOffAndTruncated() {
        Test.setMock(HttpCalloutMock.class, new CalloutMock(200, false));
        setting(true, false, null);
        Test.startTest();
        ApiLogger.send(request(), 'NoBodies');
        setting(true, true, 8);
        ApiLogger.send(request(), 'Truncated');
        Test.getEventBus().deliver();
        Test.stopTest();

        Assert.isNull([SELECT Request_Body__c FROM API_Log__c WHERE Context__c = 'NoBodies'].Request_Body__c);
        Assert.isTrue([SELECT Request_Body__c FROM API_Log__c WHERE Context__c = 'Truncated'].Request_Body__c.length() <= 12);
    }

    @IsTest
    static void disabledSettingLogsNothing() {
        Test.setMock(HttpCalloutMock.class, new CalloutMock(200, false));
        setting(false, true, null);
        Test.startTest();
        ApiLogger.send(request(), 'Off');
        Test.getEventBus().deliver();
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM API_Log__c]);
    }

    @IsTest
    static void inboundCallIsLoggedWithHeadersMasked() {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/orders';
        request.httpMethod = 'POST';
        request.remoteAddress = '10.0.0.1';
        request.requestBody = Blob.valueOf('{"token":"abc","id":7}');
        request.headers.put('Authorization', 'Bearer abc');
        request.headers.put('Accept', 'application/json');
        RestResponse response = new RestResponse();
        response.statusCode = 201;
        response.responseBody = Blob.valueOf('{"created":true}');
        RestContext.request = request;
        RestContext.response = response;

        Test.startTest();
        ApiLogger.startInbound('Orders').finish();
        Test.getEventBus().deliver();
        Test.stopTest();

        API_Log__c log = [
            SELECT Direction__c, Source__c, Status_Code__c, Success__c, Client_Ip__c,
                Request_Headers__c, Request_Body__c, Response_Body__c
            FROM API_Log__c
        ];
        Assert.areEqual('Inbound', log.Direction__c);
        Assert.areEqual('Apex REST', log.Source__c);
        Assert.areEqual(201, log.Status_Code__c);
        Assert.isTrue(log.Success__c);
        Assert.areEqual('10.0.0.1', log.Client_Ip__c);
        Assert.isTrue(log.Request_Headers__c.contains('Authorization: ***'), log.Request_Headers__c);
        Assert.isTrue(log.Request_Headers__c.contains('Accept: application/json'), log.Request_Headers__c);
        Assert.isFalse(log.Request_Body__c.contains('abc'), log.Request_Body__c);
        Assert.areEqual('{"created":true}', log.Response_Body__c);
    }

    @IsTest
    static void inboundFailureIsRecordedAsServerError() {
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();

        Test.startTest();
        ApiLogger.Inbound call = ApiLogger.startInbound('Orders');
        call.fail(new DmlException('Insert failed'));
        call.finish();
        Test.getEventBus().deliver();
        Test.stopTest();

        API_Log__c log = [SELECT Status_Code__c, Success__c, Error_Message__c FROM API_Log__c];
        Assert.areEqual(500, log.Status_Code__c);
        Assert.isFalse(log.Success__c);
        Assert.areEqual('Insert failed', log.Error_Message__c);
    }

    @IsTest
    static void importerMapsEventLogRows() {
        String csv = '"EVENT_TYPE","URI","HTTP_METHOD","STATUS_CODE","CLIENT_IP","CLIENT_NAME","USER_ID_DERIVED","TIMESTAMP_DERIVED","RUN_TIME"\n'
            + '"RestApi","/services/data/v67.0/query","GET","200","10.0.0.2","Workbench","' + UserInfo.getUserId()
            + '","2026-11-05T10:15:30.000Z","42"\n'
            + '"RestApi","/services/data/v67.0/sobjects","POST","403","10.0.0.2","","not-an-id","","x"\n\n';
        Id fileId = '0AT000000000001AAA';

        Test.startTest();
        ApiEventLogImporter.importRows(csv, 'RestApi', fileId);
        ApiEventLogImporter.importRows(csv, 'RestApi', fileId);
        Test.stopTest();

        List<API_Log__c> logs = [
            SELECT Direction__c, Source__c, Context__c, Endpoint__c, Method__c, Status_Code__c, Success__c,
                Client_Ip__c, Client_Name__c, User__c, Logged_At__c, Duration_Ms__c
            FROM API_Log__c
            ORDER BY Status_Code__c
        ];
        Assert.areEqual(2, logs.size(), 'Importing the same file twice must not duplicate rows');
        Assert.areEqual('Inbound', logs[0].Direction__c);
        Assert.areEqual('Event Monitoring', logs[0].Source__c);
        Assert.areEqual('RestApi', logs[0].Context__c);
        Assert.areEqual('GET', logs[0].Method__c);
        Assert.isTrue(logs[0].Success__c);
        Assert.areEqual('Workbench', logs[0].Client_Name__c);
        Assert.areEqual(UserInfo.getUserId(), logs[0].User__c);
        Assert.areEqual(42, logs[0].Duration_Ms__c);
        Assert.isNotNull(logs[0].Logged_At__c);
        Assert.isFalse(logs[1].Success__c);
        Assert.isNull(logs[1].User__c);
    }

    @IsTest
    static void importerRunsCleanlyWithoutEventLogs() {
        Test.startTest();
        new ApiEventLogImporter.Scheduler().execute(null);
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM API_Log__c]);
    }

    @IsTest
    static void maskHandlesNullAndPlainText() {
        Assert.areEqual('', ApiLogger.mask(null));
        Assert.areEqual('plain text', ApiLogger.mask('plain text'));
        Assert.areEqual('password=***&x=1', ApiLogger.mask('password=abc&x=1'));
    }

    @IsTest
    static void purgeRemovesOnlyOldLogs() {
        API_Log__c oldLog = new API_Log__c(Direction__c = 'Outbound');
        insert oldLog;
        Test.setCreatedDate(oldLog.Id, Datetime.now().addDays(-40));
        API_Log__c newLog = new API_Log__c(Direction__c = 'Outbound');
        insert newLog;

        Test.startTest();
        new ApiLogPurge(30).execute((SchedulableContext) null);
        Test.stopTest();

        List<API_Log__c> remaining = [SELECT Id FROM API_Log__c];
        Assert.areEqual(1, remaining.size());
        Assert.areEqual(newLog.Id, remaining[0].Id);
    }
}
