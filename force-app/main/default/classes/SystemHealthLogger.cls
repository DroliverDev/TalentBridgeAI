public with sharing class SystemHealthLogger {

    public class LogContext {
        public Long startTime;
        public String className;
        public String flowName;
        public Id relatedRecordId;
        public String requestPayload;
        public String responsePayload;
        public Double StatusCode;

        public LogContext(String className) {
            this.className = className;
            this.startTime = DateTime.now().getTime();
        }
    }

    // 🔹 Create context
    public static LogContext start(String className) {
        return new LogContext(className);
    }

    // 🔹 Add optional data (fluent style)
    public static LogContext withRecord(LogContext ctx, Id recordId) {
        ctx.relatedRecordId = recordId;
        return ctx;
    }

    public static LogContext withFlow(LogContext ctx, String flowName) {
        ctx.flowName = flowName;
        return ctx;
    }

    public static LogContext withRequest(LogContext ctx, Object request) {
        ctx.requestPayload = JSON.serialize(request);
        return ctx;
    }

    public static LogContext withResponse(LogContext ctx, Object response) {
        ctx.responsePayload = JSON.serialize(response);
        return ctx;
    }

    // 🔹 Success log
    public static void success(LogContext ctx) {
        save(ctx, ctx.StatusCode, null, null);
    }

    // 🔹 Error log
    public static void error(LogContext ctx, Exception e) {
        save(ctx, ctx.StatusCode, e.getTypeName(), e.getMessage());
    }

    // 🔹 Core save logic
    private static void save(
        LogContext ctx,
        Double status,
        String errorType,
        String message
    ) {
        Long endTime = DateTime.now().getTime();

        insert new System_Health_Log__c(
            Execution_Time__c = endTime - ctx.startTime,
            CPU_Time__c = Limits.getCpuTime(),
            Heap_Size__c = Limits.getHeapSize(),
            SOQL_Queries_Count__c = Limits.getQueries(),
            Error_Type__c = errorType,
            Message__c = message,
            Status__c = status,
            Related_Record__c = ctx.relatedRecordId != null
                ? String.valueOf(ctx.relatedRecordId)
                : null,
            Related_Object_Name__c = ctx.relatedRecordId != null
                ? ctx.relatedRecordId.getSObjectType().getDescribe().getName()
                : null,
            Apex_Class_Name__c = ctx.className,
            Flow_Name__c = ctx.flowName,
            Request_Payload__c = ctx.requestPayload,
            Response_Payload__c = ctx.responsePayload
        );
    }
}