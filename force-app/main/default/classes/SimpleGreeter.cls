public with sharing class SimpleGreeter {
    public static String greet(String name) {
        if (String.isBlank(name)) {
            return 'Hello, friend!';
        }
        return 'Hello, ' + name + '!';
    }
}
