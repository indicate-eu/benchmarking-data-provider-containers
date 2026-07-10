library "TimePeriods" version '1.0.0'

using OMOP version 'v5.4'

include OMOPHelpers
include LocalTimeGermany called L
include IndicateQiElements called E

/// Shifts

// Parameters for controlling the timing of shifts.  Note that the indicator is
// specified as follows:
//
//   Each day is divided into 3 shifts/periods per days:
//   - 06:00:00 to 13:59:59
//   - 14:00:00 to 21:59:59
//   - 22:00:00 to 05:59:59
//
// So there should normally be no reason to change these values.
parameter "Shift Start within Day" Quantity default 6 hours
parameter "Shift Duration"         Quantity default 8 'h'

// The configured shift duration must divide 24 so that a full 24-hour
// period can contain a whole number of shifts if aligned correctly.
// The correct alignment is ensured by starting 24-hour periods at the
// same start time as the first shift.
define "Verified Shift Duration":
  if (24 hours mod "Shift Duration") != 0 hours then
    Message(null, true, '400', 'Error',
            'Shift duration must divide 24; '
            + ToString("Shift Duration".value)
            + ' does not divide 24.')
  else
    "Shift Duration"

context Patient

define function "Shifts during Period with Duration"(period Interval<DateTime>, shiftDuration Quantity):
  (1) _
    let periodStartDay:  date from start of period,
        periodEnd:       end of period,
        firstShiftStart: L.ExpandDateToDateTime(periodStartDay) + "Shift Start within Day"
      return if firstShiftStart before periodEnd then
               (Expand(Interval[firstShiftStart, periodEnd], shiftDuration)) s
                 let shift: Interval[s, s + shiftDuration)
                   where shift included in period
                   return all shift
             else
               {} as List<Interval<DateTime>>

define function "Shifts during Period"(period Interval<DateTime>):
  (1) _
    let shiftDuration: Quantity{
                         value: (convert "Verified Shift Duration" to 's').value,
                         unit:  'seconds'
                       }
      return "Shifts during Period with Duration"(period, shiftDuration)

// Note: currently unused
define function "Shifts during Periods"(periods List<Interval<DateTime>>):
  (1) _
    let shiftDuration: Quantity{
                         value: (convert "Verified Shift Duration" to 's').value,
                         unit:  'seconds'
                       }
      return (periods) period
               return all "Shifts during Period with Duration"(
                            period,
                            shiftDuration
                          )

// Note: currently unused
define "Shifts in Visits":
  "Shifts during Periods"(E."Intensive Care Visits in Review Period")

/// 24-hour Periods

// Each 24-hour period starts at 6:00 and ends 24 h later at 5:59 of the
// following day.  All periods of this kind that overlap the given period
// are initially generated even though some of those at the beginning
// and at the end of the visit may not be used due to exclusion rules.
define function "24-hour Periods overlapping Period"(periodInterval Interval<DateTime>):
  (1) _
    let dayDuration:      Quantity{
                            value: (convert 1 'd' to 's').value,
                            unit:  'seconds'
                          },
        periodStart:      start of periodInterval,
        periodEnd:        end of periodInterval,
        periodStartDay:   date from periodStart,
        // Align start of 24-hour periods with the start of the first shift.
        // See comment above "Verified Shift Duration" regarding duration of
        // shifts and 24-hour periods.
        maybeExpandStart: L.ExpandDateToDateTime(periodStartDay)
                          + "Shift Start within Day",
        // If the time (within the day) of periodStart is before the
        // time of maybeExpandStart, using maybeExpandStart in Expand
        // would produce a first Interval that omits the time from
        // periodStart to maybeExpandStart.  To include that time in the
        // first interval, extend the "expand interval" by 24 hours if
        // appropriate.
        expandStart:      if periodStart before maybeExpandStart then
                            maybeExpandStart - dayDuration
                          else
                            maybeExpandStart,
        expandEnd:        periodEnd + dayDuration
      return if expandStart before expandEnd then
               // "Expand" the "expand interval" into a list of start
               // points for 24-hour intervals.  Then transform each
               // start point into the corresponding 24-hour interval.
               (Expand(Interval[expandStart, expandEnd], dayDuration)) s
                 where not (s = periodEnd)
                 return all Interval[s, s + dayDuration)
             else
               // Without the casts, the CQL engine does not know that
               // the two legs of the if have the same type.
               {} as List<Interval<DateTime>>

// Note: currently unused
define function "24-hour Periods overlapping Visits"(visits List<Interval<DateTime>>):
  (visits) v
    let periods: "24-hour Periods overlapping Period"(v)
      where Exists(periods)
      return all periods

// Note: currently unused
define "24-hour Periods in Visits":
  "24-hour Periods overlapping Visits"(E."Intensive Care Visits in Review Period")

/// Visits

define "Intensive Care Visits overlapping Review Period":
  E."Intensive Care Visits" v
    where v overlaps E."Review Period"
    return all v

define function "Visits and 24-hour Periods"(visits List<Interval<DateTime>>):
  (visits) v
    let periods: "24-hour Periods overlapping Period"(v)
      where Exists(periods)
      return all {visit: v, periods: periods}

// Return a list which contains for each visit in the given visits a
// triple of the visit, "overlapping" 24-hour periods and "fully
// contained" 24-hour periods.  Visits for which none of those periods
// are within the given considered period are excluded from the returned
// list of triples.
//
// An "overlapping" 24-hour period is an Interval that starts at the
// configured "Shift Start within Day" and has a duration of 24-hour
// hours.  All returned "overlapping" 24-hour periods overlap the
// temporal period of the corresponding visit and overlap the considered
// period.
//
// An "fully contained" 24-hour period is an Interval that starts at
// the configured "Shift Start within Day" and has a duration of 24-hour
// hours.  All returned "fully contained" 24-hour periods are contained
// in the temporal period of the corresponding visit and are contained in
// the considered period.
define function "Visits and 24-hour Periods during Period"(
    visits       List<Interval<DateTime>>,
    consideredPeriod Interval<DateTime>
  ):
  Flatten(
    (visits) visit
      let overlappingPeriods: "24-hour Periods overlapping Period"(visit)
        where Exists(overlappingPeriods)
        return all (1) _
                     let fullyContainedPeriods: (overlappingPeriods) p
                                                  where     (p during visit)
                                                        and (p during consideredPeriod)
                                                  return all p
                       return if Exists(fullyContainedPeriods) then
                               { {
                                  visit:                 visit,
                                  overlappingPeriods:    overlappingPeriods,
                                  fullyContainedPeriods: fullyContainedPeriods
                                } }
                              else
                                // Without the casts, the CQL engine
                                // does not know that the two legs of
                                // the if have the same type.
                                ({} as List<Tuple{visit                 Interval<DateTime>,
                                                  overlappingPeriods    List<Interval<DateTime>>,
                                                  fullyContainedPeriods List<Interval<DateTime>>}>)
  )

define "Visits with 24-hour Periods":
  "Visits and 24-hour Periods during Period"("Intensive Care Visits overlapping Review Period", E."Review Period")
