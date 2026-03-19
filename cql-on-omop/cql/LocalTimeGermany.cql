library LocalTimeGermany version '1.0.0'

// From https://watches.uhrzeit.org/daylight-savings-schedule
define SummerTimesGermany:
  {
    Interval[@2026-03-29T02:00:00+01:00,@2026-10-25T03:00:00+02:00],
    Interval[@2025-03-30T02:00:00+01:00,@2025-10-26T03:00:00+02:00],
    Interval[@2024-03-31T02:00:00+01:00,@2024-10-27T03:00:00+02:00],
    Interval[@2023-03-26T02:00:00+01:00,@2023-10-29T03:00:00+02:00],
    Interval[@2022-03-27T02:00:00+01:00,@2022-10-30T03:00:00+02:00],
    Interval[@2021-03-28T02:00:00+01:00,@2021-10-31T03:00:00+02:00],
    Interval[@2020-03-29T02:00:00+01:00,@2020-10-25T03:00:00+02:00],
    Interval[@2019-03-31T02:00:00+01:00,@2019-10-27T03:00:00+02:00],
    Interval[@2018-03-25T02:00:00+01:00,@2018-10-28T03:00:00+02:00],
    Interval[@2017-03-26T02:00:00+01:00,@2017-10-29T03:00:00+02:00],
    Interval[@2016-03-27T02:00:00+01:00,@2016-10-30T03:00:00+02:00],
    Interval[@2015-03-29T02:00:00+01:00,@2015-10-25T03:00:00+02:00],
    Interval[@2014-03-30T02:00:00+01:00,@2014-10-26T03:00:00+02:00],
    Interval[@2013-03-31T02:00:00+01:00,@2013-10-27T03:00:00+02:00],
    Interval[@2012-03-25T02:00:00+01:00,@2012-10-28T03:00:00+02:00],
    Interval[@2011-03-27T02:00:00+01:00,@2011-10-30T03:00:00+02:00],
    Interval[@2010-03-28T02:00:00+01:00,@2010-10-31T03:00:00+02:00],
    Interval[@2009-03-29T02:00:00+01:00,@2009-10-25T03:00:00+02:00],
    Interval[@2008-03-30T02:00:00+01:00,@2008-10-26T03:00:00+02:00],
    Interval[@2007-03-25T02:00:00+01:00,@2007-10-28T03:00:00+02:00],
    Interval[@2006-03-26T02:00:00+01:00,@2006-10-29T03:00:00+02:00],
    Interval[@2005-03-27T02:00:00+01:00,@2005-10-30T03:00:00+02:00],
    Interval[@2004-03-28T02:00:00+01:00,@2004-10-31T03:00:00+02:00],
    Interval[@2003-03-30T02:00:00+01:00,@2003-10-26T03:00:00+02:00],
    Interval[@2002-03-31T02:00:00+01:00,@2002-10-27T03:00:00+02:00],
    Interval[@2001-03-25T02:00:00+01:00,@2001-10-28T03:00:00+02:00],
    Interval[@2000-03-26T02:00:00+01:00,@2000-10-29T03:00:00+02:00],
    Interval[@1999-03-28T02:00:00+01:00,@1999-10-31T03:00:00+02:00],
    Interval[@1998-03-29T02:00:00+01:00,@1998-10-25T03:00:00+02:00],
    Interval[@1997-03-30T02:00:00+01:00,@1997-10-26T03:00:00+02:00],
    Interval[@1996-03-31T02:00:00+01:00,@1996-10-27T03:00:00+02:00],
    Interval[@1995-03-26T02:00:00+01:00,@1995-09-24T03:00:00+02:00],
    Interval[@1994-03-27T02:00:00+01:00,@1994-09-25T03:00:00+02:00],
    Interval[@1993-03-28T02:00:00+01:00,@1993-09-26T03:00:00+02:00],
    Interval[@1992-03-29T02:00:00+01:00,@1992-09-27T03:00:00+02:00],
    Interval[@1991-03-31T02:00:00+01:00,@1991-09-29T03:00:00+02:00],
    Interval[@1990-03-25T02:00:00+01:00,@1990-09-30T03:00:00+02:00],
    Interval[@1989-03-26T02:00:00+01:00,@1989-09-24T03:00:00+02:00],
    Interval[@1988-03-27T02:00:00+01:00,@1988-09-25T03:00:00+02:00],
    Interval[@1987-03-29T02:00:00+01:00,@1987-09-27T03:00:00+02:00],
    Interval[@1986-03-30T02:00:00+01:00,@1986-09-28T03:00:00+02:00],
    Interval[@1985-03-31T02:00:00+01:00,@1985-09-29T03:00:00+02:00],
    Interval[@1984-03-25T02:00:00+01:00,@1984-09-30T03:00:00+02:00],
    Interval[@1983-03-27T02:00:00+01:00,@1983-09-25T03:00:00+02:00],
    Interval[@1982-03-28T02:00:00+01:00,@1982-09-26T03:00:00+02:00],
    Interval[@1981-03-29T02:00:00+01:00,@1981-09-27T03:00:00+02:00],
    Interval[@1980-04-06T02:00:00+01:00,@1980-09-28T03:00:00+02:00]
  }

define function LocalTimezoneOffset(dateTime DateTime):
  if Exists(SummerTimesGermany summerTime where summerTime contains dateTime) then
    2
  else
    1

define function LocalTimezoneOffset(dateTime Date):
  if Exists(SummerTimesGermany summerTime where summerTime contains dateTime) then
    2
  else
    1

/// Conversion to local timezone

define function ToLocalTimezone(dateTime DateTime):
  (1) _
    let TimezoneOffset: LocalTimezoneOffset(dateTime),
        LocalDateTime:  dateTime
                        - Quantity{value: timezoneoffset from dateTime,
                                   unit:  'hour'}
                        + Quantity{value: TimezoneOffset,
                                   unit:  'hour'},
        // We have to be careful to not let a millisecond of null slip through
        // here because if that happens, TimezoneOffset will be silently(!)
        // ignore.
        Millisecond:    if millisecond from LocalDateTime is null then
                          0
                        else
                          millisecond from LocalDateTime
      return DateTime(year        from LocalDateTime,
                      month       from LocalDateTime,
                      day         from LocalDateTime,
                      hour        from LocalDateTime,
                      minute      from LocalDateTime,
                      second      from LocalDateTime,
                      Millisecond,
                      TimezoneOffset)

// If we used `convert date to DateTime` instead, we would get the
// same result as long as the timezone was configured as CET. In case of
// a different timezone configuration, the result would be the same
// except for a different timezoneoffset which is not the same at all,
// really.
define function ExpandDateToDateTime(date Date):
  DateTime(year from date,
           month from date,
           day from date,
           0, // hour
           0, // minute
           0, // second
           0, // millisecond
           LocalTimezoneOffset(date))
