public inherited sharing class UserSelector extends BaseSelector {
    protected override SObjectType getSObjectType() {
        return User.SObjectType;
    }

    protected override List<String> getDefaultFields() {
        return new List<String>{ 'Name', 'Username', 'Email', 'IsActive', 'ProfileId', 'UserRoleId', 'ManagerId' };
    }

    public List<User> selectActiveByProfileId(Set<Id> profileIds) {
        return selectWhere(
            'IsActive = true AND ProfileId IN :profileIds',
            new Map<String, Object>{ 'profileIds' => profileIds }
        );
    }

    public List<User> selectByUsername(Set<String> usernames) {
        return selectWhere('Username IN :usernames', new Map<String, Object>{ 'usernames' => usernames });
    }
}
