@IsTest
private class TestDataFactoryTest {
    @IsTest
    static void buildDoesNotInsert() {
        List<Account> accounts = TestDataFactory.of(Account.SObjectType).withCount(3).build();
        Assert.areEqual(3, accounts.size());
        Assert.isNull(accounts[0].Id);
        Assert.isNotNull(accounts[0].Name, 'Required fields should be filled');
        Assert.areEqual(0, [SELECT COUNT() FROM Account]);
    }

    @IsTest
    static void createInsertsRecords() {
        List<Account> accounts = TestDataFactory.of(Account.SObjectType).withCount(2).create();
        Assert.isNotNull(accounts[0].Id);
        Assert.areEqual(2, [SELECT COUNT() FROM Account]);
    }

    @IsTest
    static void namesAreNumberedOnlyForSeveralRecords() {
        List<Account> several = TestDataFactory.of(Account.SObjectType).withName('Acme').withCount(2).build();
        Assert.areEqual('Acme 1', several[0].Name);
        Assert.areEqual('Acme 2', several[1].Name);

        Account single = (Account) TestDataFactory.of(Account.SObjectType).withName('Acme').buildOne();
        Assert.areEqual('Acme', single.Name);
    }

    @IsTest
    static void nameGoesToEachObjectsNameField() {
        Assert.areEqual('Smith', ((Contact) TestDataFactory.of(Contact.SObjectType).withName('Smith').buildOne()).LastName);
        Assert.areEqual('Issue', ((Case) TestDataFactory.of(Case.SObjectType).withName('Issue').buildOne()).Subject);
    }

    @IsTest
    static void fieldValuesOverrideDefaults() {
        Account byToken = (Account) TestDataFactory.of(Account.SObjectType)
            .withField(Account.Name, 'Token')
            .withField('Description', 'By name')
            .buildOne();
        Assert.areEqual('Token', byToken.Name);
        Assert.areEqual('By name', byToken.Description);
    }

    @IsTest
    static void fieldValueBeatsName() {
        Account record = (Account) TestDataFactory.of(Account.SObjectType)
            .withName('Named')
            .withFields(new Map<String, Object>{ 'Name' => 'Explicit' })
            .buildOne();
        Assert.areEqual('Explicit', record.Name);
    }

    @IsTest
    static void oneCallFormHonoursDoInsert() {
        Map<String, Object> values = new Map<String, Object>{ 'Description' => 'Set' };
        List<Account> built = TestDataFactory.make(Account.SObjectType, 'Built', 2, values, false);
        Assert.isNull(built[0].Id);
        Assert.areEqual('Set', built[0].Description);

        List<Account> saved = TestDataFactory.make(Account.SObjectType, 'Saved', 1, null, true);
        Assert.isNotNull(saved[0].Id);
    }

    @IsTest
    static void commonObjectsInsertWithDefaultsOnly() {
        Assert.isNotNull(TestDataFactory.of(Account.SObjectType).createOne().Id);
        Assert.isNotNull(TestDataFactory.of(Contact.SObjectType).createOne().Id);
        Assert.isNotNull(TestDataFactory.of(Lead.SObjectType).createOne().Id);
        Assert.isNotNull(TestDataFactory.of(Opportunity.SObjectType).createOne().Id);
        Assert.isNotNull(TestDataFactory.of(Case.SObjectType).createOne().Id);
        Assert.isNotNull(TestDataFactory.of(Task.SObjectType).createOne().Id);
    }

    @IsTest
    static void userIsBuiltWithRequiredSettings() {
        // Built, not inserted: inserting users can fail on license limits in small orgs.
        User record = (User) TestDataFactory.of(User.SObjectType).withName('Tester').buildOne();
        Assert.areEqual('Tester', record.LastName);
        Assert.areEqual(UserInfo.getProfileId(), record.ProfileId);
        Assert.isTrue(record.Username.endsWith('.invalid'));
    }

    @IsTest
    static void invalidCountIsRejected() {
        try {
            TestDataFactory.of(Account.SObjectType).withCount(0);
            Assert.fail('Expected an exception for a zero count');
        } catch (TestDataFactory.TestDataFactoryException e) {
            Assert.isTrue(e.getMessage().contains('at least 1'));
        }
    }

    @IsTest
    static void objectWithoutWritableNameIsRejected() {
        try {
            TestDataFactory.of(CaseComment.SObjectType).withName('No name field').build();
            Assert.fail('Expected an exception for an object with no name field');
        } catch (TestDataFactory.TestDataFactoryException e) {
            Assert.isTrue(e.getMessage().contains('no writable name field'));
        }
    }
}
