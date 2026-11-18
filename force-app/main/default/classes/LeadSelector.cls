public inherited sharing class LeadSelector extends BaseSelector {
    protected override SObjectType getSObjectType() {
        return Lead.SObjectType;
    }

    protected override List<String> getDefaultFields() {
        return new List<String>{
            'FirstName', 'LastName', 'Name', 'Company', 'Email', 'Phone', 'Status', 'LeadSource', 'IsConverted', 'OwnerId'
        };
    }

    public List<Lead> selectByEmail(Set<String> emails) {
        return selectWhere('Email IN :emails', new Map<String, Object>{ 'emails' => emails });
    }

    public List<Lead> selectUnconvertedByOwnerId(Set<Id> ownerIds) {
        return selectWhere(
            'IsConverted = false AND OwnerId IN :ownerIds',
            new Map<String, Object>{ 'ownerIds' => ownerIds }
        );
    }
}
