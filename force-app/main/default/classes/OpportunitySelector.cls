public inherited sharing class OpportunitySelector extends BaseSelector {
    protected override SObjectType getSObjectType() {
        return Opportunity.SObjectType;
    }

    protected override List<String> getDefaultFields() {
        return new List<String>{
            'Name', 'AccountId', 'StageName', 'Amount', 'CloseDate', 'Probability', 'IsClosed', 'IsWon', 'OwnerId'
        };
    }

    public List<Opportunity> selectByAccountId(Set<Id> accountIds) {
        return selectWhere('AccountId IN :accountIds', new Map<String, Object>{ 'accountIds' => accountIds });
    }

    public List<Opportunity> selectOpenByAccountId(Set<Id> accountIds) {
        return selectWhere(
            'IsClosed = false AND AccountId IN :accountIds',
            new Map<String, Object>{ 'accountIds' => accountIds }
        );
    }
}
