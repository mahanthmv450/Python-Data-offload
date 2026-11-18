/**
 * Base class for trigger handlers. A trigger contains one line:
 *     new AccountTriggerHandler().run();
 *
 * Admins turn triggers off with Trigger_Setting__mdt records (Setup > Custom
 * Metadata Types > Trigger Setting > Manage Records), per object or, using the
 * object name "All", for every handler. An object with no record stays on.
 */
public virtual class TriggerHandler {
    private static final String ALL_OBJECTS = 'All';
    private static Set<String> bypassedHandlers = new Set<String>();

    @TestVisible
    private static List<Trigger_Setting__mdt> settingsOverride;
    @TestVisible
    private TriggerOperation operation = Trigger.operationType;
    @TestVisible
    private String objectName;

    public void run() {
        if (operation == null) {
            throw new TriggerHandlerException('TriggerHandler.run() must be called from a trigger.');
        }
        if (isBypassed(handlerName()) || isDisabled(resolveObjectName())) {
            return;
        }
        switch on operation {
            when BEFORE_INSERT { beforeInsert(); }
            when BEFORE_UPDATE { beforeUpdate(); }
            when BEFORE_DELETE { beforeDelete(); }
            when AFTER_INSERT { afterInsert(); }
            when AFTER_UPDATE { afterUpdate(); }
            when AFTER_DELETE { afterDelete(); }
            when AFTER_UNDELETE { afterUndelete(); }
        }
    }

    /** Skips a handler for the rest of this transaction. Pass the class name. */
    public static void bypass(String handlerName) {
        bypassedHandlers.add(handlerName.toLowerCase());
    }

    public static void clearBypass(String handlerName) {
        bypassedHandlers.remove(handlerName.toLowerCase());
    }

    public static void clearAllBypasses() {
        bypassedHandlers.clear();
    }

    public static Boolean isBypassed(String handlerName) {
        return bypassedHandlers.contains(handlerName.toLowerCase());
    }

    /** True when a Trigger_Setting__mdt record turns this object, or all objects, off. */
    public static Boolean isDisabled(String sObjectApiName) {
        List<Trigger_Setting__mdt> settings = settingsOverride != null
            ? settingsOverride
            : Trigger_Setting__mdt.getAll().values();
        for (Trigger_Setting__mdt setting : settings) {
            Boolean applies = setting.Object_API_Name__c == ALL_OBJECTS
                || setting.Object_API_Name__c == sObjectApiName;
            if (applies && !setting.Active__c) {
                return true;
            }
        }
        return false;
    }

    protected virtual void beforeInsert() {}
    protected virtual void beforeUpdate() {}
    protected virtual void beforeDelete() {}
    protected virtual void afterInsert() {}
    protected virtual void afterUpdate() {}
    protected virtual void afterDelete() {}
    protected virtual void afterUndelete() {}

    private String handlerName() {
        return String.valueOf(this).substringBefore(':');
    }

    private String resolveObjectName() {
        if (objectName == null) {
            List<SObject> records = Trigger.new != null ? Trigger.new : Trigger.old;
            objectName = String.valueOf(records[0].getSObjectType());
        }
        return objectName;
    }

    public class TriggerHandlerException extends Exception {}
}
