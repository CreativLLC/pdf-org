public with sharing class ContactPhoneNormalizer {

    @TestVisible
    private static final Pattern NON_DIGIT = Pattern.compile('\\D');

    public static void normalize(List<Contact> contacts) {
        if (contacts == null || contacts.isEmpty()) {
            return;
        }
        for (Contact c : contacts) {
            String formatted = formatPhone(c.Phone);
            if (formatted != null) {
                c.Phone = formatted;
            }
        }
    }

    @TestVisible
    private static String formatPhone(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String digits = NON_DIGIT.matcher(raw).replaceAll('');
        if (digits.length() == 11 && digits.startsWith('1')) {
            digits = digits.substring(1);
        }
        if (digits.length() != 10) {
            return null;
        }
        return '(' + digits.substring(0, 3) + ') '
             + digits.substring(3, 6) + '-'
             + digits.substring(6, 10);
    }
}
