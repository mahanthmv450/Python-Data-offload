public inherited sharing class AccountSelector extends BaseSelector {
    protected override SObjectType getSObjectType() {
        return Account.SObjectType;
    }

    protected override List<String> getDefaultFields() {
        return new List<String>{
            'Name', 'Type', 'Industry', 'Phone', 'Website', 'OwnerId', 'ParentId', 'BillingCity', 'BillingCountry'
        };
    }

    public List<Account> selectByName(Set<String> names) {
        return selectWhere('Name IN :names', new Map<String, Object>{ 'names' => names });
    }

    public List<Account> selectByParentId(Set<Id> parentIds) {
        return selectWhere('ParentId IN :parentIds', new Map<String, Object>{ 'parentIds' => parentIds });
    }

    public List<Account> selectWithContacts(Set<Id> ids) {
        withFields(new List<String>{ '(SELECT Id, Name, Email FROM Contacts)' });
        return selectById(ids);
    }
}
