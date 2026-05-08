/**
 * Created by charl on 2/20/2024.
 */

@IsTest
private class UtilNinjaTest {
    public static testMethod void testSmartValue()
    {
        String testStringInp;
        Decimal testDecInp;
        Decimal testDec = UtilNinja.smartValue(testStringInp);
        System.assertEquals(testDec, 0);
        testDec = UtilNinja.smartValue(testDecInp);
        System.assertEquals(testDec, 0);
        testDec = UtilNinja.smartValue(5);
        System.assertEquals(testDec, 5);
        testDec = UtilNinja.smartValue('5');
        System.assertEquals(testDec, 5);
    }
    
    public static testMethod void testTempoDateString()
    {
        String tempoDateString = '2025-08-22 8:30';
        Date convertedDate = UtilNinja.convertTempoDateString(tempoDateString);
        System.assertEquals(convertedDate, Date.newInstance(2025, 8, 22));
        
    }
    public static testMethod void testFindPreviousMonday()
    {
        Datetime previousMonday = UtilNinja.findPreviousMonday(Datetime.newInstance(2025, 12, 25, 10, 30, 0));
        System.assertEquals(previousMonday.date(), Date.newInstance(2025, 12, 22));
    }
}