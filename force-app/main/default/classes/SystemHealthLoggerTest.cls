@IsTest
private class SystemHealthLoggerTest {

    // Helper to query last created log
    private static System_Health_Log__c getLatestLog() {
        return [
            SELECT Id,
                   Execution_Time__c,
                   CPU_Time__c,
                   Heap_Size__c,
                   SOQL_Queries_Count__c,
                   Error_Type__c,
                   Message__c,
                   Status__c,
                   Related_Record__c,
                   Related_Object_Name__c,
                   Apex_Class_Name__c,
                   Flow_Name__c,
                   Request_Payload__c,
                   Response_Payload__c,
                   CreatedDate
            FROM System_Health_Log__c
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    @IsTest
    static void testSuccessMinimalContext() {
        // Arrange
        SystemHealthLogger.LogContext ctx = SystemHealthLogger.start('MinimalClass');

        // Act
        Test.startTest();
        SystemHealthLogger.success(ctx);
        Test.stopTest();

        // Assert
        System_Health_Log__c log = getLatestLog();
        System.assertNotEquals(null, log.Id, 'Log should be inserted');
        System.assertEquals('MinimalClass', log.Apex_Class_Name__c, 'Class name must be stored');
        System.assertEquals(null, log.Flow_Name__c, 'Flow name should be null for minimal');
        System.assertEquals(null, log.Error_Type__c, 'No error expected');
        System.assertEquals(null, log.Message__c, 'No error message expected');
        System.assertEquals(null, log.Status__c, 'Status remains null if not set on context');
        System.assertNotEquals(null, log.Execution_Time__c, 'Execution time should be populated');
        System.assert(log.Execution_Time__c >= 0, 'Execution time should be non-negative');
        System.assertNotEquals(null, log.CPU_Time__c, 'CPU time should be captured');
        System.assertNotEquals(null, log.Heap_Size__c, 'Heap size should be captured');
        System.assertNotEquals(null, log.SOQL_Queries_Count__c, 'SOQL count should be captured');
        System.assertEquals(null, log.Related_Record__c, 'No related record expected');
        System.assertEquals(null, log.Related_Object_Name__c, 'No related object expected');
        System.assertEquals(null, log.Request_Payload__c, 'No request payload expected');
        System.assertEquals(null, log.Response_Payload__c, 'No response payload expected');
    }

    @IsTest
    static void testSuccessWithAllOptionalData() {
        // Arrange - create a record to reference
        Account a = new Account(Name = 'Test Acc');
        insert a;

        // Build a sample request/response structure
        Map<String, Object> request = new Map<String, Object>{
            'op' => 'create',
            'value' => 5
        };
        List<String> response = new List<String>{ 'ok', 'done' };

        SystemHealthLogger.LogContext ctx = SystemHealthLogger.start('FullClass');
        // Set a status code and optional attributes
        ctx.StatusCode = 200.0;
        ctx = SystemHealthLogger.withRecord(ctx, a.Id);
        ctx = SystemHealthLogger.withFlow(ctx, 'Sample_Flow');
        ctx = SystemHealthLogger.withRequest(ctx, request);
        ctx = SystemHealthLogger.withResponse(ctx, response);

        // Act
        Test.startTest();
        SystemHealthLogger.success(ctx);
        Test.stopTest();

        // Assert
        System_Health_Log__c log = getLatestLog();
        System.assertEquals('FullClass', log.Apex_Class_Name__c);
        System.assertEquals('Sample_Flow', log.Flow_Name__c);
        System.assertEquals(200.0, log.Status__c, 'Status code persisted');

        System.assertEquals(String.valueOf(a.Id), log.Related_Record__c, 'Related record id should be stringified');
        System.assertEquals('Account', log.Related_Object_Name__c, 'Object name should be derived from Id type');

        // Validate payloads are JSON serialized
        System.assert(log.Request_Payload__c != null && log.Request_Payload__c.contains('"op"'), 'Request JSON should contain key');
        System.assert(log.Response_Payload__c != null && log.Response_Payload__c.contains('ok'), 'Response JSON should contain value');

        // Limits and times captured
        System.assertNotEquals(null, log.Execution_Time__c);
        System.assertNotEquals(null, log.CPU_Time__c);
        System.assertNotEquals(null, log.Heap_Size__c);
        System.assertNotEquals(null, log.SOQL_Queries_Count__c);
    }

    @IsTest
    static void testErrorPathCapturesTypeAndMessage() {
        // Arrange
        SystemHealthLogger.LogContext ctx = SystemHealthLogger.start('ErrorClass');
        ctx.StatusCode = 500.0;

        // Create a controlled exception
        Exception ex;
        try {
            // Intentionally cause DML exception (required field missing)
            insert new Account(); // Name is required -> will throw
        } catch (Exception e) {
            ex = e;
        }
        System.assertNotEquals(null, ex, 'Expected an exception to be thrown');

        // Act
        Test.startTest();
        SystemHealthLogger.error(ctx, ex);
        Test.stopTest();

        // Assert
        System_Health_Log__c log = getLatestLog();
        System.assertEquals('ErrorClass', log.Apex_Class_Name__c);
        System.assertEquals(500.0, log.Status__c, 'Status code persisted on error');
        System.assertNotEquals(null, log.Error_Type__c, 'Error type should be captured');
        System.assertNotEquals(null, log.Message__c, 'Error message should be captured');
        System.assert(log.Error_Type__c.contains('DmlException') || log.Error_Type__c.endsWith('Exception'),
                      'Should capture an exception type');
        System.assert(log.Message__c != null && log.Message__c.length() > 0, 'Message should have content');
    }

    @IsTest
    static void testWithRecordHandlesNullsGracefully() {
        // Arrange
        SystemHealthLogger.LogContext ctx = SystemHealthLogger.start('NullRecordClass');
        // Explicitly do not set record id
        ctx.StatusCode = 204.0;

        // Act
        Test.startTest();
        SystemHealthLogger.success(ctx);
        Test.stopTest();

        // Assert
        System_Health_Log__c log = getLatestLog();
        System.assertEquals('NullRecordClass', log.Apex_Class_Name__c);
        System.assertEquals(204.0, log.Status__c);
        System.assertEquals(null, log.Related_Record__c, 'Related record should remain null');
        System.assertEquals(null, log.Related_Object_Name__c, 'Related object should remain null');
    }

    @IsTest
    static void testBulkMultipleLogs() {
        // Arrange
        Integer N = 5;
        List<SystemHealthLogger.LogContext> contexts = new List<SystemHealthLogger.LogContext>();
        for (Integer i = 0; i < N; i++) {
            SystemHealthLogger.LogContext c = SystemHealthLogger.start('BulkClass' + i);
            c.StatusCode = 200.0 + i;
            contexts.add(c);
        }

        // Act
        Test.startTest();
        for (SystemHealthLogger.LogContext c : contexts) {
            SystemHealthLogger.success(c);
        }
        Test.stopTest();

        // Assert - check count increased by N
        Integer count = [SELECT COUNT() FROM System_Health_Log__c];
        System.assert(count >= N, 'At least N logs should have been inserted in this test context');
    }
}