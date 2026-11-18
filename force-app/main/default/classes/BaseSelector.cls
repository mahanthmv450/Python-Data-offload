/**
 * Base class for selectors, the one place an object's queries live.
 *
 * Queries run in user mode by default, so sharing, object access and field
 * access are enforced. A query that touches a field the user can't read throws
 * a QueryException. Call withSystemMode() only when code must see beyond the
 * running user's access.
 *
 * Conditions are SOQL text. Pass every value through binds, never by
 * concatenating it into the condition, or the query is open to SOQL injection.
 */
public abstract inherited sharing class BaseSelector {
    private AccessLevel queryAccess = AccessLevel.USER_MODE;
    private List<String> extraFields = new List<String>();
    private String orderByClause;
    private Integer rowLimit;

    protected abstract SObjectType getSObjectType();
    protected abstract List<String> getDefaultFields();

    /** Adds fields, relationship fields or subqueries to the default field list. */
    public BaseSelector withFields(List<String> fields) {
        extraFields.addAll(fields);
        return this;
    }

    public BaseSelector withSystemMode() {
        queryAccess = AccessLevel.SYSTEM_MODE;
        return this;
    }

    /** Example: orderBy('CreatedDate DESC'). */
    public BaseSelector orderBy(String clause) {
        orderByClause = clause;
        return this;
    }

    public BaseSelector withLimit(Integer maxRows) {
        rowLimit = maxRows;
        return this;
    }

    public List<SObject> selectById(Set<Id> ids) {
        return selectWhere('Id IN :ids', new Map<String, Object>{ 'ids' => ids });
    }

    /** Example: selectWhere('Name LIKE :term', new Map<String, Object>{ 'term' => 'Ac%' }). */
    public List<SObject> selectWhere(String condition, Map<String, Object> binds) {
        return Database.queryWithBinds(
            buildQuery(condition),
            binds == null ? new Map<String, Object>() : binds,
            queryAccess
        );
    }

    @TestVisible
    private String buildQuery(String condition) {
        String soql = 'SELECT ' + String.join(fieldList(), ', ') + ' FROM ' + String.valueOf(getSObjectType());
        if (String.isNotBlank(condition)) {
            soql += ' WHERE ' + condition;
        }
        if (String.isNotBlank(orderByClause)) {
            soql += ' ORDER BY ' + orderByClause;
        }
        if (rowLimit != null) {
            soql += ' LIMIT ' + rowLimit;
        }
        return soql;
    }

    private List<String> fieldList() {
        Map<String, String> uniqueFields = new Map<String, String>{ 'id' => 'Id' };
        List<String> requested = new List<String>(getDefaultFields());
        requested.addAll(extraFields);
        for (String field : requested) {
            uniqueFields.put(field.trim().toLowerCase(), field.trim());
        }
        return uniqueFields.values();
    }
}
