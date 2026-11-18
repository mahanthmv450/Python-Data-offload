public inherited sharing class ContactSelector extends BaseSelector {
    protected override SObjectType getSObjectType() {
        return Contact.SObjectType;
    }

    protected override List<String> getDefaultFields() {
        return new List<String>{ 'FirstName', 'LastName', 'Name', 'Email', 'Phone', 'Title', 'AccountId', 'OwnerId' };
    }

    public List<Contact> selectByAccountId(Set<Id> accountIds) {
        return selectWhere('AccountId IN :accountIds', new Map<String, Object>{ 'accountIds' => accountIds });
    }

    public List<Contact> selectByEmail(Set<String> emails) {
        return selectWhere('Email IN :emails', new Map<String, Object>{ 'emails' => emails });
    }
}
