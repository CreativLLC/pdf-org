@IsTest
private class ContactPhoneNormalizer_Test {

    private static final String EXPECTED = '(555) 123-4567';

    @IsTest
    static void phone_normalize_10digit_formats() {
        Contact c = ContactUtils.generateContact(null, false);
        c.Phone = '5551234567';

        Test.startTest();
        insert c;
        Test.stopTest();

        Contact reloaded = [SELECT Phone FROM Contact WHERE Id = :c.Id];
        System.assertEquals(EXPECTED, reloaded.Phone,
            'Raw 10-digit phone should be formatted to (XXX) XXX-XXXX');
    }

    @IsTest
    static void phone_normalize_11digit_leadingOne_dropsAndFormats() {
        Contact c = ContactUtils.generateContact(null, false);
        c.Phone = '1-555-123-4567';

        Test.startTest();
        insert c;
        Test.stopTest();

        Contact reloaded = [SELECT Phone FROM Contact WHERE Id = :c.Id];
        System.assertEquals(EXPECTED, reloaded.Phone,
            '11-digit phone starting with 1 should have the leading 1 dropped and be formatted');
    }

    @IsTest
    static void phone_normalize_alreadyFormatted_isIdempotent() {
        Contact c = ContactUtils.generateContact(null, false);
        c.Phone = EXPECTED;

        Test.startTest();
        insert c;
        // re-save to exercise the before-update path too
        c.Phone = EXPECTED;
        update c;
        Test.stopTest();

        Contact reloaded = [SELECT Phone FROM Contact WHERE Id = :c.Id];
        System.assertEquals(EXPECTED, reloaded.Phone,
            'Already-formatted phone should round-trip unchanged through insert and update');
    }

    @IsTest
    static void phone_normalize_emptyOrNull_unchanged() {
        Contact nullPhone = ContactUtils.generateContact(null, false);
        nullPhone.Phone = null;

        Contact emptyPhone = ContactUtils.generateContact(null, false);
        emptyPhone.Phone = '';

        Test.startTest();
        insert new List<Contact>{ nullPhone, emptyPhone };
        Test.stopTest();

        Contact reloadedNull = [SELECT Phone FROM Contact WHERE Id = :nullPhone.Id];
        Contact reloadedEmpty = [SELECT Phone FROM Contact WHERE Id = :emptyPhone.Id];
        System.assertEquals(null, reloadedNull.Phone,
            'Null phone should remain null');
        // Salesforce normalizes empty strings on Contact.Phone to null on persistence;
        // either null or empty is acceptable — both signal "no change applied".
        System.assert(reloadedEmpty.Phone == null || reloadedEmpty.Phone == '',
            'Empty-string phone should not be transformed');
    }

    @IsTest
    static void phone_normalize_international_unchanged() {
        String intl = '+44 20 7946 0958';
        Contact c = ContactUtils.generateContact(null, false);
        c.Phone = intl;

        Test.startTest();
        insert c;
        Test.stopTest();

        Contact reloaded = [SELECT Phone FROM Contact WHERE Id = :c.Id];
        System.assertEquals(intl, reloaded.Phone,
            'International phone (not 10 or 11-with-leading-1 digits) should pass through unchanged');
    }

    @IsTest
    static void phone_normalize_bulk200_mixedShapes_allCorrectlyNormalized() {
        String formatted = '(555) 123-4567';
        String intl = '+44 20 7946 0958';

        List<Contact> contacts = new List<Contact>();
        Map<Integer, String> expectedByIndex = new Map<Integer, String>();

        for (Integer i = 0; i < 200; i++) {
            Contact c = ContactUtils.generateContact(null, false);
            Integer shape = Math.mod(i, 5);
            if (shape == 0) {
                c.Phone = '5551234567';
                expectedByIndex.put(i, formatted);
            } else if (shape == 1) {
                c.Phone = '1-555-123-4567';
                expectedByIndex.put(i, formatted);
            } else if (shape == 2) {
                c.Phone = formatted;
                expectedByIndex.put(i, formatted);
            } else if (shape == 3) {
                c.Phone = intl;
                expectedByIndex.put(i, intl);
            } else {
                c.Phone = null;
                expectedByIndex.put(i, null);
            }
            contacts.add(c);
        }

        Test.startTest();
        insert contacts;
        Test.stopTest();

        // Re-query: before-trigger mutations are persisted, but the in-memory
        // caller list does not reliably reflect them. The database is the
        // source of truth.
        Map<Id, Contact> reloaded = new Map<Id, Contact>(
            [SELECT Id, Phone FROM Contact WHERE Id IN :contacts]
        );
        for (Integer i = 0; i < 200; i++) {
            Contact stored = reloaded.get(contacts[i].Id);
            System.assertNotEquals(null, stored,
                'Row ' + i + ' should be persisted (Id=' + contacts[i].Id + ')');
            System.assertEquals(expectedByIndex.get(i), stored.Phone,
                'Bulk row ' + i + ' (shape ' + Math.mod(i, 5) + ') should normalize as expected');
        }
    }
}
