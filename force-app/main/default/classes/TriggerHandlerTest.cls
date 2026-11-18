@IsTest
private class TriggerHandlerTest {
    private class RecordingHandler extends TriggerHandler {
        public List<String> calls = new List<String>();
        protected override void beforeInsert() { calls.add('beforeInsert'); }
        protected override void beforeUpdate() { calls.add('beforeUpdate'); }
        protected override void beforeDelete() { calls.add('beforeDelete'); }
        protected override void afterInsert() { calls.add('afterInsert'); }
        protected override void afterUpdate() { calls.add('afterUpdate'); }
        protected override void afterDelete() { calls.add('afterDelete'); }
        protected override void afterUndelete() { calls.add('afterUndelete'); }
    }

    private static RecordingHandler handlerFor(TriggerOperation operation) {
        RecordingHandler handler = new RecordingHandler();
        handler.operation = operation;
        handler.objectName = 'Account';
        return handler;
    }

    private static Trigger_Setting__mdt setting(String objectApiName, Boolean active) {
        return new Trigger_Setting__mdt(Object_API_Name__c = objectApiName, Active__c = active);
    }

    @IsTest
    static void routesEveryOperationToItsMethod() {
        TriggerHandler.settingsOverride = new List<Trigger_Setting__mdt>();
        Map<TriggerOperation, String> expected = new Map<TriggerOperation, String>{
            TriggerOperation.BEFORE_INSERT => 'beforeInsert',
            TriggerOperation.BEFORE_UPDATE => 'beforeUpdate',
            TriggerOperation.BEFORE_DELETE => 'beforeDelete',
            TriggerOperation.AFTER_INSERT => 'afterInsert',
            TriggerOperation.AFTER_UPDATE => 'afterUpdate',
            TriggerOperation.AFTER_DELETE => 'afterDelete',
            TriggerOperation.AFTER_UNDELETE => 'afterUndelete'
        };
        for (TriggerOperation operation : expected.keySet()) {
            RecordingHandler handler = handlerFor(operation);
            handler.run();
            Assert.areEqual(new List<String>{ expected.get(operation) }, handler.calls);
        }
    }

    @IsTest
    static void objectWithoutSettingStaysOn() {
        TriggerHandler.settingsOverride = new List<Trigger_Setting__mdt>{ setting('Contact', false) };
        RecordingHandler handler = handlerFor(TriggerOperation.BEFORE_INSERT);
        handler.run();
        Assert.areEqual(1, handler.calls.size());
    }

    @IsTest
    static void inactiveObjectSettingStopsHandler() {
        TriggerHandler.settingsOverride = new List<Trigger_Setting__mdt>{ setting('Account', false) };
        RecordingHandler handler = handlerFor(TriggerOperation.BEFORE_INSERT);
        handler.run();
        Assert.isTrue(handler.calls.isEmpty());
    }

    @IsTest
    static void inactiveAllSettingStopsEveryHandler() {
        TriggerHandler.settingsOverride = new List<Trigger_Setting__mdt>{ setting('All', false) };
        RecordingHandler handler = handlerFor(TriggerOperation.AFTER_UPDATE);
        handler.run();
        Assert.isTrue(handler.calls.isEmpty());
    }

    @IsTest
    static void activeSettingLeavesHandlerOn() {
        TriggerHandler.settingsOverride = new List<Trigger_Setting__mdt>{ setting('Account', true) };
        RecordingHandler handler = handlerFor(TriggerOperation.AFTER_INSERT);
        handler.run();
        Assert.areEqual(1, handler.calls.size());
    }

    @IsTest
    static void bypassLastsUntilCleared() {
        TriggerHandler.settingsOverride = new List<Trigger_Setting__mdt>();
        TriggerHandler.bypass('RecordingHandler');
        RecordingHandler bypassed = handlerFor(TriggerOperation.BEFORE_INSERT);
        bypassed.run();
        Assert.isTrue(bypassed.calls.isEmpty());

        TriggerHandler.clearBypass('RecordingHandler');
        RecordingHandler restored = handlerFor(TriggerOperation.BEFORE_INSERT);
        restored.run();
        Assert.areEqual(1, restored.calls.size());

        TriggerHandler.bypass('RecordingHandler');
        TriggerHandler.clearAllBypasses();
        Assert.isFalse(TriggerHandler.isBypassed('RecordingHandler'));
    }

    @IsTest
    static void runOutsideTriggerThrows() {
        try {
            new TriggerHandler().run();
            Assert.fail('Expected an exception outside trigger context');
        } catch (TriggerHandler.TriggerHandlerException e) {
            Assert.isTrue(e.getMessage().contains('must be called from a trigger'));
        }
    }
}
