/**
 * Copies Event Monitoring data into API_Log__c. This covers traffic that never
 * runs custom Apex, such as standard REST, SOAP and Bulk API calls.
 *
 * Schedule: System.schedule('API event log import', '0 0 5 * * ?', new ApiEventLogImporter.Scheduler());
 *
 * Event log files are hourly-to-daily batches, so entries arrive about a day late.
 * ApiTotalUsage is free in most orgs; the other event types need Event Monitoring.
 * Each file gets its own queueable run to stay within heap limits, and rows are
 * keyed by file and row number, so running twice can't create duplicates.
 */
public without sharing class ApiEventLogImporter implements Queueable {
    private static final Map<String, String> DIRECTION_BY_EVENT = new Map<String, String>{
        'ApiTotalUsage' => 'Inbound',
        'API' => 'Inbound',
        'RestApi' => 'Inbound',
        'BulkApi' => 'Inbound',
        'BulkApi2' => 'Inbound',
        'ApexRestApi' => 'Inbound',
        'ApexSoap' => 'Inbound',
        'ApexCallout' => 'Outbound',
        'ExternalCustomApexCallout' => 'Outbound',
        'ExternalODataCallout' => 'Outbound'
    };
    private static final Integer MAX_FILE_BYTES = 4000000;
    private static final Integer MAX_ROWS = 5000;

    private List<Id> pendingFileIds;

    public ApiEventLogImporter() {}

    private ApiEventLogImporter(List<Id> pendingFileIds) {
        this.pendingFileIds = pendingFileIds;
    }

    /** Separate because one class can't be both Queueable and Schedulable. */
    public class Scheduler implements Schedulable {
        public void execute(SchedulableContext context) {
            System.enqueueJob(new ApiEventLogImporter());
        }
    }

    public void execute(QueueableContext context) {
        if (pendingFileIds == null) {
            pendingFileIds = findFiles();
        }
        if (pendingFileIds.isEmpty()) {
            return;
        }
        EventLogFile file = [
            SELECT Id, EventType, LogFile, LogFileLength
            FROM EventLogFile
            WHERE Id = :pendingFileIds.remove(0)
        ];
        if (file.LogFileLength <= MAX_FILE_BYTES) {
            importRows(file.LogFile.toString(), file.EventType, file.Id);
        } else {
            System.debug(LoggingLevel.WARN, 'Skipped oversized event log file ' + file.Id);
        }
        if (!pendingFileIds.isEmpty() && !Test.isRunningTest()) {
            System.enqueueJob(new ApiEventLogImporter(pendingFileIds));
        }
    }

    private static List<Id> findFiles() {
        Set<String> eventTypes = DIRECTION_BY_EVENT.keySet();
        return new List<Id>(new Map<Id, EventLogFile>([
            SELECT Id
            FROM EventLogFile
            WHERE EventType IN :eventTypes AND Interval = 'Daily' AND LogDate >= LAST_N_DAYS:2
        ]).keySet());
    }

    @TestVisible
    private static void importRows(String csv, String eventType, Id fileId) {
        List<API_Log__c> logs = new List<API_Log__c>();
        List<Map<String, String>> rows = parseCsv(csv);
        for (Integer index = 0; index < Math.min(rows.size(), MAX_ROWS); index++) {
            logs.add(toLog(rows[index], eventType, fileId + '|' + index));
        }
        if (rows.size() > MAX_ROWS) {
            System.debug(LoggingLevel.WARN, 'Imported the first ' + MAX_ROWS + ' of ' + rows.size() + ' rows from ' + fileId);
        }
        for (Database.UpsertResult result : Database.upsert(logs, API_Log__c.External_Id__c, false)) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'API_Log__c import failed: ' + result.getErrors());
            }
        }
    }

    private static API_Log__c toLog(Map<String, String> row, String eventType, String externalId) {
        String status = firstValue(row, new List<String>{ 'STATUS_CODE', 'HTTP_STATUS_CODE' });
        Decimal statusCode = status != null && status.isNumeric() ? Decimal.valueOf(status) : null;
        String duration = firstValue(row, new List<String>{ 'RUN_TIME', 'TIME' });
        String userId = firstValue(row, new List<String>{ 'USER_ID_DERIVED', 'USER_ID' });
        String timestamp = firstValue(row, new List<String>{ 'TIMESTAMP_DERIVED' });
        String endpoint = firstValue(row, new List<String>{ 'URI', 'URL', 'API_RESOURCE', 'ENTITY_NAME' });
        return new API_Log__c(
            External_Id__c = externalId,
            Direction__c = DIRECTION_BY_EVENT.get(eventType),
            Source__c = 'Event Monitoring',
            Context__c = eventType,
            Endpoint__c = endpoint == null ? null : endpoint.left(255),
            Method__c = firstValue(row, new List<String>{ 'HTTP_METHOD', 'METHOD', 'METHOD_NAME' }),
            Status_Code__c = statusCode,
            Success__c = statusCode != null && statusCode < 400,
            Duration_Ms__c = duration != null && duration.isNumeric() ? Decimal.valueOf(duration) : null,
            Client_Ip__c = firstValue(row, new List<String>{ 'CLIENT_IP' }),
            Client_Name__c = firstValue(row, new List<String>{ 'CLIENT_NAME', 'CONNECTED_APP_ID' }),
            Request_Id__c = firstValue(row, new List<String>{ 'REQUEST_ID' }),
            User__c = userId instanceof Id ? (Id) userId : null,
            Logged_At__c = timestamp == null ? null : (Datetime) JSON.deserialize('"' + timestamp + '"', Datetime.class)
        );
    }

    private static String firstValue(Map<String, String> row, List<String> columns) {
        for (String column : columns) {
            if (String.isNotBlank(row.get(column))) {
                return row.get(column);
            }
        }
        return null;
    }

    /** Event log CSV quotes every value, which keeps this split simple. */
    @TestVisible
    private static List<Map<String, String>> parseCsv(String csv) {
        List<Map<String, String>> rows = new List<Map<String, String>>();
        List<String> lines = csv.replace('\r', '').split('\n');
        List<String> headers = splitLine(lines[0]);
        for (Integer index = 1; index < lines.size(); index++) {
            if (String.isBlank(lines[index])) {
                continue;
            }
            List<String> values = splitLine(lines[index]);
            Map<String, String> row = new Map<String, String>();
            for (Integer column = 0; column < Math.min(headers.size(), values.size()); column++) {
                row.put(headers[column], values[column]);
            }
            rows.add(row);
        }
        return rows;
    }

    private static List<String> splitLine(String line) {
        return line.trim().removeStart('"').removeEnd('"').split('","', -1);
    }
}
