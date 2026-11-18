trigger ApiLogEventTrigger on API_Log_Event__e (after insert) {
    ApiLogEventHandler.handle(Trigger.new);
}
