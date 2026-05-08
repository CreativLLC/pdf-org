public with sharing class UtilNinja {

	public static Integer offsetToPreviousMonday(String dayName){
		switch on dayName {
			when 'Tuesday' {
				return -1;
			}
			when 'Wednesday' {
				return -2;
			}
			when 'Thursday' {
				return -3;
			}
			when 'Friday' {
				return -4;
			}
			when 'Saturday' {
				return -5;
			}
			when 'Sunday' {
				return -6;
			}
			when else {
				return 0;
			}
		}
	}

	public static DateTime findPreviousMonday(DateTime targetDateTime){
		String dayOfWeek = targetDateTime.formatGmt('EEEE');
		Integer offset = UtilNinja.offsetToPreviousMonday(dayOfWeek);
		return targetDateTime.addDays(offset);
	}

	public static Decimal smartValue(Decimal dec)
	{
		if(dec == null)
			return 0.00;
		else
			return dec;
	}
	
	public static Decimal smartValue(String str)
	{
		if(str == null)
			return 0.00;
		else
			return Decimal.valueOf(str);
	}
    
    public static Date convertTempoDateString(String dateString){
        Date returnDate;
        if(dateString != null){
            List<String> dateStrings = dateString.split(' ');
            if(dateStrings.size() == 2){
                List<String> dateComponents = dateStrings[0].split('-');
                if(dateComponents.size() == 3){
                    dateComponents[0] = dateComponents[0].length() == 1 ? '0' + dateComponents[0] : dateComponents[0];
                    dateComponents[1] = dateComponents[1].length() == 1 ? '0' + dateComponents[1] : dateComponents[1];
                    dateComponents[2] = dateComponents[2].length() == 1 ? '0' + dateComponents[2] : dateComponents[2];
                    String formattedString = dateComponents[0] + '-' + dateComponents[1] + '-' + dateComponents[2];
                    returnDate = Date.valueOf(formattedString);
                }
            }
        }
        return returnDate;
    }
}