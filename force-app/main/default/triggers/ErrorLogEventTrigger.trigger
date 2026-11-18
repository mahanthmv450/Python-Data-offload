trigger ErrorLogEventTrigger on Error_Log_Event__e (after insert) {
    ErrorLogEventHandler.handle(Trigger.new);
}
