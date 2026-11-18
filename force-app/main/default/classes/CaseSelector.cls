public inherited sharing class CaseSelector extends BaseSelector {
    protected override SObjectType getSObjectType() {
        return Case.SObjectType;
    }

    protected override List<String> getDefaultFields() {
        return new List<String>{
            'CaseNumber', 'Subject', 'Status', 'Priority', 'Origin', 'IsClosed', 'AccountId', 'ContactId', 'OwnerId'
        };
    }

    public List<Case> selectByAccountId(Set<Id> accountIds) {
        return selectWhere('AccountId IN :accountIds', new Map<String, Object>{ 'accountIds' => accountIds });
    }

    public List<Case> selectOpenByAccountId(Set<Id> accountIds) {
        return selectWhere(
            'IsClosed = false AND AccountId IN :accountIds',
            new Map<String, Object>{ 'accountIds' => accountIds }
        );
    }

    public List<Case> selectByContactId(Set<Id> contactIds) {
        return selectWhere('ContactId IN :contactIds', new Map<String, Object>{ 'contactIds' => contactIds });
    }
}
