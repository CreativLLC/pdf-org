@IsTest
private class SimpleGreeter_Test {
    @IsTest
    static void testGreetWithName() {
        System.assertEquals('Hello, World!', SimpleGreeter.greet('World'));
    }

    @IsTest
    static void testGreetWithNullOrBlank() {
        System.assertEquals('Hello, friend!', SimpleGreeter.greet(null));
        System.assertEquals('Hello, friend!', SimpleGreeter.greet(''));
        System.assertEquals('Hello, friend!', SimpleGreeter.greet('   '));
    }
}
