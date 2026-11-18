public inherited sharing class TaskSelector extends BaseSelector {
    protected override SObjectType getSObjectType() {
        return Task.SObjectType;
    }

    protected override List<String> getDefaultFields() {
        return new List<String>{
            'Subject', 'Status', 'Priority', 'ActivityDate', 'IsClosed', 'WhatId', 'WhoId', 'OwnerId'
        };
    }

    public List<Task> selectByWhatId(Set<Id> whatIds) {
        return selectWhere('WhatId IN :whatIds', new Map<String, Object>{ 'whatIds' => whatIds });
    }

    public List<Task> selectOpenByOwnerId(Set<Id> ownerIds) {
        return selectWhere(
            'IsClosed = false AND OwnerId IN :ownerIds',
            new Map<String, Object>{ 'ownerIds' => ownerIds }
        );
    }
}
