@IsTest
private class SelectorTest {
    private static String firstOpenStage() {
        for (OpportunityStage stage : [SELECT ApiName FROM OpportunityStage WHERE IsActive = true AND IsClosed = false LIMIT 1]) {
            return stage.ApiName;
        }
        return null;
    }

    @TestSetup
    static void createRecords() {
        Account parent = new Account(Name = 'Selector Parent');
        insert parent;
        Account child = new Account(Name = 'Selector Child', ParentId = parent.Id);
        insert child;
        insert new Contact(LastName = 'Selector', Email = 'selector.test@example.com', AccountId = parent.Id);
        insert new Lead(LastName = 'Selector', Company = 'Selector Co', Email = 'selector.lead@example.com');
        insert new Opportunity(
            Name = 'Selector Opp',
            AccountId = parent.Id,
            StageName = firstOpenStage(),
            CloseDate = Date.today().addDays(30)
        );
        insert new Case(Subject = 'Selector Case', AccountId = parent.Id);
        insert new Task(Subject = 'Selector Task', WhatId = parent.Id, OwnerId = UserInfo.getUserId());
    }

    private static Id parentId() {
        return [SELECT Id FROM Account WHERE Name = 'Selector Parent' LIMIT 1].Id;
    }

    @IsTest
    static void baseOptionsShapeTheQuery() {
        BaseSelector selector = new AccountSelector()
            .withFields(new List<String>{ 'Owner.Name', 'name' })
            .orderBy('Name DESC')
            .withLimit(5);
        String soql = selector.buildQuery('Name != null');

        Assert.isTrue(soql.startsWith('SELECT Id, '), soql);
        Assert.isTrue(soql.contains('Owner.Name'), soql);
        Assert.areEqual(1, soql.substringBefore(' FROM ').toLowerCase().countMatches(' name,'), soql);
        Assert.isTrue(soql.endsWith('WHERE Name != null ORDER BY Name DESC LIMIT 5'), soql);
    }

    @IsTest
    static void selectByIdReturnsTypedRecords() {
        List<Account> accounts = new AccountSelector().selectById(new Set<Id>{ parentId() });
        Assert.areEqual('Selector Parent', accounts[0].Name);
    }

    @IsTest
    static void selectWhereWorksWithoutBinds() {
        List<Account> accounts = new AccountSelector().withSystemMode().selectWhere('Name = \'Selector Parent\'', null);
        Assert.areEqual(1, accounts.size());
    }

    @IsTest
    static void accountSelectorMethods() {
        Id parent = parentId();
        AccountSelector selector = new AccountSelector();
        Assert.areEqual(1, selector.selectByName(new Set<String>{ 'Selector Child' }).size());
        Assert.areEqual(1, selector.selectByParentId(new Set<Id>{ parent }).size());
        Assert.areEqual(1, selector.selectWithContacts(new Set<Id>{ parent })[0].Contacts.size());
    }

    @IsTest
    static void contactSelectorMethods() {
        ContactSelector selector = new ContactSelector();
        Assert.areEqual(1, selector.selectByAccountId(new Set<Id>{ parentId() }).size());
        Assert.areEqual(1, selector.selectByEmail(new Set<String>{ 'selector.test@example.com' }).size());
    }

    @IsTest
    static void leadSelectorMethods() {
        LeadSelector selector = new LeadSelector();
        Assert.areEqual(1, selector.selectByEmail(new Set<String>{ 'selector.lead@example.com' }).size());
        Assert.isFalse(selector.selectUnconvertedByOwnerId(new Set<Id>{ UserInfo.getUserId() }).isEmpty());
    }

    @IsTest
    static void opportunitySelectorMethods() {
        OpportunitySelector selector = new OpportunitySelector();
        Assert.areEqual(1, selector.selectByAccountId(new Set<Id>{ parentId() }).size());
        Assert.areEqual(1, selector.selectOpenByAccountId(new Set<Id>{ parentId() }).size());
    }

    @IsTest
    static void caseSelectorMethods() {
        CaseSelector selector = new CaseSelector();
        Assert.areEqual(1, selector.selectByAccountId(new Set<Id>{ parentId() }).size());
        Assert.areEqual(1, selector.selectOpenByAccountId(new Set<Id>{ parentId() }).size());
        Assert.isTrue(selector.selectByContactId(new Set<Id>{ UserInfo.getUserId() }).isEmpty());
    }

    @IsTest
    static void taskSelectorMethods() {
        TaskSelector selector = new TaskSelector();
        Assert.areEqual(1, selector.selectByWhatId(new Set<Id>{ parentId() }).size());
        Assert.isFalse(selector.selectOpenByOwnerId(new Set<Id>{ UserInfo.getUserId() }).isEmpty());
    }

    @IsTest
    static void userSelectorMethods() {
        UserSelector selector = new UserSelector();
        Assert.areEqual(1, selector.selectByUsername(new Set<String>{ UserInfo.getUserName() }).size());
        Assert.isFalse(selector.selectActiveByProfileId(new Set<Id>{ UserInfo.getProfileId() }).isEmpty());
    }
}
