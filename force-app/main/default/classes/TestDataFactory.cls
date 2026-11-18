/**
 * Builds test records for any object. Required fields are filled from the org's
 * own schema, so new required fields and different picklist values don't break
 * tests. Required lookups can't be guessed: set them with withField().
 *
 *   List<Account> built = TestDataFactory.of(Account.SObjectType).withCount(5).build();
 *   List<Account> saved = TestDataFactory.of(Account.SObjectType)
 *       .withName('Acme')
 *       .withCount(3)
 *       .withField(Account.Industry, 'Technology')
 *       .create();
 *   Contact one = (Contact) TestDataFactory.of(Contact.SObjectType).withName('Smith').createOne();
 *
 * With a count above 1, names are numbered: Acme 1, Acme 2, Acme 3.
 */
@IsTest
public class TestDataFactory {
    private static final Map<SObjectType, String> NAME_FIELDS = new Map<SObjectType, String>{
        Contact.SObjectType => 'LastName',
        Lead.SObjectType => 'LastName',
        User.SObjectType => 'LastName',
        Case.SObjectType => 'Subject',
        Task.SObjectType => 'Subject',
        Event.SObjectType => 'Subject'
    };
    private static Map<SObjectType, List<DescribeFieldResult>> requiredFieldCache =
        new Map<SObjectType, List<DescribeFieldResult>>();
    private static Integer sequence = 0;

    public static Builder of(SObjectType objectType) {
        return new Builder(objectType);
    }

    /** One-call form. Pass doInsert = false to build without saving. */
    public static List<SObject> make(
        SObjectType objectType,
        String name,
        Integer count,
        Map<String, Object> fieldValues,
        Boolean doInsert
    ) {
        Builder builder = of(objectType).withName(name).withCount(count).withFields(fieldValues);
        return doInsert ? builder.create() : builder.build();
    }

    public class Builder {
        private SObjectType objectType;
        private String recordName;
        private Integer recordCount = 1;
        private Map<String, Object> fieldValues = new Map<String, Object>();

        private Builder(SObjectType objectType) {
            this.objectType = objectType;
        }

        public Builder withName(String name) {
            recordName = name;
            return this;
        }

        public Builder withCount(Integer count) {
            if (count == null || count < 1) {
                throw new TestDataFactoryException('Record count must be at least 1.');
            }
            recordCount = count;
            return this;
        }

        public Builder withField(SObjectField field, Object value) {
            return withField(String.valueOf(field), value);
        }

        public Builder withField(String fieldApiName, Object value) {
            fieldValues.put(fieldApiName, value);
            return this;
        }

        public Builder withFields(Map<String, Object> values) {
            if (values != null) {
                fieldValues.putAll(values);
            }
            return this;
        }

        /** Returns records without saving them. */
        public List<SObject> build() {
            List<SObject> records = (List<SObject>) Type.forName(
                'List<' + String.valueOf(objectType) + '>'
            ).newInstance();
            for (Integer index = 0; index < recordCount; index++) {
                records.add(buildRecord(index));
            }
            return records;
        }

        /** Returns saved records. */
        public List<SObject> create() {
            List<SObject> records = build();
            insert records;
            return records;
        }

        public SObject buildOne() {
            return withCount(1).build()[0];
        }

        public SObject createOne() {
            return withCount(1).create()[0];
        }

        private SObject buildRecord(Integer index) {
            SObject record = objectType.newSObject();
            for (DescribeFieldResult field : requiredFields(objectType)) {
                Object value = defaultValue(field);
                if (value != null) {
                    record.put(field.getName(), value);
                }
            }
            if (objectType == User.SObjectType) {
                applyUserDefaults(record);
            }
            if (recordName != null) {
                String numbered = recordCount > 1 ? recordName + ' ' + (index + 1) : recordName;
                record.put(nameField(objectType), numbered);
            }
            for (String fieldName : fieldValues.keySet()) {
                record.put(fieldName, fieldValues.get(fieldName));
            }
            return record;
        }
    }

    private static List<DescribeFieldResult> requiredFields(SObjectType objectType) {
        if (!requiredFieldCache.containsKey(objectType)) {
            List<DescribeFieldResult> required = new List<DescribeFieldResult>();
            for (SObjectField field : objectType.getDescribe().fields.getMap().values()) {
                DescribeFieldResult describe = field.getDescribe();
                if (describe.isCreateable() && !describe.isNillable() && !describe.isDefaultedOnCreate()) {
                    required.add(describe);
                }
            }
            requiredFieldCache.put(objectType, required);
        }
        return requiredFieldCache.get(objectType);
    }

    private static String nameField(SObjectType objectType) {
        if (NAME_FIELDS.containsKey(objectType)) {
            return NAME_FIELDS.get(objectType);
        }
        for (SObjectField field : objectType.getDescribe().fields.getMap().values()) {
            DescribeFieldResult describe = field.getDescribe();
            if (describe.isNameField() && describe.isCreateable()) {
                return describe.getName();
            }
        }
        throw new TestDataFactoryException(objectType + ' has no writable name field. Use withField() instead.');
    }

    private static Object defaultValue(DescribeFieldResult field) {
        sequence++;
        switch on field.getType() {
            when STRING, TEXTAREA, ENCRYPTEDSTRING {
                return ('Test ' + sequence).left(field.getLength());
            }
            when EMAIL {
                return 'test' + sequence + '@example.com';
            }
            when URL {
                return 'https://example.com/' + sequence;
            }
            when PHONE {
                return '555' + String.valueOf(sequence).leftPad(7, '0');
            }
            when PICKLIST, MULTIPICKLIST {
                return firstActiveValue(field);
            }
            when BOOLEAN {
                return false;
            }
            when DATE {
                return Date.today().addDays(30);
            }
            when DATETIME {
                return Datetime.now().addDays(30);
            }
            when INTEGER {
                return sequence;
            }
            when DOUBLE, CURRENCY, PERCENT {
                return Decimal.valueOf(sequence);
            }
            when else {
                return null;
            }
        }
    }

    private static String firstActiveValue(DescribeFieldResult field) {
        for (PicklistEntry entry : field.getPicklistValues()) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }

    private static void applyUserDefaults(SObject user) {
        sequence++;
        String unique = sequence + '.' + Datetime.now().getTime();
        user.put('Username', 'test.' + unique + '@example.com.invalid');
        user.put('Email', 'test.' + sequence + '@example.com');
        user.put('Alias', ('t' + sequence).left(8));
        user.put('ProfileId', UserInfo.getProfileId());
        user.put('EmailEncodingKey', 'UTF-8');
        user.put('LanguageLocaleKey', 'en_US');
        user.put('LocaleSidKey', 'en_US');
        user.put('TimeZoneSidKey', 'GMT');
    }

    public class TestDataFactoryException extends Exception {}
}
